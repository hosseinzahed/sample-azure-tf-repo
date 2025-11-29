terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-vm-snoozing-automation"
}

variable "location" {
  description = "Azure location for resources"
  type        = string
  default     = "Sweden Central"
}

variable "automation_account_name" {
  description = "Name of the Automation Account"
  type        = string
  default     = "aa-vm-snoozing-automation"
}

variable "runbook_name" {
  description = "Name of the PowerShell runbook"
  type        = string
  default     = "rb-vm-snoozing-automation"
}

variable "stop_schedule_name" {
  description = "Name of the stop schedule"
  type        = string
  default     = "schedule-stop-vm-snoozing-automation"
}

variable "start_schedule_name" {
  description = "Name of the start schedule"
  type        = string
  default     = "schedule-start-vm-snoozing-automation"
}

variable "vm_tag_filter" {
  description = "Map of VM tag filter"
  type = map(string)
  default = {
    AutoSnooze = "true"
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "vm_snoozing" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Purpose     = "VM Snoozing Automation"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_automation_account" "vm_snoozing" {
  name                = var.automation_account_name
  location            = azurerm_resource_group.vm_snoozing.location
  resource_group_name = azurerm_resource_group.vm_snoozing.name
  sku                 = "Basic"
  identity {
    type = "SystemAssigned"
  }

  tags = azurerm_resource_group.vm_snoozing.tags
}

resource "azurerm_role_assignment" "vm_contributor" {
  scope              = data.azurerm_subscription.current.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id       = azurerm_automation_account.vm_snoozing.identity[0].principal_id

  depends_on = [azurerm_automation_account.vm_snoozing]
}

resource "azurerm_automation_runbook" "vm_snoozing" {
  name                    = var.runbook_name
  location                = azurerm_resource_group.vm_snoozing.location
  resource_group_name     = azurerm_resource_group.vm_snoozing.name
  automation_account_name = azurerm_automation_account.vm_snoozing.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"

  content = <<-EOT
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Start','Stop')]
    [string]$Action,
    [string]$ResourceGroupName = $null,
    [string]$VMNames = $null,
    [string]$TagName = "AutoSnooze",
    [string]$TagValue = "true"
)

try {
    Write-Output "Starting VM Snoozing Automation runbook with action: $Action"

    Connect-AzAccount -Identity

    $vmList = @()

    if ($null -ne $VMNames) {
        $names = $VMNames -split ',' | ForEach-Object { $_.Trim() }
        foreach ($name in $names) {
            $vm = Get-AzVM -Name $name -ErrorAction SilentlyContinue
            if ($null -ne $vm) { $vmList += $vm }
        }
    }
    elseif ($null -ne $ResourceGroupName) {
        $vmList = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object {
            $tags = $_.Tags
            $tags[$TagName] -eq $TagValue
        }
    }
    else {
        $vmList = Get-AzVM -Status | Where-Object {
            $_.Tags[$TagName] -eq $TagValue
        }
    }

    $successCount = 0
    $failureCount = 0
    $skippedCount = 0

    foreach ($vm in $vmList) {
        $vmStatus = $vm.PowerState
        $vmName = $vm.Name

        try {
            if ($Action -eq 'Stop') {
                if ($vmStatus -eq 'VM running') {
                    Write-Output "Stopping VM: $vmName"
                    Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vmName -Force
                    $successCount++
                } else {
                    Write-Output "Skipping VM $vmName as it is not running"
                    $skippedCount++
                }
            } elseif ($Action -eq 'Start') {
                if ($vmStatus -eq 'VM deallocated') {
                    Write-Output "Starting VM: $vmName"
                    Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vmName
                    $successCount++
                } else {
                    Write-Output "Skipping VM $vmName as it is already running or in invalid state"
                    $skippedCount++
                }
            }
        } catch {
            Write-Warning "Failed to process VM $vmName: $_"
            $failureCount++
        }
    }

    Write-Output "VM Snoozing Automation completed. Success: $successCount, Failures: $failureCount, Skipped: $skippedCount"
} catch {
    Write-Error "Runbook execution failed: $_"
    throw
}
EOT

  depends_on = [azurerm_automation_account.vm_snoozing, azurerm_role_assignment.vm_contributor]
}

resource "azurerm_automation_schedule" "stop_schedule" {
  name                    = var.stop_schedule_name
  resource_group_name     = azurerm_resource_group.vm_snoozing.name
  automation_account_name = azurerm_automation_account.vm_snoozing.name
  frequency               = "Week"
  interval                = 1
  timezone                = "W. Europe Standard Time"
  start_time              = timeadd(timestamp(), "24h")
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  description             = "Stop VMs every weekday at 6 PM"
}

resource "azurerm_automation_schedule" "start_schedule" {
  name                    = var.start_schedule_name
  resource_group_name     = azurerm_resource_group.vm_snoozing.name
  automation_account_name = azurerm_automation_account.vm_snoozing.name
  frequency               = "Week"
  interval                = 1
  timezone                = "W. Europe Standard Time"
  start_time              = timeadd(timestamp(), "24h")
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  description             = "Start VMs every weekday at 8 AM"
}

resource "azurerm_automation_job_schedule" "stop_job_schedule" {
  automation_account_name = azurerm_automation_account.vm_snoozing.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing.name
  schedule_name           = azurerm_automation_schedule.stop_schedule.name
  resource_group_name     = azurerm_resource_group.vm_snoozing.name

  parameters = {
    Action   = "Stop"
    TagName  = "AutoSnooze"
    TagValue = "true"
  }

  depends_on = [azurerm_automation_runbook.vm_snoozing, azurerm_automation_schedule.stop_schedule]
}

resource "azurerm_automation_job_schedule" "start_job_schedule" {
  automation_account_name = azurerm_automation_account.vm_snoozing.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing.name
  schedule_name           = azurerm_automation_schedule.start_schedule.name
  resource_group_name     = azurerm_resource_group.vm_snoozing.name

  parameters = {
    Action   = "Start"
    TagName  = "AutoSnooze"
    TagValue = "true"
  }

  depends_on = [azurerm_automation_runbook.vm_snoozing, azurerm_automation_schedule.start_schedule]
}

output "automation_account_id" {
  value       = azurerm_automation_account.vm_snoozing.id
  description = "ID of the Automation Account"
}

output "automation_account_name" {
  value       = azurerm_automation_account.vm_snoozing.name
  description = "Name of the Automation Account"
}

output "managed_identity_principal_id" {
  value       = azurerm_automation_account.vm_snoozing.identity[0].principal_id
  description = "Principal ID of the managed identity"
}

output "runbook_name" {
  value       = azurerm_automation_runbook.vm_snoozing.name
  description = "Name of the PowerShell runbook"
}

output "resource_group_name" {
  value       = azurerm_resource_group.vm_snoozing.name
  description = "Name of the resource group"
}

output "stop_schedule_name" {
  value       = azurerm_automation_schedule.stop_schedule.name
  description = "Name of the stop schedule"
}

output "start_schedule_name" {
  value       = azurerm_automation_schedule.start_schedule.name
  description = "Name of the start schedule"
}
