# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.vm_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = "${var.vm_name}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "${var.vm_name}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
  tags                = var.tags
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Connect NSG to NIC
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = var.vm_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  disable_password_authentication = true
}

# ============================================================================
# VM Snoozing Automation Infrastructure
# ============================================================================

# Data Sources
data "azurerm_client_config" "current_vm_snoozing_automation" {}

data "azurerm_subscription" "current_vm_snoozing_automation" {}

# Resource Group for VM Snoozing Automation
resource "azurerm_resource_group" "vm_snoozing_automation" {
  name     = "rg-vm-snoozing-automation"
  location = "Sweden Central"
}

# Automation Account for VM Snoozing
resource "azurerm_automation_account" "vm_snoozing_automation" {
  name                = "aa-vm-snoozing-automation"
  location            = azurerm_resource_group.vm_snoozing_automation.location
  resource_group_name = azurerm_resource_group.vm_snoozing_automation.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }
}

# Role Assignment - Virtual Machine Contributor for Automation Account
resource "azurerm_role_assignment" "vm_snoozing_automation" {
  scope                = data.azurerm_subscription.current_vm_snoozing_automation.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.vm_snoozing_automation.identity[0].principal_id
}

# PowerShell Runbook for VM Snoozing
resource "azurerm_automation_runbook" "vm_snoozing_automation" {
  name                    = "rb-vm-snoozing-automation"
  location                = azurerm_resource_group.vm_snoozing_automation.location
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"

  content = <<-EOT
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Start", "Stop")]
        [string]$Action,

        [Parameter(Mandatory=$false)]
        [string]$ResourceGroupName = "",

        [Parameter(Mandatory=$false)]
        [string]$VMNames = "",

        [Parameter(Mandatory=$false)]
        [string]$TagName = "AutoSnooze",

        [Parameter(Mandatory=$false)]
        [string]$TagValue = "true"
    )

    # Connect using system-assigned managed identity
    try {
        Connect-AzAccount -Identity
        Write-Output "Successfully connected using managed identity"
    }
    catch {
        Write-Error "Failed to connect using managed identity: $_"
        throw $_
    }

    # Get VMs based on parameters
    $vms = @()

    if (-not [string]::IsNullOrEmpty($VMNames)) {
        # Get specific VMs by name
        $vmNameList = $VMNames -split ","
        foreach ($vmName in $vmNameList) {
            $vmName = $vmName.Trim()
            if (-not [string]::IsNullOrEmpty($ResourceGroupName)) {
                $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -ErrorAction SilentlyContinue
            } else {
                $vm = Get-AzVM | Where-Object { $_.Name -eq $vmName }
            }
            if ($vm) {
                $vms += $vm
            } else {
                Write-Warning "VM '$vmName' not found"
            }
        }
    } elseif (-not [string]::IsNullOrEmpty($ResourceGroupName)) {
        # Get all VMs in resource group with matching tag
        $vms = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object { $_.Tags[$TagName] -eq $TagValue }
    } else {
        # Get all VMs in subscription with matching tag
        $vms = Get-AzVM | Where-Object { $_.Tags[$TagName] -eq $TagValue }
    }

    Write-Output "Found $($vms.Count) VM(s) to process"

    foreach ($vm in $vms) {
        $vmName = $vm.Name
        $vmResourceGroup = $vm.ResourceGroupName

        # Get current power state
        $vmStatus = Get-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName -Status
        $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code

        Write-Output "VM: $vmName, Current State: $powerState"

        if ($Action -eq "Stop") {
            if ($powerState -eq "PowerState/running") {
                Write-Output "Stopping VM: $vmName"
                Stop-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName -Force
                Write-Output "Successfully stopped VM: $vmName"
            } else {
                Write-Output "VM $vmName is not running (state: $powerState), skipping stop"
            }
        } elseif ($Action -eq "Start") {
            if ($powerState -ne "PowerState/running") {
                Write-Output "Starting VM: $vmName"
                Start-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName
                Write-Output "Successfully started VM: $vmName"
            } else {
                Write-Output "VM $vmName is already running, skipping start"
            }
        }
    }

    Write-Output "VM Snoozing automation completed. Action: $Action, VMs processed: $($vms.Count)"
  EOT
}

# Schedule for stopping VMs - Weekdays at 6 PM (W. Europe time)
resource "azurerm_automation_schedule" "stop_vm_snoozing_automation" {
  name                    = "schedule-stop-vm-snoozing-automation"
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  frequency               = "Week"
  interval                = 1
  timezone                = "Europe/Amsterdam"
  start_time              = formatdate("YYYY-MM-DD'T'18:00:00Z", timeadd(timestamp(), "24h"))
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Schedule for starting VMs - Weekdays at 8 AM (W. Europe time)
resource "azurerm_automation_schedule" "start_vm_snoozing_automation" {
  name                    = "schedule-start-vm-snoozing-automation"
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  frequency               = "Week"
  interval                = 1
  timezone                = "Europe/Amsterdam"
  start_time              = formatdate("YYYY-MM-DD'T'08:00:00Z", timeadd(timestamp(), "24h"))
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Job Schedule Link for Stop action
resource "azurerm_automation_job_schedule" "stop_vm_snoozing_automation" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.stop_vm_snoozing_automation.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing_automation.name

  parameters = {
    action = "Stop"
  }
}

# Job Schedule Link for Start action
resource "azurerm_automation_job_schedule" "start_vm_snoozing_automation" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.start_vm_snoozing_automation.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing_automation.name

  parameters = {
    action = "Start"
  }
}
