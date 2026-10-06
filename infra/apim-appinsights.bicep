// App Insights for APIM call tracing: logger + diagnostics for the OEN REST API and the OEN MCP server.
// Logs headers (Authorization masked) and up to 8 KB of request/response bodies so tools/call arguments
// and OEN query strings are visible. Drop samplingPct / bodyBytes for production.
param apimName string
param location string = resourceGroup().location
param appInsightsName string = 'appi-psa-oen'
param lawName string = 'law-psa-oen'
param apiIds array = [ 'oen', 'oen-mcp' ]
param samplingPct int = 100
param bodyBytes int = 8192

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appi.id
    credentials: {
      connectionString: appi.properties.ConnectionString
    }
  }
}

var http = {
  headers: [ 'Content-Type', 'mcp-session-id', 'X-Forwarded-For' ]
  body: { bytes: bodyBytes }
}

resource diags 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = [for a in apiIds: {
  name: '${apimName}/${a}/applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    verbosity: 'information'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: { samplingType: 'fixed', percentage: samplingPct }
    frontend: { request: http, response: http }
    backend: { request: http, response: http }
  }
}]

output appInsightsName string = appi.name
