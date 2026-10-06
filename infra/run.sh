#!/bin/bash
set -e
S=bd15c49d-3894-4d25-a9ec-d07c06ada81a
RG=rg-psa-oen-apim
APIM=apim-psa-oen-hub
KV=kv-psa-oen-hub
ACR=jtantratestacr
ACRRG=jtantra-test-rg
APP=oen-link
ROOT=/home/jtantra/dev/live/psa-oen-api
STATE=$HOME/.psa-oen
mkdir -p $STATE && chmod 700 $STATE
cd $ROOT/infra
EMAIL=$(az ad signed-in-user show --query userPrincipalName -o tsv)
common="apimName=$APIM kvName=$KV publisherEmail=$EMAIL acrName=$ACR acrResourceGroup=$ACRRG"

case "$1" in
build)
  az bicep build --file main.bicep --stdout >/dev/null && echo BUILD_OK ;;
whatif)
  az deployment group what-if --subscription $S -g $RG -f main.bicep -p $common --result-format ResourceIdOnly 2>&1 | grep -E '^ +[-~+=*!x] |Resource changes|Error|Delete|Modify' ;;
infra)
  az deployment group create --subscription $S -g $RG -n infra-$(date +%s) -f main.bicep -p $common -o json --query properties.outputs ;;
entra)
  FQDN=$APP.$(az containerapp env show -n cae-psa-oen -g $RG --subscription $S --query properties.defaultDomain -o tsv)
  CID=$(az ad app list --display-name "PSA OEN Link" --query "[0].appId" -o tsv)
  if [ -z "$CID" ]; then
    CID=$(az ad app create --display-name "PSA OEN Link" --sign-in-audience AzureADMyOrg \
      --web-redirect-uris "https://$FQDN/.auth/login/aad/callback" --enable-id-token-issuance true --query appId -o tsv)
    az ad sp create --id $CID -o none
  fi
  az ad app update --id $CID --identifier-uris "api://$CID" --web-redirect-uris "https://$FQDN/.auth/login/aad/callback"
  az ad app permission add --id $CID --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope -o none 2>/dev/null || true
  SECRET=$(az ad app credential reset --id $CID --display-name aca-auth --years 1 --query password -o tsv)
  umask 077; printf '%s' "$SECRET" > $STATE/client-secret; echo "$CID" > $STATE/client-id
  echo "client=$CID fqdn=$FQDN" ;;
image)
  TAG=$(cd $ROOT/linking-app && cat app.py requirements.txt Dockerfile | sha256sum | cut -c1-12)
  echo $TAG > $STATE/tag
  PYTHONIOENCODING=utf-8 az acr build --subscription $S -r $ACR -t oen-link:$TAG $ROOT/linking-app --no-logs -o none
  az acr repository show -n $ACR --image oen-link:$TAG --query digest -o tsv ;;
app)
  TAG=$(cat $STATE/tag)
  az deployment group create --subscription $S -g $RG -n app-$(date +%s) -f main.bicep -p $common \
    linkImage=$ACR.azurecr.io/oen-link:$TAG entraClientId=$(cat $STATE/client-id) \
    entraClientSecret="$(cat $STATE/client-secret)" buildId=$TAG -o json --query properties.outputs ;;
verify)
  az apim show -n $APIM -g $RG --subscription $S --query "{sku:sku.name,state:provisioningState,vnet:virtualNetworkType,subnet:virtualNetworkConfiguration.subnetResourceId}" -o json
  az keyvault show -n $KV --subscription $S --query "{pna:properties.publicNetworkAccess}" -o json
  az network private-dns record-set a list -g $RG -z privatelink.vaultcore.azure.net --subscription $S --query "[].{n:name,ip:aRecords[0].ipv4Address}" -o tsv
  az containerapp show -n $APP -g $RG --subscription $S --query "{fqdn:properties.configuration.ingress.fqdn,rev:properties.latestReadyRevisionName,img:properties.template.containers[0].image}" -o json 2>/dev/null || true
  az role assignment list --scope $(az keyvault show -n $KV --subscription $S --query id -o tsv) --query "[].{p:principalName,r:roleDefinitionName}" -o tsv ;;
esac
