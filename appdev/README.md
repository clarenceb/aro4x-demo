App Dev on ARO + Azure Container Apps
=====================================

Common Steps
------------

- Create Azure Container Registry

```sh
source aro4-env.sh
ACRNAME="demoacr$RANDOM"

az group create \
    --name $RESOURCEGROUP \
    --location $LOCATION

az acr create -n $ACRNAME -g $RESOURCEGROUP --sku Standard -l $LOCATION --admin-enabled
```

Run the app locally with Docker Compose
---------------------------------------

```sh
git clone https://github.com/clarenceb/rating-web

docker-compose build
docker-compose up
# browse to: http://localhost:8081
# CTRL+C
docker-compose down
```

ARO Steps
---------

Refer to the ARO Workshop for details: https://microsoft.github.io/aroworkshop/

### Create the ARO cluster

```sh
source aro4-env.sh

az group create \
    --name $RESOURCEGROUP \
    --location $LOCATION

az network vnet create \
    --resource-group $RESOURCEGROUP \
    --name aro-vnet \
    --address-prefixes 10.0.0.0/22

az network vnet subnet create \
    --resource-group $RESOURCEGROUP \
    --vnet-name aro-vnet \
    --name master-subnet \
    --address-prefixes 10.0.0.0/23 \
    --service-endpoints Microsoft.ContainerRegistry

az network vnet subnet create \
    --resource-group $RESOURCEGROUP \
    --vnet-name aro-vnet \
    --name worker-subnet \
    --address-prefixes 10.0.2.0/23  \
    --service-endpoints Microsoft.ContainerRegistry

 az network vnet subnet update \
    --name master-subnet 
    --resource-group $RESOURCEGROUP \
    --vnet-name aro-vnet \
    --disable-private-link-service-network-policies true

az aro create \
    --resource-group $RESOURCEGROUP \
    --name $CLUSTER \
    --vnet $VNET \
    --master-subnet master-subnet \
    --worker-subnet worker-subnet 
    --pull-secret @pull-secret.txt

az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER

# ==> {
#         "kubeadminPassword": "<password>",
#         "kubeadminUsername": "kubeadmin"
#     }

az aro show \
    --name $CLUSTER \
    --resource-group $RESOURCEGROUP \
    --query "consoleProfile.url" -o tsv

# ==> https://console-openshift-console.apps.<domain>.<location>.aroapp.io/
```

Open the ARO Consule URL in your browser and log in as `kubeadmin` and enter the password retrived via `az aro list-credentials ...`.

Login via the CLI (either retrieve `oc` login from the console to login with a token or login with the `kubeadmin` user):

```sh
ARO_API_URI="$(az aro show --name $CLUSTER --resource-group $RESOURCEGROUP --query "apiserverProfile.url" -o tsv)"
ARO_PASSWORD="$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER | jq -r ".kubeadminPassword")"
oc login $ARO_API_URI -u kubeadmin -p $ARO_PASSWORD
oc status
```

### Create the project

```sh
PROJECT=ratingapp
oc new-project $PROJECT
```

### Create in-cluster MongoDB

```sh
MONGODB_USERNAME=ratingsuser
MONGODB_PASSWORD=ratingspassword
MONGODB_DATABASE=ratingsdb
MONGODB_ROOT_USER=root
MONGODB_ROOT_PASSWORD=ratingspassword

oc new-app bitnami/mongodb:5.0 \
  -e MONGODB_USERNAME=$MONGODB_USERNAME \
  -e MONGODB_PASSWORD=$MONGODB_PASSWORD \
  -e MONGODB_DATABASE=$MONGODB_DATABASE \
  -e MONGODB_ROOT_USER=$MONGODB_ROOT_USER \
  -e MONGODB_ROOT_PASSWORD=$MONGODB_ROOT_PASSWORD
```

### Deploy Rating App (from source code in GitHub using source strategy)

```sh
oc new-app https://github.com/clarenceb/rating-api --strategy=source

oc set env deploy/rating-api MONGODB_URI="mongodb://$MONGODB_USERNAME:$MONGODB_PASSWORD@mongodb.$PROJECT.svc.cluster.local:27017/ratingsdb"

oc port-forward svc/rating-api 8080:8080 &

curl -s http://localhost:8080/api/items | jq .

jobs
kill %1
```

### Deploy Rating Web (from source code in GitHub using Docker build strategy)

```sh
oc new-app https://github.com/clarenceb/rating-web --strategy=docker

oc set env deploy rating-web API=http://rating-api:8080
```

### Optional - Deploy Rating Web (from pre-built Docker image in ACR)

```sh
az acr build -r $ACRNAME -t rating-web:v1 https://github.com/clarenceb/rating-web

ACR_USERNAME="$(az acr credential show -n $ACRNAME -g $RESOURCEGROUP --query username -o tsv)"
ACR_PASSWD="$(az acr credential show -n $ACRNAME -g $RESOURCEGROUP --query passwords[0].value -o tsv)"

oc create secret docker-registry $ACRNAME-secret \
    --docker-server=$ACRNAME.azurecr.io \
    --docker-username=$ACR_USERNAME \
    --docker-password=$ACR_PASSWD \
    --docker-email=admin@example.com

oc secrets link default $ACRNAME-secret --for=pull

oc delete all -l app=rating-web
oc new-app $ACRNAME.azurecr.io/rating-web:v1 -e API=http://rating-api:8080
```

### Expose TLS route for the Web frontend

```sh
# Create a TLS edge route
oc create route edge rating-web --service=rating-web
oc get route rating-web
```

### (Optional) Reset state for in-cluster database without persistent volume

- Delete the MondoDB pod
- Delete the Rating API pod (to populate the MongoDB collections)

Open the front end in your browser: `https://rating-web-ratingapp.apps.[domain].[location].aroapp.io/`

ACA STEPS
---------

### Build the Rating API image

```sh
az acr build -r $ACRNAME -t rating-api:v1 https://github.com/clarenceb/rating-api -f Dockerfile.k8s
```

### Create the Container apps environment

```sh
RESOURCE_GROUP="containerapps"
LOCATION="australiaeast"
CONTAINERAPPS_ENVIRONMENT="ratingapp"

az group create -n $RESOURCE_GROUP -l $LOCATION

LOG_ANALYTICS_WORKSPACE="logs-${CONTAINERAPPS_ENVIRONMENT}"

az monitor log-analytics workspace create \
  --resource-group $RESOURCE_GROUP \
  --workspace-name $LOG_ANALYTICS_WORKSPACE

LOG_ANALYTICS_WORKSPACE_CLIENT_ID=$(az monitor log-analytics workspace show \
    --query customerId -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE --out tsv)

LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET=$(az monitor log-analytics workspace get-shared-keys \
    --query primarySharedKey -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE --out tsv)

APP_INSIGHTS_NAME="appins-${CONTAINERAPPS_ENVIRONMENT}"

LOG_ANALYTICS_WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show \
    --query id -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE --out tsv)

az monitor app-insights component create \
    --app $APP_INSIGHTS_NAME \
    --location $LOCATION \
    --kind web \
    -g $RESOURCE_GROUP \
    --workspace "$LOG_ANALYTICS_WORKSPACE_RESOURCE_ID"

APP_INSIGHTS_INSTRUMENTATION_KEY=$(az monitor app-insights component show --app $APP_INSIGHTS_NAME -g $RESOURCE_GROUP --query instrumentationKey -o tsv)

az containerapp env create \
  --name $CONTAINERAPPS_ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --location "$LOCATION" \
  --logs-workspace-id $LOG_ANALYTICS_WORKSPACE_CLIENT_ID \
  --logs-workspace-key $LOG_ANALYTICS_WORKSPACE_CLIENT_SECRET \
  --dapr-instrumentation-key $APP_INSIGHTS_INSTRUMENTATION_KEY

REGISTRY_RESOURCE_GROUP="aro-demo"
REGISTRY_USERNAME=$(az acr credential show --resource-group $REGISTRY_RESOURCE_GROUP --name $ACRNAME --query username -o tsv)
REGISTRY_PASSWORD=$(az acr credential show --resource-group $REGISTRY_RESOURCE_GROUP --name $ACRNAME --query passwords[0].value -o tsv)
REGISTRY_SERVER="$ACRNAME.azurecr.io"
```

### Deploy MongoDB API for Cosmos DB

```sh
COSMOS_ACCOUNT_NAME=ratingapp$RANDOM
COSMOS_LOCATION=australiasoutheast
SEMVER_VERSION=4.2

az cosmosdb create \
  --resource-group $RESOURCE_GROUP \
  --name $COSMOS_ACCOUNT_NAME \
  --kind MongoDB \
  --enable-automatic-failover false \
  --default-consistency-level "Eventual" \
  --server-version $SEMVER_VERSION \
  --locations regionName="$COSMOS_LOCATION" failoverPriority=0 isZoneRedundant=False

az cosmosdb mongodb database create \
    --account-name $COSMOS_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --name $MONGODB_DATABASE \
    --throughput 400
```

### Deploy the Rating API container app

CAPPS_MONGODB_URI=$(az cosmosdb list-connection-strings \
    --name $COSMOS_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "connectionStrings[0].connectionString" \
    -o tsv)

CAPPS_MONGODB_URI=$(echo $CAPPS_MONGODB_URI | sed 's/&maxIdleTimeMS=[0-9]\+//g' | sed 's/\/?/\/ratingsdb?/g')

```sh
az containerapp create \
  --name rating-api \
  --resource-group $RESOURCE_GROUP \
  --image $REGISTRY_SERVER/rating-api:v1 \
  --environment $CONTAINERAPPS_ENVIRONMENT \
  --registry-server $REGISTRY_SERVER \
  --registry-username $REGISTRY_USERNAME \
  --registry-password $REGISTRY_PASSWORD \
  --min-replicas 1 \
  --max-replicas 1 \
  --enable-dapr \
  --dapr-app-port 8080 \
  --dapr-app-id rating-api \
  --dapr-app-protocol http \
  --secrets "mongodb-uri=$CAPPS_MONGODB_URI" \
  --env-vars "MONGODB_URI=secretref:mongodb-uri" 
```

### Deploy the Rating Web container app

```sh
RATING_API_URI="http://localhost:3500/v1.0/invoke/rating-api/method"

az containerapp create \
  --name rating-web \
  --resource-group $RESOURCE_GROUP \
  --image $REGISTRY_SERVER/rating-web:v1 \
  --environment $CONTAINERAPPS_ENVIRONMENT \
  --registry-server $REGISTRY_SERVER \
  --registry-username $REGISTRY_USERNAME \
  --registry-password $REGISTRY_PASSWORD \
  --min-replicas 1 \
  --max-replicas 1 \
  --ingress 'external' \
  --target-port 8080 \
  --enable-dapr \
  --dapr-app-port 8080 \
  --dapr-app-id rating-web \
  --env-vars "API=$RATING_API_URI"

az containerapp revision list -n rating-web -g $RESOURCE_GROUP -o table

FRONTEND_INGRESS_URL=$(az containerapp show -n rating-web -g $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)

echo "Browse to: https://$FRONTEND_INGRESS_URL"

# Access the site and stream logs to console (press CTRL+C to stop following log stream):
az containerapp logs show -n rating-api -g $RESOURCE_GROUP --follow --tail=50
az containerapp logs show -n rating-web -g $RESOURCE_GROUP --follow --tail=50
```
