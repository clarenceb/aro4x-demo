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

Open the ARO Console URL in your browser and log in as `kubeadmin` and enter the password retrived via `az aro list-credentials ...`.

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

### Deploy Rating Api (from source code in GitHub using source strategy)

```sh
oc new-app https://github.com/clarenceb/rating-api --strategy=source

MONGODB_URI="mongodb://$MONGODB_USERNAME:$MONGODB_PASSWORD@mongodb.$PROJECT.svc.cluster.local:27017/ratingsdb"

oc set env deploy/rating-api MONGODB_URI=$MONGODB_URI

oc port-forward svc/rating-api 8080:8080 &

curl -s http://localhost:8080/api/items | jq .

jobs
kill %1
```

### Optional - Deploy Rating API (from pre-built Docker image in ACR)

```sh
az acr build -r $ACRNAME -t rating-api:v1-ubi8 https://github.com/clarenceb/rating-api

# Create image pull secret and link to default service account
ACR_USERNAME="$(az acr credential show -n $ACRNAME -g $RESOURCEGROUP --query username -o tsv)"
ACR_PASSWD="$(az acr credential show -n $ACRNAME -g $RESOURCEGROUP --query passwords[0].value -o tsv)"

oc create secret docker-registry $ACRNAME-secret \
    --docker-server=$ACRNAME.azurecr.io \
    --docker-username=$ACR_USERNAME \
    --docker-password=$ACR_PASSWD \
    --docker-email=admin@example.com

oc secrets link default $ACRNAME-secret --for=pull

oc delete all -l app=rating-api

oc import-image rating-api:v1 --from $ACRNAME.azurecr.io/rating-api:v1-ubi8 --reference-policy=local --confirm
oc label imagestream/rating-api app=rating-api

oc new-app --name rating-api --image-stream rating-api:v1 -e MONGODB_URI=$MONGODB_URI
```

To deploy an updated image from the external registry:

```sh
NEW_TAG=gh-v1.0.16
oc tag $ACRNAME.azurecr.io/rating-api:$NEW_TAG rating-api:v1 --reference-policy local 
```

### Deploy Rating Web (from source code in GitHub using Docker build strategy)

```sh
oc new-app https://github.com/clarenceb/rating-web --strategy=docker

oc set env deploy rating-web API=http://rating-api:8080
```

### Optional - Deploy Rating Web (from pre-built Docker image in ACR)

```sh
az acr build -r $ACRNAME -t rating-web:v1 https://github.com/clarenceb/rating-web

# Create image pull secret and link to default service account
ACR_USERNAME="$(az acr credential show -n $ACRNAME -g $RESOURCEGROUP --query username -o tsv)"
ACR_PASSWD="$(az acr credential show -n $ACRNAME -g $RESOURCEGROUP --query passwords[0].value -o tsv)"

oc create secret docker-registry $ACRNAME-secret \
    --docker-server=$ACRNAME.azurecr.io \
    --docker-username=$ACR_USERNAME \
    --docker-password=$ACR_PASSWD \
    --docker-email=admin@example.com

oc secrets link default $ACRNAME-secret --for=pull

oc delete all -l app=rating-web

oc import-image rating-web:v1 --from $ACRNAME.azurecr.io/rating-web:v1 --reference-policy=local --confirm
oc label imagestream/rating-web app=rating-web

oc new-app --name rating-web --image-stream rating-web:v1 -e API=http://rating-api:8080
```

To deploy an updated image from the external registry:

```sh
NEW_TAG=gh-v1.0.16
oc tag $ACRNAME.azurecr.io/rating-web:$NEW_TAG rating-web:v1 --reference-policy local 
```

### Expose TLS route for the Web frontend

```sh
# Create a TLS edge route
oc create route edge rating-web --service=rating-web
oc get route rating-web
```

### (Optional) Reset state for in-cluster database without persistent volume

- Delete the MongoDB pod

```sh
oc delete all -l app=mongodb
```

- Delete the Rating API pod (to populate the MongoDB collections)

```sh
oc delete pod rating-api-xxxxxxxxxxxxxx
```

Open the front end in your browser: `https://rating-web-ratingapp.apps.[domain].[location].aroapp.io/`

ACA STEPS
---------

### Build the Rating API image

```sh
az acr build -r $ACRNAME -t rating-api:v1 https://github.com/clarenceb/rating-api -f Dockerfile
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

az containerapp revision list -n rating-api -g $RESOURCE_GROUP -o table
```

### Deploy the Rating Web container app

```sh
# Dapr invocation URL for Rating API (works via service discovery when Dapr is enabled)
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

### Ratings API CI/CD pipeline (GitHub Actions)

See file: [.github/workflows/docker-image.yml](https://github.com/clarenceb/rating-api/blob/master/.github/workflows/docker-image.yml)

Check that the [workflow](https://github.com/clarenceb/rating-api/actions/workflows/docker-image.yml) is enabled by clicking the ellipsis `[...]` and choosing **Enable workflow** (if its currently disabled).

The following Repository secrets are needed:

- ACR_LOGIN_SERVER
- ASC_APPINSIGHTS_CONNECTION_STRING
- ASC_AUTH_TOKEN
- REGISTRY_PASSWORD
- REGISTRY_PASSWORD

The following Environments are needed:

- dev-containerapps

  - Environment secrets:

    - CAPPS_MONGODB_URI
    - CONTAINERAPPS_ENVIRONMENT
    - LOCATION
    - RESOURCE_GROUP
    - AZURE_CREDENTIALS

  - Create [Azure Credentials](https://github.com/marketplace/actions/azure-login#configure-deployment-credentials) service principal:

  ```sh
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  # RESOURCE_GROUP should be the resource group of your container apps environment
  az ad sp create-for-rbac --name "dev-containerapps-sp" --role contributor \
                           --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP \
                           --sdk-auth > ./dev-containerapps-sp.json
  ```

  - Paste contents of file `dev-containerapps-sp.json` into an Environment Secret named `AZURE_CREDENTIALS`

- dev-aro

  - Environment secrets:

    - OPENSHIFT_SERVER

    ```sh
    oc whoami --show-server
    ```

    - OPENSHIFT_NAMESPACE

    ```sh
    echo $PROJECT
    ```

    - OPENSHIFT_TOKEN

    ```sh
    # First, name your Service Account (the Kubernetes shortname is "sa")
    SA=github-actions-sa

    # oc new-project $OPENSHIFT_NAMESPACE # Create a new project (namespace)
    oc project $OPENSHIFT_NAMESPACE # Switch to existing project

    # and create it.
    oc create sa $SA

    # Grant permissions to update resources in the OPENSHIFT_NAMESPACE
    oc policy add-role-to-user edit -z $SA

    # Now, we have to find the name of the secret in which the Service Account's apiserver token is stored.
    # The following command will output two secrets. 
    SECRETS=$(oc get sa $SA -o jsonpath='{.secrets[*].name}{"\n"}') && echo $SECRETS
    # Select the one with "token" in the name - the other is for the container registry.
    SECRET_NAME=$(printf "%s\n" $SECRETS | grep "token") && echo $SECRET_NAME

    # Get the token from the secret. 
    ENCODED_TOKEN=$(oc get secret $SECRET_NAME -o jsonpath='{.data.token}{"\n"}') && echo $ENCODED_TOKEN;
    TOKEN=$(echo $ENCODED_TOKEN | base64 -d) && echo $TOKEN
    # eyJhb...<jwt>...
    ```

    - CAPPS_MONGODB_URI

    ```sh
    echo $CAPPS_MONGODB_URI
    ```

Refer to [Using a Service Account for GitHub Actions](https://github.com/redhat-actions/oc-login/wiki/Using-a-Service-Account-for-GitHub-Actions) for instructions on creating the OPENSHIFT_TOKEN.

More info on the [openshift-login](https://github.com/marketplace/actions/openshift-login) GitHub action.

Azure Monitor (Container Insights via Azure Arc-enabled Kubernetes)
-------------------------------------------------------------------

Go to ARO Arc resource / Insights in the Azure Portal.

* Health, nodes, pods, live logs, metrics, recommended alerts
* Go to Contaihners, filter by namespace "ratingsapp", filter to "api"
* Open Live Logs, submit a rating in the web app
* Reports
  * Workload Details
  * Data Usage
  * Persistent Volume Details
* Recommended alerts
* Logs

Open the KQL query editor in the "Logs" blade of the ARO Arc resource and try some queries.

Investigate some app logs where votes were placed:

```kql
ContainerLog
| where LogEntry contains "Saving rating"
```

See average rating per fruit:

```kql
ContainerLog
| where LogEntry contains "Saving rating"
| parse LogEntry with * "itemRated: [ " itemCode " ]" * "rating: " rating " }" *
| extend fruit=
    replace_string(
        replace_string(
            replace_string(
                replace_string(itemCode, '62f6fb3f209fa5001777fea0', 'Banana'),
            '62f6fb3f209fa5001777fea1', 'Coconut'),
        '62f6fb3f209fa5001777fea2', 'Oranges'),
    '62f6fb3f209fa5001777fea3', 'Pineapple')
| project fruit, rating
| summarize AvgRating=avg(toint(rating)) by fruit
```

Choose "Chart" to see a visualisation of the average votes.

Note: Your item ids will be different.  Run a Mongo query to find your ids, like so:

```sh
oc port-forward --namespace ratingsapp svc/mongodb 27017:27017 &
mongosh --host 127.0.0.1 --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD

use ratingsdb
db.items.find()
quit

kill %1
```

See number of votes submitted over time:

```sh
ContainerLog
| where LogEntry contains "Saving rating"
| summarize NumberOfVotes=count()/4 by bin(TimeGenerated, 15m)
| render areachart
```

Kube event failures:

```kql
KubeEvents
| where TimeGenerated > ago(24h)
| where Reason in ("Failed")
| summarize count() by Reason, bin(TimeGenerated, 5m)
| render areachart
```

Pod failures (e.g. ImagePullBackOff):

```kql
KubeEvents
| where TimeGenerated > ago(24h)
| where Reason in ("Failed")
| where ObjectKind == "Pod"
| project TimeGenerated, ObjectKind, Name, Namespace, Message
```

### Try some other KQL queries

List container images deployed in the cluster:

```kql
ContainerInventory
| distinct Repository, Image, ImageTag
| where Image contains "rating"
| render table
```

List container inventory and state:

```kql
ContainerInventory
| project Computer, Name, Image, ImageTag, ContainerState, CreatedTime, StartedTime, FinishedTime
| render table
```

List Kubernetes Events:

```kql
KubeEvents
| where not(isempty(Namespace))
| sort by TimeGenerated desc
| render table
```

List Azure Diagnostic categories:

```kql
AzureDiagnostics
| distinct Category
```
