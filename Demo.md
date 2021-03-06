Demo App
========

## Demo of Source-to-Image (S2I) for a microservices app

Login via `oc` CLI
------------------

```sh
source ./aro4-env.sh

API_URL=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
KUBEADMIN_PASSWD=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER | jq -r .kubeadminPassword)

oc login -u kubeadmin -p $KUBEADMIN_PASSWD --server=$API_URL
oc status

# Create project
PROJECT=workshop
oc new-project $PROJECT

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
oc set env deploy rating-api MONGODB_URI=mongodb://ratingsuser:ratingspassword@mongodb.$PROJECT.svc.cluster.local:27017/ratingsdb

oc get svc rating-api
oc describe bc/rating-api

# Deploy Ratings Frontend
oc new-app https://github.com/microsoft/rating-web --strategy=source
oc set env deploy rating-web API=http://rating-api:8080

# Expose service using a route method from the ones below (depending on your setup):

# 1. Default route
oc expose svc/rating-web

# 2. Edge route (<service>.<apps>.<custom-domain>) - Terminates TLS at router (use this is you set up your custom domain on the ingress router)
oc create route edge --service=rating-web

# 3. Edge route with another domain, not the default router domain (optional CA, cert, key; if different from the default ingress/router setup)
oc create route edge --service=rating-web --hostname=<another-domain> --ca-cert=<path-to-ca-cert> --cert=<path-to-cert> --key=<path-to-key>
# Test when using different domain to the default router
curl https://rating-web.<another-domain> --resolve 'rating-web.<another-domain>:443:<router_ip_address>'

# If using App Gateway, update the HTTP Settings and specify a Host name override with specific domain name (and backend pool can use IP address)

# 4. Re-encrypt

TODO

# 5. Pass-through

TODO

oc get route rating-web
```

Access the web app using the URL from above.

Things to explore:

* Web console
* Admin perspective (logs, deployments, etc.)
* Developer perspective (builds, topology, etc.)

Cleanup:

```sh
oc delete project $PROJECT
```

## References

* [ARO Workshop](https://aroworkshop.io/)
