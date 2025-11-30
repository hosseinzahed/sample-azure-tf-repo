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

# =============================================
# VM Snoozing Automation Resources
# =============================================

# Data Sources for VM Snoozing Automation
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

# Role Assignment for VM Snoozing Automation
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
  log_verbose             = false
  log_progress            = false
  runbook_type            = "PowerShell"

  content = <<-EOT
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Start", "Stop")]
        [string]$Action
    )

    # Connect using the system-assigned managed identity
    Connect-AzAccount -Identity

    # Get all VMs in the subscription
    $vms = Get-AzVM -Status

    foreach ($vm in $vms) {
        $vmName = $vm.Name
        $resourceGroupName = $vm.ResourceGroupName
        $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code

        if ($Action -eq "Stop") {
            if ($powerState -eq "PowerState/running") {
                Write-Output "Stopping VM: $vmName in Resource Group: $resourceGroupName"
                Stop-AzVM -Name $vmName -ResourceGroupName $resourceGroupName -Force
            } else {
                Write-Output "VM $vmName is not running (current state: $powerState). Skipping."
            }
        } elseif ($Action -eq "Start") {
            if ($powerState -eq "PowerState/deallocated" -or $powerState -eq "PowerState/stopped") {
                Write-Output "Starting VM: $vmName in Resource Group: $resourceGroupName"
                Start-AzVM -Name $vmName -ResourceGroupName $resourceGroupName
            } else {
                Write-Output "VM $vmName is not stopped (current state: $powerState). Skipping."
            }
        }
    }

    Write-Output "VM $Action operation completed."
  EOT
}

# Stop Schedule for VM Snoozing Automation (Weekdays 6 PM W. Europe Standard Time)
resource "azurerm_automation_schedule" "stop_vm_snoozing_automation" {
  name                    = "stop-schedule-vm-snoozing-automation"
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  frequency               = "Week"
  interval                = 1
  timezone                = "Europe/Amsterdam"
  start_time              = timeadd(formatdate("YYYY-MM-DD", timestamp()), "T18:00:00+01:00")
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Start Schedule for VM Snoozing Automation (Weekdays 8 AM W. Europe Standard Time)
resource "azurerm_automation_schedule" "start_vm_snoozing_automation" {
  name                    = "start-schedule-vm-snoozing-automation"
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  frequency               = "Week"
  interval                = 1
  timezone                = "Europe/Amsterdam"
  start_time              = timeadd(formatdate("YYYY-MM-DD", timestamp()), "T08:00:00+01:00")
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Job Schedule Link for Stop VM Snoozing Automation
resource "azurerm_automation_job_schedule" "stop_vm_snoozing_automation" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.stop_vm_snoozing_automation.name

  parameters = {
    action = "Stop"
  }
}

# Job Schedule Link for Start VM Snoozing Automation
resource "azurerm_automation_job_schedule" "start_vm_snoozing_automation" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  runbook_name            = azurerm_automation_runbook.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.start_vm_snoozing_automation.name

  parameters = {
    action = "Start"
  }
}
