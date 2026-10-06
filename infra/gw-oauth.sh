#!/bin/bash
# Make "PSA OEN Gateway" usable as the Cowork OAuth client (auth-code + PKCE via Teams token store).
set -e
STATE=$HOME/.psa-oen
GW=$(cat $STATE/gw-client-id)
OBJ=$(az ad app show --id $GW --query id -o tsv)
cat > $STATE/gwweb.json <<EOF
{"web":{"redirectUris":["https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect"]}}
EOF
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$OBJ" --body @$STATE/gwweb.json --headers Content-Type=application/json
SECRET=$(az ad app credential reset --id $GW --display-name cowork-oauth --years 1 --append --query password -o tsv 2>/dev/null)
umask 077; printf '%s' "$SECRET" > $STATE/gw-client-secret
TID=$(az account show --query tenantId -o tsv)
echo "client_id=$GW"
echo "tenant=$TID"
az ad app show --id $GW --query "{uris:identifierUris,redirect:web.redirectUris,scopes:api.oauth2PermissionScopes[].value,pre:api.preAuthorizedApplications[].appId}" -o json
az ad sp show --id $GW --query "{sp:displayName,appRoleAssignmentRequired:appRoleAssignmentRequired}" -o json
