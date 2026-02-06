---
applyTo: "**/*.tf"
description: "This file contains the Terraform coding standards and guidelines for Copilot."
---

# Generating Terraform Code with Proper Style

Refactor the Terraform configuration so that it adheres to the following style guidelines:

## Formatting Terraform for Revision

When providing Terraform configuration, follow these guidelines to ensure proper style and readability:

### General Formatting Guidelines

1. **Use `terraform fmt` standard formatting** - 2-space indentation
2. **One resource per block** with clear separation
3. **Group related resources together** logically
4. **Use consistent naming conventions** - lowercase with hyphens or underscores
5. **Include comments** for complex logic or non-obvious configurations
6. **Order attributes logically** - required attributes first, then optional

### File Structure

Organize Terraform projects with standard file structure:

```
terraform/
├── main.tf            # Primary resource definitions
├── variables.tf       # Input variable declarations
├── outputs.tf         # Output value declarations
├── versions.tf        # Provider version constraints
├── providers.tf       # Provider configuration
├── backend.tf         # Backend configuration (if used)
├── locals.tf          # Local values (optional)
├── data.tf            # Data sources (optional)
├── terraform.tfvars   # Non-sensitive variable values
├── terraform.lock.hcl # Provider lock file (commit this)
└── modules/
  └── module-name/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

### Formatting Examples

#### Example 1: Resource Definition

**Before:**
```terraform
resource "azurerm_virtual_network" "vnet" {
name="my-vnet"
location="eastus"
resource_group_name="rg-prod"
address_space=["10.0.0.0/16"]
tags={environment="production",owner="platform-team"}
}
```

**After:**
```terraform
resource "azurerm_virtual_network" "vnet" {
  name                = "my-vnet"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "production"
    owner       = "platform-team"
  }
}
```

#### Example 2: Variable Declarations

**Before:**
```terraform
variable "location" {
type=string
default="eastus"
}
variable "vm_size" {
type=string
}
```

**After:**
```terraform
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string

  validation {
    condition     = contains(["Standard_B2s", "Standard_D2s_v3", "Standard_D4s_v3"], var.vm_size)
    error_message = "VM size must be a supported SKU."
  }
}
```

#### Example 3: Module Usage

**Before:**
```terraform
module "network" {
source="./modules/network"
vnet_name="my-vnet"
address_space=["10.0.0.0/16"]
subnets={"subnet1":"10.0.1.0/24","subnet2":"10.0.2.0/24"}
}
```

**After:**
```terraform
module "network" {
  source = "./modules/network"

  vnet_name     = "my-vnet"
  address_space = ["10.0.0.0/16"]

  subnets = {
    subnet1 = "10.0.1.0/24"
    subnet2 = "10.0.2.0/24"
  }

  tags = local.common_tags
}
```

#### Example 4: Data Source and Locals

**Before:**
```terraform
data "azurerm_client_config" "current" {}
locals {
tags={env="prod",project="myapp",managed_by="terraform"}
rg_name="${var.prefix}-rg-${var.environment}"
}
```

**After:**
```terraform
# Get current Azure subscription context
data "azurerm_client_config" "current" {}

# Common local values
locals {
  common_tags = {
    environment = "production"
    project     = "myapp"
    managed_by  = "terraform"
  }

  resource_group_name = "${var.prefix}-rg-${var.environment}"
  location            = var.location
}
```

#### Example 5: Output Declarations

**Before:**
```terraform
output "vnet_id" {
value=azurerm_virtual_network.vnet.id
}
output "subnet_ids" {
value=[for s in azurerm_subnet.subnets : s.id]
}
```

**After:**
```terraform
output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.vnet.id
}

output "subnet_ids" {
  description = "Map of subnet names to their IDs"
  value       = { for k, s in azurerm_subnet.subnets : k => s.id }
}
```

### Naming Conventions

1. **Resources**: Use descriptive names that indicate their purpose
   - Good: `azurerm_resource_group.main`, `azurerm_virtual_network.app_vnet`
   - Bad: `azurerm_resource_group.rg1`, `azurerm_virtual_network.vnet`

2. **Variables**: Use snake_case for variable names
   - Good: `var.resource_group_name`, `var.vm_instance_count`
   - Bad: `var.rgName`, `var.VMInstanceCount`

3. **Files**: Use standard naming
   - `main.tf` - primary resources
   - `variables.tf` - input variables
   - `outputs.tf` - outputs
   - `versions.tf` - provider versions
   - `locals.tf` - local values (optional)
   - `data.tf` - data sources (optional)

### Best Practices

1. **Use Variables for Flexibility**
   - Define inputs in `variables.tf` with descriptions and types
   - Use validation blocks where appropriate
   - Provide sensible defaults when possible

2. **Leverage Locals for DRY Principle**
   - Use locals for computed values used multiple times
   - Keep complex expressions in locals rather than inline

3. **Add Descriptions Everywhere**
   - Every variable should have a description
   - Every output should have a description
   - Complex resources should have comments

4. **Use Count and For-Each Wisely**
   - Prefer `for_each` over `count` for managing multiple resources
   - Use `for_each` when you need to reference specific instances

5. **Manage State Carefully**
  - Use remote state (Azure Storage, Terraform Cloud, etc.)
  - Never commit state files to version control
  - Use state locking to prevent conflicts
  - Commit `terraform.lock.hcl` to ensure consistent providers

6. **Version Constraints**
   ```terraform
   terraform {
     required_version = ">= 1.0"

     required_providers {
       azurerm = {
         source  = "hashicorp/azurerm"
         version = "~> 3.0"
       }
     }
   }
   ```

7. **Use Depends-On Sparingly**
   - Terraform infers most dependencies automatically
   - Only use explicit `depends_on` when absolutely necessary

8. **Tags and Metadata**
  - Use consistent tagging strategy
  - Define common tags in locals
  - Apply tags to all taggable resources

9. **Protect Sensitive Data**
  - Mark secrets with `sensitive = true`
  - Prefer external secret stores over plaintext values

10. **Use Preconditions for Safety**
  - Add `precondition` or `postcondition` blocks for critical assumptions
  - Prefer clear error messages when validation fails

11. **Refactor Safely**
  - Use `moved` blocks for renames to avoid resource replacement

### Tooling and Validation

1. **Format and Validate**
  - `terraform fmt` before reviews
  - `terraform validate` for basic correctness

2. **Plan Before Apply**
  - Use `terraform plan` in CI or pre-merge checks
  - Store and review plan output for production changes

3. **Lint and Security Checks**
  - Use `tflint` for linting
  - Use `tfsec` or equivalent for security scanning

### Terraform-Specific Patterns

#### Dynamic Blocks

```terraform
resource "azurerm_network_security_group" "nsg" {
  name                = "my-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  dynamic "security_rule" {
    for_each = var.security_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }
}
```

#### Conditional Resources

```terraform
resource "azurerm_public_ip" "pip" {
  count = var.create_public_ip ? 1 : 0

  name                = "${var.prefix}-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
}
```

### Error Handling and Validation

1. **Use validation blocks** to catch errors early
2. **Provide clear error messages** in validation blocks
3. **Use lifecycle blocks** for complex resource management
4. **Document preconditions** in comments

### Module Development

1. **Keep modules focused** - single responsibility principle
2. **Version your modules** if stored in Git repos
3. **Provide examples** in a `examples/` directory
4. **Include a README.md** explaining usage
5. **Define clear input/output contracts**

Example module structure:
```terraform
# modules/virtual-network/main.tf
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space

  tags = var.tags
}

# modules/virtual-network/variables.tf
variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# modules/virtual-network/outputs.tf
output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.this.name
}
```

## Security Considerations

1. **Never hardcode secrets** - use Azure Key Vault or environment variables
2. **Use sensitive = true** for outputs containing secrets
3. **Implement least privilege** with Azure RBAC
4. **Enable encryption** for storage accounts and disks
5. **Use private endpoints** where applicable
