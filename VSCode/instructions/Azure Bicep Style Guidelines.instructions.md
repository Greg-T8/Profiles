---
applyTo: "**/*.bicep"
description: "This file contains the Azure Bicep coding standards and guidelines for Copilot."
---

# Generating Azure Bicep Code with Proper Style

Refactor the Bicep configuration so that it adheres to the following style guidelines:

## Formatting Bicep for Revision

When providing Bicep configuration, follow these guidelines to ensure proper style and readability:

### General Formatting Guidelines

1. **Use 2-space indentation** for nested blocks
2. **One resource per declaration** with clear separation
3. **Group related resources together** logically
4. **Use descriptive symbolic names** - camelCase convention
5. **Include comments and descriptions** for complex logic
6. **Order elements logically** - metadata, parameters, variables, resources, outputs

### File Structure

Organize Bicep projects with standard file structure:

```
bicep/
├── main.bicep            # Primary deployment template
├── main.bicepparam       # Bicep parameter file (preferred)
├── parameters.json       # ARM parameter file (if needed)
├── parameters.dev.json   # Environment-specific parameters
├── bicepconfig.json      # Linter and analyzer configuration
└── modules/
  └── module-name/
    └── module.bicep
```

### Formatting Examples

#### Example 1: Resource Definition

**Before:**
```bicep
resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
name:'my-vnet'
location:'eastus'
properties:{addressSpace:{addressPrefixes:['10.0.0.0/16']}}
tags:{environment:'production',owner:'platform-team'}
}
```

**After:**
```bicep
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'my-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
  tags: {
    environment: 'production'
    owner: 'platform-team'
  }
}
```

#### Example 2: Parameter Declarations

**Before:**
```bicep
param location string='eastus'
param vmSize string
```

**After:**
```bicep
@description('Azure region for resources')
param location string = 'eastus'

@description('Size of the virtual machine')
@allowed([
  'Standard_B2s'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
])
param vmSize string
```

#### Example 3: Module Usage

**Before:**
```bicep
module network './modules/network.bicep'={
name:'network-deployment'
params:{vnetName:'my-vnet',addressSpace:['10.0.0.0/16']}}
```

**After:**
```bicep
module network './modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    vnetName: 'my-vnet'
    location: location
    addressSpace: [
      '10.0.0.0/16'
    ]
    tags: commonTags
  }
}
```

#### Example 4: Variables and Outputs

**Before:**
```bicep
var tags={env:'prod',project:'myapp'}
output vnetId string=vnet.id
```

**After:**
```bicep
// Common tags for all resources
var commonTags = {
  environment: 'production'
  project: 'myapp'
  managedBy: 'bicep'
}

@description('Resource ID of the virtual network')
output vnetId string = vnet.id

@description('Name of the virtual network')
output vnetName string = vnet.name
```

#### Example 5: Conditional Resources

**Before:**
```bicep
resource pip 'Microsoft.Network/publicIPAddresses@2021-02-01'=if(createPublicIp){name:'my-pip',location:location,properties:{publicIPAllocationMethod:'Static'}}
```

**After:**
```bicep
resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = if (createPublicIp) {
  name: '${prefix}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  tags: commonTags
}
```

### Naming Conventions

1. **Symbolic Names**: Use camelCase
   - Good: `resourceGroup`, `virtualNetwork`, `storageAccount`
   - Bad: `resource_group`, `VirtualNetwork`, `storage-account`

2. **Resource Names**: Use descriptive names with prefixes/suffixes
   - Good: `'${prefix}-vnet-${environment}'`, `'st${uniqueString(resourceGroup().id)}'`
   - Bad: `'vnet1'`, `'storage'`

3. **Parameters**: Use camelCase with descriptive names
   - Good: `param resourceGroupName string`, `param vmInstanceCount int`
   - Bad: `param rgName string`, `param count int`

4. **Variables**: Use camelCase
   - Good: `var subnetAddressPrefix = '10.0.1.0/24'`
   - Bad: `var subnet_address_prefix = '10.0.1.0/24'`

### Resource API Versions

Always use recent, stable API versions (avoid preview versions in production):

```bicep
// Good - recent stable version
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  // ...
}

// Avoid - old version
resource vnet 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  // ...
}

// Use with caution - preview version (only if needed for specific features)
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01-preview' = {
  // ...
}
```

### Best Practices

#### 1. Use Decorators Extensively

```bicep
@description('Name of the virtual machine')
@minLength(1)
@maxLength(64)
param vmName string

@description('Admin username for the VM')
@secure()
param adminUsername string

@description('Admin password for the VM')
@secure()
@minLength(12)
param adminPassword string

@description('Tags to apply to all resources')
@metadata({
  example: {
    environment: 'dev'
    costCenter: 'IT'
  }
})
param tags object = {}
```

#### 2. Leverage Variables for DRY Principle

```bicep
// Common resource name prefix
var prefix = '${projectName}-${environment}'

// Resource names
var resourceNames = {
  virtualNetwork: '${prefix}-vnet'
  subnet: '${prefix}-subnet'
  nsg: '${prefix}-nsg'
  storageAccount: 'st${uniqueString(resourceGroup().id)}'
}

// Use in resources
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: resourceNames.virtualNetwork
  // ...
}
```

#### 3. Use Existing Resources

```bicep
// Reference existing resource in another resource group
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroupName)
}

// Use the existing resource
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: existingVnet
  name: 'subnet1'
  properties: {
    addressPrefix: '10.0.1.0/24'
  }
}
```

#### 4. Modularize Complex Deployments

```bicep
// main.bicep
targetScope = 'subscription'

@description('Location for all resources')
param location string = 'eastus'

// Deploy resource group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${projectName}-${environment}'
  location: location
}

// Deploy network module
module network './modules/network.bicep' = {
  scope: rg
  name: 'network-deployment'
  params: {
    location: location
    vnetName: 'vnet-${projectName}'
  }
}

// Deploy compute module
module compute './modules/compute.bicep' = {
  scope: rg
  name: 'compute-deployment'
  params: {
    location: location
    subnetId: network.outputs.subnetId
  }
}
```

#### 5. Use Loops Effectively

```bicep
@description('List of subnet configurations')
param subnets array = [
  {
    name: 'subnet1'
    addressPrefix: '10.0.1.0/24'
  }
  {
    name: 'subnet2'
    addressPrefix: '10.0.2.0/24'
  }
]

// Create multiple subnets using a loop
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = [for subnet in subnets: {
  parent: vnet
  name: subnet.name
  properties: {
    addressPrefix: subnet.addressPrefix
  }
}]
```

#### 6. Type Definitions for Complex Parameters

```bicep
@description('Configuration for virtual machine')
type vmConfig = {
  @description('Name of the VM')
  name: string

  @description('Size of the VM')
  size: string

  @description('Operating system type')
  osType: 'Windows' | 'Linux'

  @description('Additional data disks')
  dataDisks: {
    name: string
    sizeGB: int
  }[]?
}

param vmConfiguration vmConfig
```

### Working with Outputs

```bicep
@description('Resource ID of the virtual network')
output vnetId string = vnet.id

@description('Name of the virtual network')
output vnetName string = vnet.name

@description('Subnet IDs')
output subnetIds array = [for (subnet, i) in subnets: {
  name: subnet.name
  id: subnet[i].id
}]

@description('Connection string (marked as secure)')
@secure()
output connectionString string = 'Server=${sqlServer.properties.fullyQualifiedDomainName};...'
```

### Scope Management

```bicep
// Subscription-level deployment
targetScope = 'subscription'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'my-rg'
  location: location
}

// Management group-level deployment
targetScope = 'managementGroup'

resource policy 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: 'my-policy'
  properties: {
    // ...
  }
}

// Tenant-level deployment
targetScope = 'tenant'

resource mgmt 'Microsoft.Management/managementGroups@2021-04-01' = {
  name: 'my-mgmt-group'
  properties: {
    // ...
  }
}
```

### Comments and Documentation

```bicep
/*
  This module deploys a virtual network with the following components:
  - Virtual network with configurable address space
  - Multiple subnets based on input parameters
  - Network security groups for each subnet
  - DDoS protection (optional)
*/

@description('Address space for the virtual network')
param addressSpace array = [
  '10.0.0.0/16'
]

// Calculate derived values
var subnetCount = length(subnets)
var enableDdos = environment == 'production'  // Enable DDoS only in production

// Deploy virtual network with DDoS protection if enabled
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressSpace
    }
    // Enable DDoS protection for production environments
    enableDdosProtection: enableDdos
    ddosProtectionPlan: enableDdos ? {
      id: ddosProtectionPlan.id
    } : null
  }
}
```

### Error Handling and Validation

```bicep
@description('Environment name')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string

@description('VM size')
@allowed([
  'Standard_B2s'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
])
param vmSize string

@description('Number of VMs to deploy')
@minValue(1)
@maxValue(10)
param vmCount int

@description('Storage account name')
@minLength(3)
@maxLength(24)
param storageAccountName string
```

### Using Bicep Functions

```bicep
// String manipulation
var lowerCaseName = toLower(resourceName)
var upperCaseName = toUpper(resourceName)
var trimmedName = trim(resourceName)

// Unique string generation
var uniqueName = 'st${uniqueString(resourceGroup().id)}'

// Working with arrays
var firstSubnet = first(subnets)
var lastSubnet = last(subnets)
var subnetCount = length(subnets)
var concatenatedSubnets = concat(subnets1, subnets2)

// Working with objects
var mergedTags = union(defaultTags, customTags)

// Conditional logic
var vmSize = environment == 'prod' ? 'Standard_D4s_v3' : 'Standard_B2s'

// Resource references
var storageAccountId = resourceId('Microsoft.Storage/storageAccounts', storageAccountName)
var subscriptionId = subscription().subscriptionId
var tenantId = tenant().tenantId
var rgLocation = resourceGroup().location
```

## Security Considerations

1. **Always use @secure() decorator** for sensitive parameters
2. **Never output sensitive data** without @secure() decorator
3. **Use managed identities** instead of storing credentials
4. **Enable encryption** by default for storage and databases
5. **Use private endpoints** for Azure services
6. **Implement network security groups** with least-privilege rules
7. **Use Azure Key Vault** for secrets management

```bicep
@description('Admin password for resources')
@secure()
param adminPassword string

@description('SQL connection string (secure output)')
@secure()
output sqlConnectionString string = '...'

// Use Key Vault reference in parameter file (parameters.json)
// {
//   "adminPassword": {
//     "reference": {
//       "keyVault": {
//         "id": "/subscriptions/.../providers/Microsoft.KeyVault/vaults/myVault"
//       },
//       "secretName": "adminPassword"
//     }
//   }
// }
// Prefer .bicepparam for Bicep-native parameter files when possible.
```

## Testing and Validation

1. **Use bicep build** to validate syntax
2. **Use what-if deployments** to preview changes
3. **Test with different parameter files** for each environment
4. **Use bicepconfig.json** to enforce linting rules

```powershell
# Validate Bicep syntax
bicep build main.bicep

# Preview changes without deploying
az deployment group what-if `
  --resource-group myResourceGroup `
  --template-file main.bicep `
  --parameters main.bicepparam

# Deploy Bicep template
az deployment group create `
  --resource-group myResourceGroup `
  --template-file main.bicep `
  --parameters parameters.json
```
