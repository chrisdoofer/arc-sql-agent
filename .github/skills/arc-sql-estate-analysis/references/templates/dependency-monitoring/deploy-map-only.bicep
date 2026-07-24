targetScope = 'resourceGroup'

@description('Name of the dedicated Log Analytics workspace used for the 24-hour dependency capture.')
param workspaceName string

@description('Azure region for the workspace and DCR.')
param location string = resourceGroup().location

@description('Name of the Map-only data collection rule.')
param dcrName string = 'arc-sql-dependency-map-only'

@description('Retention in days. 30 keeps the short capture inside the free retention window.')
@minValue(30)
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      searchVersion: 1
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  properties: {
    description: 'Arc SQL VM Insights dependency capture — Map-only (Microsoft-ServiceMap only, no InsightsMetrics).'
    dataSources: {
      extensions: [
        {
          name: 'DependencyAgentDataSource'
          extensionName: 'DependencyAgent'
          streams: [
            'Microsoft-ServiceMap'
          ]
          extensionSettings: {}
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'dependencyWorkspace'
          workspaceResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ServiceMap'
        ]
        destinations: [
          'dependencyWorkspace'
        ]
      }
    ]
  }
}

output workspaceResourceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
output dcrResourceId string = dcr.id
