#!/bin/bash
# usage: calls.sh [minutes] -> APIM calls incl. query string
S=bd15c49d-3894-4d25-a9ec-d07c06ada81a
W=$(az monitor log-analytics workspace show -g rg-psa-oen-apim -n law-psa-oen --subscription $S --query customerId -o tsv)
az monitor log-analytics query -w $W -o tsv --analytics-query "
ApiManagementGatewayLogs | where TimeGenerated > ago(${1:-20}m)
| project t=format_datetime(TimeGenerated,'HH:mm:ss'), ApiId, OperationId, ResponseCode, BackendResponseCode, ms=TotalTime, ip=CallerIpAddress, q=url_decode(tostring(split(Url,'?')[1])), path=tostring(parse_url(Url).Path)
| order by t asc"
