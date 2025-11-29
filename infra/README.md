# Azure Infrastructure with Terraform

This directory contains Terraform configurations to provision Azure resources.

## Resources Created

- **Resource Group**: Container for all Azure resources
- **Virtual Network**: Network infrastructure for the VM
- **Subnet**: Network segment within the VNet
- **Network Security Group**: Firewall rules (SSH access enabled)
- **Public IP**: Public IP address for VM access
- **Network Interface**: VM network connection
- **Linux Virtual Machine**: Ubuntu 22.04 LTS VM

## Prerequisites

1. **Terraform**: Install Terraform >= 1.0
   ```bash
   # Verify installation
   terraform version
   ```

2. **Azure CLI** (optional, for local development):
   ```bash
   az login
   ```

3. **SSH Key Pair**: Generate if you don't have one
   ```bash
   ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
   ```

## Configuration

### For Local Development

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values

3. Authenticate with Azure:
   ```bash
   az login
   ```

### For CI/CD (GitHub Actions)

Set these as **GitHub Repository Secrets**:

#### Azure Authentication (Required)
- `ARM_CLIENT_ID`: Azure Service Principal App ID
- `ARM_CLIENT_SECRET`: Azure Service Principal Password
- `ARM_SUBSCRIPTION_ID`: Azure Subscription ID
- `ARM_TENANT_ID`: Azure AD Tenant ID

#### Terraform Variables (Required)
- `TF_VAR_resource_group_name`: Name for the resource group
- `TF_VAR_vm_name`: Name for the virtual machine
- `TF_VAR_ssh_public_key`: SSH public key for VM access

#### Optional Variables
- `TF_VAR_location`: Azure region (default: eastus)
- `TF_VAR_vm_size`: VM size (default: Standard_B2s)
- `TF_VAR_admin_username`: Admin username (default: azureuser)
- `TF_VAR_tags`: JSON object with tags (e.g., `{"Environment":"Production"}`)

### Creating Azure Service Principal

```bash
# Create service principal
az ad sp create-for-rbac --name "terraform-sp" --role Contributor --scopes /subscriptions/<SUBSCRIPTION_ID>

# Output will include:
# appId (ARM_CLIENT_ID)
# password (ARM_CLIENT_SECRET)
# tenant (ARM_TENANT_ID)
```

## Usage

### Initialize Terraform

```bash
cd infra
terraform init
```

### Plan Infrastructure Changes

```bash
terraform plan
```

### Apply Infrastructure

```bash
terraform apply
```

### Destroy Infrastructure

```bash
terraform destroy
```

## GitHub Actions Example

```yaml
name: 'Terraform Deploy'

on:
  push:
    branches:
      - main

jobs:
  terraform:
    runs-on: ubuntu-latest
    
    env:
      ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
      ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
      ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
      ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
      TF_VAR_resource_group_name: ${{ secrets.TF_VAR_resource_group_name }}
      TF_VAR_vm_name: ${{ secrets.TF_VAR_vm_name }}
      TF_VAR_ssh_public_key: ${{ secrets.TF_VAR_ssh_public_key }}
      TF_VAR_location: "eastus"
      TF_VAR_tags: '{"Environment":"Production","ManagedBy":"Terraform"}'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: 1.6.0
    
    - name: Terraform Init
      working-directory: ./infra
      run: terraform init
    
    - name: Terraform Plan
      working-directory: ./infra
      run: terraform plan
    
    - name: Terraform Apply
      working-directory: ./infra
      run: terraform apply -auto-approve
```

## Outputs

After successful deployment, Terraform will output:

- `resource_group_name`: Name of the resource group
- `vm_name`: Name of the virtual machine
- `vm_public_ip`: Public IP address for SSH access
- `vm_private_ip`: Private IP address

## Connecting to the VM

```bash
ssh azureuser@<vm_public_ip>
```

## Security Best Practices

1. **Never commit** `terraform.tfvars` or any file with sensitive data
2. **Always use** repository secrets for CI/CD credentials
3. **Rotate** Azure Service Principal credentials regularly
4. **Restrict** Network Security Group rules to specific IPs in production
5. **Enable** Azure Key Vault for secret management in production

## Customization

- Modify `main.tf` to add/remove Azure resources
- Update `variables.tf` to add new configurable parameters
- Adjust NSG rules in `main.tf` for different port access
- Change VM image in `source_image_reference` block

## Troubleshooting

### Authentication Errors
- Verify Azure credentials are set correctly
- Check service principal has Contributor role

### Resource Naming Conflicts
- Ensure resource names are unique in your subscription
- Update `vm_name` and `resource_group_name` variables

### State File Issues
- Consider using remote state (Azure Storage, Terraform Cloud)
- Never commit `.tfstate` files to version control
