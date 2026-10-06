// OEN REST API + MCP server on the existing APIM.
param apimName string
param gwClientId string
param linkUrl string
param kvUri string
param oenApiBase string = 'https://sandbox.api.n2n.globalpsa.com/api/'
param oenWebOrigin string = 'https://sandbox.n2n.globalpsa.com'

resource apim 'Microsoft.ApiManagement/service@2025-09-01-preview' existing = {
  name: apimName
}

var nv = {
  'oen-tenant-id': tenant().tenantId
  'oen-gw-client-id': gwClientId
  'oen-link-url': linkUrl
  'oen-kv-uri': kvUri
  'oen-api-base': oenApiBase
  'oen-web-origin': oenWebOrigin
}

resource namedValues 'Microsoft.ApiManagement/service/namedValues@2025-09-01-preview' = [for k in items(nv): {
  parent: apim
  name: k.key
  properties: { displayName: k.key, value: k.value, secret: false }
}]

resource api 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'oen'
  properties: {
    displayName: 'PSA OEN (per-user)'
    description: 'Read-only PSA N2N OEN voyage data, called as the signed-in user via their linked OEN account.'
    path: 'oen'
    protocols: [ 'https' ]
    serviceUrl: oenApiBase
    subscriptionRequired: false
    apiType: 'http'
  }
  dependsOn: [ namedValues ]
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: api
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/oen-api.xml') }
}

resource opList 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: api
  name: 'list-voyages'
  properties: {
    displayName: 'list_voyages'
    method: 'GET'
    urlTemplate: '/voyages'
    description: 'List OEN voyages, filtered and trimmed. Each voyage includes voyId, vessel, service, operator, networkSavingsHrs (OEN totalAptSavings), atRisk + atRiskReason, worstNode, recoveryNode (actual or projected), and a slim per-node list (node, order, status, berthDate + basis, APT savings, remarks). Use voyId with get_voyage / get_voyage_nodes. Results are capped by limit (default 50, max 200); check truncated.'
    request: {
      queryParameters: [
        { name: 'nodes', type: 'string', required: false, description: 'Comma-separated terminal codes, e.g. PSASG,PMUMB,BHCT. Keeps voyages calling ANY of these nodes (within the date window if given). Use real node codes, never region labels.' }
        { name: 'from', type: 'string', required: false, description: 'Start of berthing window, ISO date or datetime (UTC), e.g. 2026-10-01.' }
        { name: 'to', type: 'string', required: false, description: 'End of berthing window, inclusive, ISO date or datetime (UTC), e.g. 2026-10-31.' }
        { name: 'vessel', type: 'string', required: false, description: 'Vessel name contains (case-insensitive).' }
        { name: 'service', type: 'string', required: false, description: 'Exact service code, e.g. EC3.' }
        { name: 'operator', type: 'string', required: false, description: 'Exact vessel operator code, e.g. ONE.' }
        { name: 'at_risk_only', type: 'boolean', required: false, description: 'true = only at-risk voyages (risk node status or negative network savings), sorted worst first.' }
        { name: 'limit', type: 'integer', required: false, description: 'Max voyages to return (1-200, default 50).' }
      ]
    }
  }
}

resource opListPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: opList
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/list-voyages.xml') }
}

resource opGet 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: api
  name: 'get-voyage'
  properties: {
    displayName: 'get_voyage'
    method: 'GET'
    urlTemplate: '/voyages/{voyId}'
    description: 'Full OEN voyage record by voyId: vessel metadata (IMO, TEU/ton capacity, draught, navigation status, position) and per-node summary.'
    templateParameters: [ { name: 'voyId', type: 'integer', required: true, description: 'OEN voyage id from list_voyages.' } ]
  }
}

resource opGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: opGet
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/get-voyage.xml') }
}

resource opNodes 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: api
  name: 'get-voyage-nodes'
  properties: {
    displayName: 'get_voyage_nodes'
    method: 'GET'
    urlTemplate: '/voyages/{voyId}/nodes'
    description: 'Per-node performance detail for one voyage: timings (requested/agreed/estimated/actual berth and unberth), APT baseline/revised/actual and savings (actual + projected), volumes, GBP baseline/revised/current/actual, OCI/PCI, twin-lift, high-hoist, wait times, ABT fulfilment, bunker and carbon. Use for recovery-lever analysis.'
    templateParameters: [ { name: 'voyId', type: 'integer', required: true, description: 'OEN voyage id from list_voyages.' } ]
  }
}

resource opNodesPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: opNodes
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/get-voyage-nodes.xml') }
}

// ---- MCP server exposing the three operations as tools ----
resource mcp 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'oen-mcp'
  properties: {
    type: 'mcp'
    displayName: 'PSA OEN MCP'
    description: 'PSA N2N OEN voyage tools, run as the signed-in user.'
    path: 'oen-mcp'
    protocols: [ 'https' ]
    subscriptionRequired: false
  }
  dependsOn: [ namedValues ]
}

resource mcpPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: mcp
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('policies/mcp.xml') }
}

var tools = [
  { name: 'list_voyages', op: 'list-voyages', desc: 'List PSA OEN voyages with filters (nodes, from/to berthing window, vessel, service, operator, at_risk_only, limit). Returns trimmed voyages with voyId, networkSavingsHrs, atRisk/atRiskReason, worstNode, recoveryNode and per-node status/berth date/APT savings. Check truncated and matched.' }
  { name: 'get_voyage', op: 'get-voyage', desc: 'Full PSA OEN voyage record by voyId: vessel metadata (IMO, capacity, draught, navigation status, position) and per-node summary.' }
  { name: 'get_voyage_nodes', op: 'get-voyage-nodes', desc: 'Per-node performance detail for one PSA OEN voyage by voyId: berth timings, APT baseline/revised/actual + actual/projected savings, volumes, GBP, OCI/PCI, twin-lift, high-hoist, wait times, ABT fulfilment, bunker/carbon. Use for recovery levers.' }
]

resource mcpTools 'Microsoft.ApiManagement/service/apis/tools@2025-09-01-preview' = [for t in tools: {
  parent: mcp
  dependsOn: [ opList, opGet, opNodes ]
  name: t.name
  properties: {
    displayName: t.name
    description: t.desc
    operationId: resourceId('Microsoft.ApiManagement/service/apis/operations', apimName, api.name, t.op)
  }
}]

output restBase string = '${apim.properties.gatewayUrl}/oen'
output mcpUrl string = '${apim.properties.gatewayUrl}/oen-mcp/mcp'
