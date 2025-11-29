# GitHub Actions Workflow for Terraform Azure Deployment

This workflow automates the provisioning of Azure infrastructure using Terraform.

## Triggers

The workflow runs automatically on:
- **Push to main**: Automatically applies Terraform changes
- **Pull Requests**: Runs plan and posts results as a comment
- **Manual Dispatch**: Allows you to choose plan, apply, or destroy

## Required Setup

The workflow uses the **`dev` environment** for secrets and variables. Configure them in: **Settings → Environments → dev**

### Required Secrets (Environment: dev)

| Secret Name | Description | How to Get |
|------------|-------------|------------|
| `ARM_CLIENT_ID` | Azure Service Principal App ID | From `az ad sp create-for-rbac` output (appId) |
| `ARM_CLIENT_SECRET` | Azure Service Principal Password | From `az ad sp create-for-rbac` output (password) |
| `ARM_SUBSCRIPTION_ID` | Azure Subscription ID | Run `az account show --query id -o tsv` |
| `ARM_TENANT_ID` | Azure AD Tenant ID | From `az ad sp create-for-rbac` output (tenant) |
| `TF_VAR_RESOURCE_GROUP_NAME` | Name for the resource group | `my-terraform-rg` |
| `TF_VAR_VM_NAME` | Name for the virtual machine | `my-terraform-vm` |
| `TF_VAR_SSH_PUBLIC_KEY` | SSH public key for VM access | `ssh-rsa AAAAB3...` |

### Optional Variables (Environment: dev)

These override the defaults in `variables.tf`. Only set them if you need different values:

| Variable Name | Description | Default (from variables.tf) |
|--------------|-------------|---------|
| `TF_VAR_LOCATION` | Azure region | `swedencentral` |
| `TF_VAR_VM_SIZE` | VM size | `Standard_B2s` |
| `TF_VAR_ADMIN_USERNAME` | Admin username | `azureuser` |
| `TF_VAR_TAGS` | Custom tags (JSON format) | `{"Environment":"dev"}` |

## Setting Up Azure Service Principal

```bash
# Login to Azure
az login

# Get your subscription ID
az account show --query id -o tsv

# Create service principal with Contributor role
az ad sp create-for-rbac \
  --name "github-terraform-sp" \
  --role Contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>

# Output will include:
# {
#   "appId": "<ARM_CLIENT_ID>",
#   "password": "<ARM_CLIENT_SECRET>",
#   "tenant": "<ARM_TENANT_ID>"
# }

# To grant Contributor role to an existing service principal:
az role assignment create \
  --assignee <SERVICE_PRINCIPAL_CLIENT_ID> \
  --role Contributor \
  --scope /subscriptions/<SUBSCRIPTION_ID>
```

## Generate SSH Key Pair

```bash
# Generate new SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_terraform_key -C "terraform@azure"

# Get the public key to add as TF_VAR_SSH_PUBLIC_KEY secret
cat ~/.ssh/azure_terraform_key.pub
```

## Workflow Features

### Automatic on Push to Main
- ✅ Runs format check
- ✅ Initializes Terraform
- ✅ Validates configuration
- ✅ Plans changes
- ✅ **Automatically applies** infrastructure changes
- ✅ Outputs deployment results

### On Pull Requests
- ✅ Runs format check
- ✅ Initializes Terraform
- ✅ Validates configuration
- ✅ Plans changes
- ✅ **Posts plan as PR comment**
- ❌ Does NOT apply changes

### Manual Workflow Dispatch
Navigate to: **Actions → Terraform Azure Deployment → Run workflow**

Choose from:
- **plan**: Preview changes without applying
- **apply**: Apply infrastructure changes
- **destroy**: Tear down all infrastructure

## Workflow Steps Explained

1. **Checkout Repository**: Gets the latest code
2. **Setup Terraform**: Installs Terraform CLI
3. **Terraform Format Check**: Ensures code follows Terraform formatting standards
4. **Set Optional Variables**: Conditionally sets optional variables if defined in environment
5. **Terraform Init**: Initializes Terraform backend and providers
6. **Terraform Validate**: Validates configuration syntax
7. **Terraform Plan**: Creates execution plan showing what will change
8. **Terraform Apply**: Applies the changes (on main branch push or manual trigger)
9. **Terraform Destroy**: Removes all infrastructure (manual trigger only)

## Using Tags

To add custom tags, add this variable in **Variables tab**:

```
Name: TF_VAR_tags
Value: {"Environment":"Production","CostCenter":"Engineering","Owner":"DevOps"}
```

Note: Use proper JSON format for tags.

## Monitoring Workflow

1. Go to **Actions** tab in your repository
2. Click on the latest workflow run
3. View logs for each step
4. Check the **Summary** page for deployment outputs

## Security Best Practices

✅ Never commit secrets to the repository
✅ Use GitHub Secrets for sensitive data
✅ Rotate Azure Service Principal credentials regularly
✅ Review Terraform plans in PRs before merging
✅ Use branch protection rules on main branch
✅ Enable "Require approval for deployments" if needed

## Troubleshooting

### Authentication Errors
- Verify all Azure secrets are set correctly
- Ensure Service Principal has Contributor role
- Check subscription ID is correct

### Plan/Apply Failures
- Review the workflow logs for specific errors
- Ensure resource names are unique
- Check Azure quota limits

### Permission Errors
- Verify Service Principal has necessary permissions
- Check repository secrets are accessible

## Advanced: Using Terraform Cloud/Backend

To use remote state, add backend configuration to `provider.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatestore"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
```

Then add these secrets:
- `ARM_ACCESS_KEY`: Storage account access key

## Example: Complete Setup Checklist

- [ ] Create Azure Service Principal
- [ ] Add `ARM_CLIENT_ID` secret
- [ ] Add `ARM_CLIENT_SECRET` secret
- [ ] Add `ARM_SUBSCRIPTION_ID` secret
- [ ] Add `ARM_TENANT_ID` secret
- [ ] Generate SSH key pair
- [ ] Add `TF_VAR_SSH_PUBLIC_KEY` secret
- [ ] Add `TF_VAR_RESOURCE_GROUP_NAME` secret
- [ ] Add `TF_VAR_VM_NAME` secret
- [ ] (Optional) Add configuration variables
- [ ] Test workflow with manual dispatch (plan)
- [ ] Review and approve
- [ ] Run apply or push to main

## Support

For issues or questions:
- Check workflow logs in Actions tab
- Review Terraform error messages
- Verify all secrets and variables are set correctly
