Demo App
========

## Demo of Source 2 Image for a microservices app

```sh
az aro list -o table
az aro list-credentials -g "${ARO_RESOURCEGROUP}" -n "${ARO_CLUSTER}"

oc login -u <kubeadmin-or-otheruser> --server=https://api.<aro-domain>:6443

# Create project
oc new-project mydemos

# Deploy mongo DB
oc get templates -n openshift
oc process openshift//mongodb-persistent -o yaml
oc process openshift//mongodb-persistent \
    -p MONGODB_USER=ratingsuser \
    -p MONGODB_PASSWORD=ratingspassword \
    -p MONGODB_DATABASE=ratingsdb \
    -p MONGODB_ADMIN_PASSWORD=ratingspassword | oc create -f -
oc status

# Deploy Ratings API
oc new-app https://github.com/microsoft/rating-api --strategy=source
oc set env dc rating-api MONGODB_URI=mongodb://ratingsuser:ratingspassword@mongodb.mydemos.svc.cluster.local:27017/ratingsdb

oc get svc rating-api
oc describe bc/rating-api

# Deploy Ratings Frontend
oc new-app https://github.com/microsoft/rating-web --strategy=source
oc set env dc rating-web API=http://rating-api:8080

oc expose svc/rating-web
oc get route rating-web
```

Access the web app using the URL from above.

Things to explore:

* Web console
* Admin perspective (logs, deployments, etc.)
* Developer perspective (builds, topology, etc.)

Cleanup:

```sh
oc delete project mydemos
```

## References

* [ARO Workshop](https://aroworkshop.io/) - currently, based on ARO 3.11 but the demo app steps are the same for V4.3.