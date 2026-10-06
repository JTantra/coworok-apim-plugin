// PSA OEN Cowork gateway: Standard v2 APIM (VNet-integrated outbound), private Key Vault,
// and a VNet-integrated Container App hosting the OEN account-linking page.
param location string = resourceGroup().location
param apimName string
param kvName string
param publisherEmail string
param publisherName string = 'Innovation Hub'
param acrName string
param acrResourceGroup string
param linkImage string = ''
param linkAppName string = 'oen-link'
param entraClientId string = ''
@secure()
param entraClientSecret string = ''
param buildId string = 'dev'

var tenantId = subscription().tenantId
var deployApp = !empty(linkImage) && !empty(entraClientId)

// ---------------- Network ----------------
resource nsgApim 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-apim'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowKeyVaultOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureKeyVault'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-psa-oen'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.60.0.0/16' ] }
    subnets: [
      {
        name: 'snet-apim'
        properties: {
          addressPrefix: '10.60.0.0/24'
          networkSecurityGroup: { id: nsgApim.id }
          delegations: [ { name: 'web', properties: { serviceName: 'Microsoft.Web/serverFarms' } } ]
        }
      }
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: '10.60.2.0/23'
          delegations: [ { name: 'aca', properties: { serviceName: 'Microsoft.App/environments' } } ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.60.4.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ---------------- Key Vault (private) ----------------
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    tenantId: tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
  }
}

resource kvDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource kvDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: kvDns
  name: 'link-vnet-psa-oen'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}

resource kvPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${kvName}'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/snet-pe' }
    privateLinkServiceConnections: [
      { name: 'kv', properties: { privateLinkServiceId: kv.id, groupIds: [ 'vault' ] } }
    ]
  }
}

resource kvPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: kvPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [ { name: 'vault', properties: { privateDnsZoneId: kvDns.id } } ]
  }
}

// ---------------- APIM Standard v2 ----------------
resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: { name: 'StandardV2', capacity: 1 }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: { subnetResourceId: '${vnet.id}/subnets/snet-apim' }
  }
}

var kvSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
var kvSecretsOfficer = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource apimKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, apim.id, 'kv-secrets-user')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUser)
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------- Linking page ----------------
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-psa-oen'
  location: location
  properties: { sku: { name: 'PerGB2018' }, retentionInDays: 30 }
}

resource appId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${linkAppName}'
  location: location
}

resource appKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, appId.id, 'kv-secrets-officer')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsOfficer)
    principalId: appId.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

module acrPull 'acrpull.bicep' = {
  name: 'acrpull-${linkAppName}'
  scope: resourceGroup(acrResourceGroup)
  params: { acrName: acrName, principalId: appId.properties.principalId }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-psa-oen'
  location: location
  properties: {
    vnetConfiguration: { infrastructureSubnetId: '${vnet.id}/subnets/snet-aca', internal: false }
    workloadProfiles: [ { name: 'Consumption', workloadProfileType: 'Consumption' } ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = if (deployApp) {
  name: linkAppName
  location: location
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${appId.id}': {} } }
  dependsOn: [ acrPull, appKv, kvPeDns, kvDnsLink ]
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'auto', allowInsecure: false }
      registries: [ { server: '${acrName}.azurecr.io', identity: appId.id } ]
      secrets: [ { name: 'microsoft-provider-authentication-secret', value: entraClientSecret } ]
    }
    template: {
      containers: [
        {
          name: 'web'
          image: linkImage
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: [
            { name: 'KEY_VAULT_URL', value: kv.properties.vaultUri }
            { name: 'AZURE_CLIENT_ID', value: appId.properties.clientId }
            { name: 'BUILD_ID', value: buildId }
          ]
          probes: [
            { type: 'Liveness', httpGet: { path: '/healthz', port: 8000 }, initialDelaySeconds: 10, periodSeconds: 30 }
          ]
        }
      ]
      scale: { minReplicas: 0, maxReplicas: 2 }
    }
  }
}

resource auth 'Microsoft.App/containerApps/authConfigs@2024-03-01' = if (deployApp) {
  parent: app
  name: 'current'
  properties: {
    platform: { enabled: true }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
      excludedPaths: [ '/healthz' ]
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: entraClientId
          clientSecretSettingName: 'microsoft-provider-authentication-secret'
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
        }
        validation: { allowedAudiences: [ 'api://${entraClientId}' ] }
      }
    }
    login: { tokenStore: { enabled: false } }
  }
}

output apimGateway string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId
output kvUri string = kv.properties.vaultUri
output linkAppFqdn string = deployApp ? app!.properties.configuration.ingress.fqdn : ''
output envDefaultDomain string = env.properties.defaultDomain

// App Insights tracing for APIM (logger + per-API diagnostics with request/response bodies)
module apimAppInsights 'apim-appinsights.bicep' = {
  name: 'apim-appinsights'
  params: { apimName: apim.name, location: location, lawName: law.name }
}
