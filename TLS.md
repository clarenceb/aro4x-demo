Custom domain and certs setup
=============================

Setup custom domain and certs for your cluster.

See official docs: https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster#prepare-a-custom-domain-for-your-cluster-optional

Pre-requisites
--------------

* You'll need to own a domain and have a access to DNS to create A/TXT records for that domain
* You'll need CA signed certificate and private key (e.g. wildcard domain) - you can use Let's encrypt to test this out with free certs

[Azure Key Vault](https://docs.microsoft.com/en-us/azure/key-vault/certificates/certificate-scenarios) can help to automate issuance and renewal or certificates for production environments.

Define environment variables
----------------------------

```sh
git clone https://github.com/clarenceb/aro4x-demo.git

cd aro4x-demo/
cp aro4-env.sh.template aro4-env.sh
# Edit aro4-env.sh to suit your environment

source ./aro4-env.sh
```

Configure DNS for default ingress router
----------------------------------------

```sh
# Retrieve the Ingress IP for Azure DNS records
INGRESS_IP="$( az aro show -n $CLUSTER -g $RESOURCEGROUP --query 'ingressProfiles[0].ip' -o tsv)"
```

This may be a public or private IP, depending on the ingress visibility you selected.

Create your Azure DNS zone for `$DOMAIN`.

Here we'll show how to do this for a private zone, assuming you created a private cluster and have a set up bastion host in the "utils-vnet".

```sh
az network private-dns zone create -g $RESOURCEGROUP -n $DOMAIN
az network private-dns link vnet create -g $RESOURCEGROUP -n PrivateDomainLink \
   -z $DOMAIN -v $UTILS_VNET -e true

# Create a wildcard `*.apps` A record to point to the Ingress Load Balancer IP
az network private-dns record-set a add-record \
  -g $RESOURCEGROUP \
  -z $DOMAIN \
  -n '*.apps' \
  -a $INGRESS_IP

# Adjust default TTL from 1 hour (choose an appropriate value, here 5 mins is used)
az network private-dns record-set a update   -g $RESOURCEGROUP   -z $DOMAIN   -n '*.apps' --set ttl=300
```

Configure DNS for API server endpoint
-------------------------------------

```sh
# Retrieve the API Server IP for Azure DNS records
API_SERVER_IP="$(az aro show -n $CLUSTER -g $RESOURCEGROUP --query 'apiserverProfile.ip' -o tsv)"
```

This may be a public or private IP, depending on the ingress visibility you selected.

Again, we'll show how to do this for a private zone, assuming you created a private cluster and have a set up bastion host in the "utils-vnet".

```sh
# Create a wildcard `*.apps` A record to point to the Ingress Load Balancer IP
az network private-dns record-set a add-record \
  -g $RESOURCEGROUP \
  -z $DOMAIN \
  -n 'api' \
  -a $API_SERVER_IP

# Adjust default TTL from 1 hour (choose an appropriate value, here 5 mins is used)
az network private-dns record-set a update   -g $RESOURCEGROUP   -z $DOMAIN   -n 'api' --set ttl=300
```

Generate Let's Encrypt Certificates for API Server and default Ingress Router
-----------------------------------------------------------------------------

The example below uses manually created Let's Encrypt certs.  This is **not recommended for production** unless you have setup an automated process to create and renew the certs.
These certs would expire after 90 days.

**Note:** this method requires public DNS to issue the certificates since DNS challenge is used.  Once the certificate is issued you can delete the public records if desired (for example if you created a private ARO cluster and intend to use Azure DNS private record sets).

Launch a bash shell (e.g. Git Bash on Windows).

```sh
git clone https://github.com/acmesh-official/acme.sh.git
chmod +x acme.sh/acme.sh

# Issue a new cert for domain api.aro.<DOMAIN>
./acme.sh --issue --dns -d "api.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please
```

Sample output:

```sh
[Fri Aug 21 03:22:32 AEST 2020] Using CA: https://acme-v02.api.letsencrypt.org/directory
[Fri Aug 21 03:22:32 AEST 2020] Create account key ok.
[Fri Aug 21 03:22:33 AEST 2020] Registering account: https://acme-v02.api.letsencrypt.org/directory
[Fri Aug 21 03:22:34 AEST 2020] Registered
[Fri Aug 21 03:22:34 AEST 2020] ACCOUNT_THUMBPRINT='xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
[Fri Aug 21 03:22:34 AEST 2020] Creating domain key
[Fri Aug 21 03:22:34 AEST 2020] The domain key is here: /home/<USER>/.acme.sh/api.<DOMAIN>/api.<DOMAIN>.key
[Fri Aug 21 03:22:34 AEST 2020] Single domain='api.<DOMAIN>'
[Fri Aug 21 03:22:34 AEST 2020] Getting domain auth token for each domain
[Fri Aug 21 03:22:37 AEST 2020] Getting webroot for domain='api.<DOMAIN>'
[Fri Aug 21 03:22:37 AEST 2020] Add the following TXT record:
[Fri Aug 21 03:22:37 AEST 2020] Domain: '_acme-challenge.api.<DOMAIN>'
[Fri Aug 21 03:22:37 AEST 2020] TXT value: 'xxxxxxx_xxxxxxx-xxxxxxxxxxxxxxxxxxxxx'
[Fri Aug 21 03:22:37 AEST 2020] Please be aware that you prepend _acme-challenge. before your domain
[Fri Aug 21 03:22:37 AEST 2020] so the resulting subdomain will be: _acme-challenge.api.<DOMAIN>
[Fri Aug 21 03:22:37 AEST 2020] Please add the TXT records to the domains, and re-run with --renew.
[Fri Aug 21 03:22:37 AEST 2020] Please add '--debug' or '--log' to check more details.
[Fri Aug 21 03:22:37 AEST 2020] See: https://github.com/acmesh-official/acme.sh/wiki/How-to-debug-acme.sh
```

Take note of the `Domain` and `TXT value` fields as these are required for Let's Encrypt to validate that you own the domain and can therefore issue you the certificates.

Create your public Azure DNS zone for `$DOMAIN` and connect your Domain Registrar to the Azure DNS servers for your public zone (steps not shown here, see Azure DNS docs).

Create two child zones `api.$DOMAIN` and `apps.$DOMAIN`.

Once you have the public DNS zones ready you can add the necessary records to validate ownership of the domain.

```sh
# Step 1 - Add the `_acme-challenge` TXT value to your public `api.<DOMAIN>` zone.

# Step 2 - Download the certs and key from Let's Encrypt
./acme.sh --renew --dns -d "api.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key

# Note: On Windows Server, you might need to install Cygwin (https://www.cygwin.com/install.html) to handle files
# starting with an asterix ('*') -- Git bash won't work here.  Install Cywin and choose the `base` component to install.
# Also install these components:
#  `dos2unix`, `curl`, libcurl`
#
# dos2unix <path-to-aro4x-demo>/aro4x-env.sh
# source <path-to-aro4x-demo>/aro4x-env.sh
# cd /cygdrive/c/Users/azureuser/<path-to-acme.sh>
# dos2unix acme.sh

# Issue a new cert for domain *.apps.<DOMAIN>
./acme.sh --issue --dns -d "*.apps.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please
```

Sample output:

```sh
[Fri Aug 21 03:43:03 AEST 2020] Using CA: https://acme-v02.api.letsencrypt.org/directory
[Fri Aug 21 03:43:03 AEST 2020] Creating domain key
[Fri Aug 21 03:43:03 AEST 2020] The domain key is here: /home/USER/.acme.sh/*.apps.<DOMAIN>/*.apps.<DOMAIN>.key
[Fri Aug 21 03:43:03 AEST 2020] Single domain='*.apps.<DOMAIN>'
[Fri Aug 21 03:43:03 AEST 2020] Getting domain auth token for each domain
[Fri Aug 21 03:43:07 AEST 2020] Getting webroot for domain='*.apps.<DOMAIN>'
[Fri Aug 21 03:43:07 AEST 2020] Add the following TXT record:
[Fri Aug 21 03:43:07 AEST 2020] Domain: '_acme-challenge.apps.<DOMAIN>'
[Fri Aug 21 03:43:07 AEST 2020] TXT value: 'xxxxxxxxxxxxxxxxxxxxxxxxxx'
[Fri Aug 21 03:43:07 AEST 2020] Please be aware that you prepend _acme-challenge. before your domain
[Fri Aug 21 03:43:07 AEST 2020] so the resulting subdomain will be: _acme-challenge.apps.<DOMAIN>
[Fri Aug 21 03:43:07 AEST 2020] Please add the TXT records to the domains, and re-run with --renew.
[Fri Aug 21 03:43:07 AEST 2020] Please add '--debug' or '--log' to check more details.
[Fri Aug 21 03:43:07 AEST 2020] See: https://github.com/acmesh-official/acme.sh/wiki/How-to-debug-acme.sh
```

Take note of the `Domain` and `TXT value` fields as these are required for Let's Encrypt to validate that you own the domain and can therefore issue you the certificates.

```sh
# Step 1 - Add the `_acme-challenge` TXT value to your public `apps.<DOMAIN>` zone.

# Step 2 - Download the certs and key from Let's Encrypt
./acme.sh --renew --dns -d "*.apps.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key
```

Now that you have valid certificates you can proceed with confguring OpenShift to trust your customer domain with these certs.

Configure the API server with custom certificates
-------------------------------------------------

For this step we assume you have these files for the domain `api.<DOMAIN>`:

* `fullchain.cer` certificate bundle
* `file.key` certificate private key
* `ca.cer` CA certificate bundle

Login to the ARO cluster with `oc` CLI (if required):

```sh
KUBEADMIN_PASSWD=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER --query "kubeadminPassword" -o tsv)
KUBEADMIN_PASSWD=$(echo $KUBEADMIN_PASSWD | sed 's/\r//g')
API_URL=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
API_URL=$(echo $API_URL | sed 's/\r//g')
oc login -u kubeadmin -p $KUBEADMIN_PASSWD --server=$API_URL
oc status
```

Configure the API Server certs:

```sh
cd ~/.acme.sh/api.$DOMAIN

# Add an API server named certificate
# See: https://docs.openshift.com/container-platform/4.4/security/certificates/api-server.html

oc create secret tls api-custom-domain \
     --cert=fullchain.cer \
     --key=api.$DOMAIN.key \
     -n openshift-config

# Note: substitute <DOMAIN> below for your customer domain
oc patch apiserver cluster \
--type=merge -p \
'{"spec":{"servingCerts": {"namedCertificates":
[{"names": ["api.<DOMAIN>"],
"servingCertificate": {"name": "api-custom-domain"}}]}}}'

oc get apiserver cluster -o yaml
```

Configure the Ingress Router with custom certificates
-----------------------------------------------------

For this step we assume you have these files for the domain `*.apps.<DOMAIN>`:

* `fullchain.cer` certificate bundle
* `file.key` certificate private key
* `ca.cer` CA certificate bundle

Login to the ARO cluster with `oc` CLI (if required):

```sh
KUBEADMIN_PASSWD=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER --query "kubeadminPassword" -o tsv)
KUBEADMIN_PASSWD=$(echo $KUBEADMIN_PASSWD | sed 's/\r//g')
API_URL=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
API_URL=$(echo $API_URL | sed 's/\r//g')
oc login -u kubeadmin -p $KUBEADMIN_PASSWD --server=$API_URL
oc status
```

Configure the (default) Ingress Router certs:

```sh
cd ~/.acme.sh/\*.apps.$DOMAIN/

# Replacing the default ingress certificate
# See: https://docs.openshift.com/container-platform/4.4/security/certificates/replacing-default-ingress-certificate.html

oc create configmap custom-ca \
     --from-file=ca.cer \
     -n openshift-config

oc patch proxy/cluster \
     --type=merge \
     --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'

 cp '*.apps.aro.clarenceb.com.key' file.key

oc create secret tls star-apps-custom-domain \
     --cert=fullchain.cer \
     --key=file.key \
     -n openshift-ingress

oc patch ingresscontroller.operator default \
     --type=merge -p \
     '{"spec":{"defaultCertificate": {"name": "star-apps-custom-domain"}}}' \
     -n openshift-ingress-operator
```

Test your custom domain
-----------------------

```sh
az aro list-credentials -n $CLUSTER -g $RESOURCEGROUP
```

Log into the OpenShift portal - this will test the API Server.

Deploy a simple NGINX pod and expose it via a route to test the private ingress route works witrh a custom domain:

```sh
oc new-app --docker-image nginx:latest
oc create route edge nginx --service=nginx
oc get route
#  nginx-default.apps.a<DOMAIN>
```

Access your TLS endpoint via the private domain: `https://nginx-default.apps.a<DOMAIN>` on your Bastion host.

To expose this publicly, you can use an Azure Application Gateway (see [README](./README.md) or create a second public Ingress router and expose the service via that router.

References
----------

* [Prepare a custom domain for your cluster](https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster#prepare-a-custom-domain-for-your-cluster-optional)
* [Replacing the default ingress certificate](https://docs.openshift.com/container-platform/4.6/security/certificates/replacing-default-ingress-certificate.html)
* [Adding API server certificates](https://docs.openshift.com/container-platform/4.6/security/certificates/api-server.html)