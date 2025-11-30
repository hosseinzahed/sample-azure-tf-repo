output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "vm_id" {
  description = "ID of the virtual machine"
  value       = azurerm_linux_virtual_machine.main.id
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.main.name
}

output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.main.private_ip_address
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_fqdn" {
  description = "Fully qualified domain name of the VM"
  value       = azurerm_public_ip.main.fqdn
}

# =============================================================================
# VM Snoozing Automation Outputs
# =============================================================================

output "automation_account_id_vm_snoozing_automation" {
  description = "ID of the automation account for VM snoozing automation"
  value       = azurerm_automation_account.vm_snoozing_automation.id
}

output "managed_identity_principal_id_vm_snoozing_automation" {
  description = "Principal ID of the managed identity for VM snoozing automation"
  value       = try(azurerm_automation_account.vm_snoozing_automation.identity[0].principal_id, null)
}

output "resource_group_name_vm_snoozing_automation" {
  description = "Name of the resource group for VM snoozing automation"
  value       = azurerm_resource_group.vm_snoozing_automation.name
}
