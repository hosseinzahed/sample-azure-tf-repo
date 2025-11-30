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

# =============================================================================
# VM Snoozing Automation Resources
# =============================================================================

# Data sources for Azure client config and subscription
data "azurerm_client_config" "vm_snoozing_automation" {}

data "azurerm_subscription" "vm_snoozing_automation" {}

# Resource Group for VM Snoozing Automation
resource "azurerm_resource_group" "vm_snoozing_automation" {
  name     = "rg-vm-snoozing-automation"
  location = "Sweden Central"
}

# Automation Account for VM Snoozing Automation
resource "azurerm_automation_account" "vm_snoozing_automation" {
  name                = "aa-vm-snoozing-automation"
  location            = azurerm_resource_group.vm_snoozing_automation.location
  resource_group_name = azurerm_resource_group.vm_snoozing_automation.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }
}

# Role Assignment: Virtual Machine Contributor at subscription scope
resource "azurerm_role_assignment" "vm_snoozing_automation" {
  scope                = data.azurerm_subscription.vm_snoozing_automation.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.vm_snoozing_automation.identity[0].principal_id
}

# PowerShell Runbook for VM Snoozing Automation
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
        [string]$Action,

        [Parameter(Mandatory=$false)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$false)]
        [string]$VMName
    )

    # Connect to Azure using the managed identity
    try {
        Connect-AzAccount -Identity
        Write-Output "Successfully connected to Azure using managed identity"
    }
    catch {
        Write-Error "Failed to connect to Azure: $_"
        throw $_
    }

    # Function to log messages with timestamp
    function Write-Log {
        param([string]$Message)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Output "[$timestamp] $Message"
    }

    # Get VMs to process
    if ($VMName -and $ResourceGroupName) {
        Write-Log "Processing single VM: $VMName in resource group: $ResourceGroupName"
        $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
    }
    elseif ($ResourceGroupName) {
        Write-Log "Processing all VMs in resource group: $ResourceGroupName"
        $vms = Get-AzVM -ResourceGroupName $ResourceGroupName
    }
    else {
        Write-Log "Processing all VMs in subscription"
        $vms = Get-AzVM
    }

    Write-Log "Found $($vms.Count) VM(s) to process"

    foreach ($vm in $vms) {
        $vmName = $vm.Name
        $rgName = $vm.ResourceGroupName

        Write-Log "Processing VM: $vmName in resource group: $rgName"

        try {
            switch ($Action.ToLower()) {
                "start" {
                    Write-Log "Starting VM: $vmName"
                    Start-AzVM -ResourceGroupName $rgName -Name $vmName -NoWait
                    Write-Log "Start command sent for VM: $vmName"
                }
                "stop" {
                    Write-Log "Stopping VM: $vmName"
                    Stop-AzVM -ResourceGroupName $rgName -Name $vmName -Force -NoWait
                    Write-Log "Stop command sent for VM: $vmName"
                }
                default {
                    Write-Error "Invalid action: $Action. Use 'start' or 'stop'."
                }
            }
        }
        catch {
            Write-Error "Failed to $Action VM $vmName : $_"
        }
    }

    Write-Log "VM snoozing automation completed"
  EOT
}

# Automation Schedule for stopping VMs at 6 PM on weekdays (W. Europe Standard Time)
resource "azurerm_automation_schedule" "vm_stop_schedule" {
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

# Automation Schedule for starting VMs at 8 AM on weekdays (W. Europe Standard Time)
resource "azurerm_automation_schedule" "vm_start_schedule" {
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

# Job Schedule for stopping VMs at 6 PM
resource "azurerm_automation_job_schedule" "vm_stop_job_schedule" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.vm_stop_schedule.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing_automation.name

  parameters = {
    action = "stop"
  }
}

# Job Schedule for starting VMs at 8 AM
resource "azurerm_automation_job_schedule" "vm_start_job_schedule" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.vm_start_schedule.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing_automation.name

  parameters = {
    action = "start"
  }
}
