#!/bin/bash
# Gateway Entra app: "PSA OEN Gateway" exposes scope OEN.Read; APIM validates tokens for it.
set -e
S=bd15c49d-3894-4d25-a9ec-d07c06ada81a
RG=rg-psa-oen-apim
STATE=$HOME/.psa-oen
cd /home/jtantra/dev/live/psa-oen-api/infra
case "$1" in
gwapp)
  GW=$(az ad app list --display-name "PSA OEN Gateway" --query "[0].appId" -o tsv)
  if [ -z "$GW" ]; then
    GW=$(az ad app create --display-name "PSA OEN Gateway" --sign-in-audience AzureADMyOrg --query appId -o tsv)
    az ad sp create --id $GW -o none
  fi
  OBJ=$(az ad app show --id $GW --query id -o tsv)
  SID=$(az ad app show --id $GW --query "api.oauth2PermissionScopes[?value=='OEN.Read'].id | [0]" -o tsv)
  [ -z "$SID" ] && SID=$(cat /proc/sys/kernel/random/uuid)
  cat > $STATE/gwapi.json <<EOF
{"identifierUris":["api://$GW"],
 "api":{"requestedAccessTokenVersion":2,
  "oauth2PermissionScopes":[{"id":"$SID","value":"OEN.Read","type":"User","isEnabled":true,
   "adminConsentDisplayName":"Read PSA OEN voyage data as you",
   "adminConsentDescription":"Lets the app read PSA OEN voyage data using your linked OEN account.",
   "userConsentDisplayName":"Read PSA OEN voyage data as you",
   "userConsentDescription":"Lets the app read PSA OEN voyage data using your linked OEN account."}]}}
EOF
  az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$OBJ" --body @$STATE/gwapi.json --headers Content-Type=application/json
  # Azure CLI as a pre-authorized test client (lets us mint a user token for smoke tests).
  cat > $STATE/gwpre.json <<EOF
{"api":{"preAuthorizedApplications":[{"appId":"04b07795-8ddb-461a-bbee-02f9e1bf7b46","delegatedPermissionIds":["$SID"]}]}}
EOF
  az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$OBJ" --body @$STATE/gwpre.json --headers Content-Type=application/json
  echo $GW > $STATE/gw-client-id
  echo "gateway app=$GW scope=$SID" ;;
apim)
  GW=$(cat $STATE/gw-client-id)
  LINK=https://$(az containerapp show -n oen-link -g $RG --subscription $S --query properties.configuration.ingress.fqdn -o tsv)
  KVURI=$(az keyvault show -n kv-psa-oen-hub --subscription $S --query properties.vaultUri -o tsv)
  az deployment group create --subscription $S -g $RG -n apim-oen-$(date +%s) -f apim-oen.bicep \
    -p apimName=apim-psa-oen-hub gwClientId=$GW linkUrl=$LINK kvUri=$KVURI -o json --query properties.outputs ;;
token)
  GW=$(cat $STATE/gw-client-id)
  az account get-access-token --scope "api://$GW/OEN.Read" --query accessToken -o tsv ;;
esac
