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

# ============================================
# VM Snoozing Automation Infrastructure
# ============================================

# Resource Group for VM Snoozing Automation
resource "azurerm_resource_group" "vm_snoozing_automation" {
  name     = "${var.vm_name}-vm-snoozing-automation"
  location = var.location
  tags     = var.tags
}

# Automation Account for VM Snoozing
resource "azurerm_automation_account" "vm_snoozing_automation" {
  name                = "${var.vm_name}-vm-snoozing-automation"
  location            = azurerm_resource_group.vm_snoozing_automation.location
  resource_group_name = azurerm_resource_group.vm_snoozing_automation.name
  sku_name            = "Basic"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Role Assignment - Grant Automation Account Contributor access to the VM Resource Group
resource "azurerm_role_assignment" "vm_snoozing_automation" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.vm_snoozing_automation.identity[0].principal_id
}

# Runbook for Starting VM
resource "azurerm_automation_runbook" "start_vm" {
  name                    = "Start-VM-vm-snoozing-automation"
  location                = azurerm_resource_group.vm_snoozing_automation.location
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  log_verbose             = false
  log_progress            = true
  runbook_type            = "PowerShell"
  tags                    = var.tags

  content = <<-EOT
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$VMName
    )

    try {
        # Connect using Managed Identity
        Connect-AzAccount -Identity

        # Start the VM
        Write-Output "Starting VM: $VMName in Resource Group: $ResourceGroupName"
        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -NoWait
        Write-Output "VM start command issued successfully"
    }
    catch {
        Write-Error "Failed to start VM: $_"
        throw
    }
  EOT
}

# Runbook for Stopping VM
resource "azurerm_automation_runbook" "stop_vm" {
  name                    = "Stop-VM-vm-snoozing-automation"
  location                = azurerm_resource_group.vm_snoozing_automation.location
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  log_verbose             = false
  log_progress            = true
  runbook_type            = "PowerShell"
  tags                    = var.tags

  content = <<-EOT
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$VMName
    )

    try {
        # Connect using Managed Identity
        Connect-AzAccount -Identity

        # Stop the VM (deallocate to avoid charges)
        Write-Output "Stopping VM: $VMName in Resource Group: $ResourceGroupName"
        Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force -NoWait
        Write-Output "VM stop command issued successfully"
    }
    catch {
        Write-Error "Failed to stop VM: $_"
        throw
    }
  EOT
}

# Schedule for Starting VM (Wake) - 8 AM UTC on weekdays
# Note: start_time sets when the schedule becomes active. The schedule runs at
# 8 AM UTC based on the hour component. We use a future date to ensure the
# schedule is created in the future as required by Azure.
resource "azurerm_automation_schedule" "start_vm" {
  name                    = "Start-VM-Schedule-vm-snoozing-automation"
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  frequency               = "Week"
  interval                = 1
  timezone                = "UTC"
  start_time              = formatdate("YYYY-MM-DD'T'08:00:00Z", timeadd(timestamp(), "24h"))
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  # Ignore start_time changes to prevent Terraform from updating the schedule
  # on every apply due to the timestamp() function generating a new value
  lifecycle {
    ignore_changes = [start_time]
  }
}

# Schedule for Stopping VM (Snooze) - 6 PM UTC on weekdays
# Note: start_time sets when the schedule becomes active. The schedule runs at
# 6 PM (18:00) UTC based on the hour component. We use a future date to ensure
# the schedule is created in the future as required by Azure.
resource "azurerm_automation_schedule" "stop_vm" {
  name                    = "Stop-VM-Schedule-vm-snoozing-automation"
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  frequency               = "Week"
  interval                = 1
  timezone                = "UTC"
  start_time              = formatdate("YYYY-MM-DD'T'18:00:00Z", timeadd(timestamp(), "24h"))
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  # Ignore start_time changes to prevent Terraform from updating the schedule
  # on every apply due to the timestamp() function generating a new value
  lifecycle {
    ignore_changes = [start_time]
  }
}

# Link Start VM Runbook to Schedule
resource "azurerm_automation_job_schedule" "start_vm" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.start_vm.name
  runbook_name            = azurerm_automation_runbook.start_vm.name

  parameters = {
    resourcegroupname = azurerm_resource_group.main.name
    vmname            = azurerm_linux_virtual_machine.main.name
  }
}

# Link Stop VM Runbook to Schedule
resource "azurerm_automation_job_schedule" "stop_vm" {
  resource_group_name     = azurerm_resource_group.vm_snoozing_automation.name
  automation_account_name = azurerm_automation_account.vm_snoozing_automation.name
  schedule_name           = azurerm_automation_schedule.stop_vm.name
  runbook_name            = azurerm_automation_runbook.stop_vm.name

  parameters = {
    resourcegroupname = azurerm_resource_group.main.name
    vmname            = azurerm_linux_virtual_machine.main.name
  }
}
