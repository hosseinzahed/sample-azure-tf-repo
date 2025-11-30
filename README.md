# Azure Terraform Sample Repository

This repository contains Terraform Infrastructure as Code (IaC) to deploy a complete Linux virtual machine environment on Microsoft Azure. It's designed for both local development and CI/CD automation using GitHub Actions.

## 📦 What's Included

### Infrastructure Components

This repository provisions the following Azure resources:

- **Azure Resource Group** - Container for all resources
- **Virtual Network (VNet)** - Network infrastructure with 10.0.0.0/16 address space
- **Subnet** - Network segment (10.0.1.0/24) within the VNet
- **Network Security Group (NSG)** - Firewall with SSH (port 22) access enabled
- **Public IP Address** - Dynamic public IP for external access
- **Network Interface (NIC)** - VM network connection with public and private IPs
- **Linux Virtual Machine** - Ubuntu 22.04 LTS with SSH authentication

### Repository Structure

```
├── README.md                      # This file
└── infra/                         # Terraform configuration directory
    ├── main.tf                    # Main resource definitions
    ├── variables.tf               # Input variable declarations
    ├── outputs.tf                 # Output value definitions
    ├── provider.tf                # Azure provider configuration
    ├── terraform.tfvars.example   # Example variables file
    └── README.md                  # Detailed infrastructure documentation
```

## 🚀 Quick Start

### Local Development

1. **Clone the repository**
   ```powershell
   git clone https://github.com/hosseinzahed/sample-azure-tf-repo.git
   cd sample-azure-tf-repo/infra
   ```

2. **Configure variables**
   ```powershell
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Authenticate with Azure**
   ```powershell
   az login
   ```

4. **Deploy infrastructure**
   ```powershell
   terraform init
   terraform plan
   terraform apply
   ```

### CI/CD with GitHub Actions

Set up the following secrets in your GitHub repository:
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` (Azure credentials)
- `TF_VAR_resource_group_name`, `TF_VAR_vm_name`, `TF_VAR_ssh_public_key` (Terraform variables)

See [infra/README.md](infra/README.md) for complete CI/CD setup instructions.

## 📋 Prerequisites

- **Terraform** >= 1.0
- **Azure CLI** (for local development)
- **Azure subscription** with Contributor access
- **SSH key pair** for VM authentication

## 🔧 Configuration

### Required Variables

- `resource_group_name` - Name for the Azure resource group
- `vm_name` - Name for the virtual machine
- `ssh_public_key` - SSH public key for authentication

### Optional Variables

- `location` - Azure region (default: `swedencentral`)
- `vm_size` - VM size (default: `Standard_B2s`)
- `admin_username` - Admin username (default: `azureuser`)
- `tags` - Resource tags (default: `{Environment = "dev"}`)

## 📖 Documentation

For detailed information about:
- Infrastructure components and architecture
- Azure Service Principal setup
- GitHub Actions CI/CD configuration
- Security best practices
- Troubleshooting tips

Please refer to the [Infrastructure README](infra/README.md).

## 🔒 Security Notes

- Never commit sensitive data or credentials to the repository
- Use GitHub Secrets for CI/CD authentication
- SSH public key is marked as sensitive in Terraform
- NSG allows SSH from any source IP (restrict in production)

## 📄 License

This is a sample repository for demonstration purposes.

## 🤝 Contributing

Feel free to fork this repository and customize it for your needs.
