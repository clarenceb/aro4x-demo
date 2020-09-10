Customer domain and certs setup
===============================

Setup custom domain and certs for your cluster.
See: https://docs.microsoft.com/en-us/azure/openshift/tutorial-create-cluster#prepare-a-custom-domain-for-your-cluster-optional

You'll need to own a domain and have a access to create record sets and update A/TXT records for that domain.

The example below uses manually created Let's Encrypt certs.  This is not recommended for production unless you have setup an automated process to create and renew the certs.  These certs would expire after 90 days.

```sh
 git clone https://github.com/acmesh-official/acme.sh.git

 cd acme.sh/
chmod +x acme.sh

source ./aro4-env.sh

# Issue a new cert for domain api.aro.dockertutorial.technology
./acme.sh --issue --dns -d "api.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please

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

# Retrieve the API IP for Azure DNS records
az aro show -n $CLUSTER -g $RESOURCEGROUP --query 'apiserverProfile.ip'

# Set up Azure DNS records
# (You can use the IPs but it's probably better to use the alias records to the public IP resources in ase the IP address changes.)

* Create a `api` A record of type Alias to point to the API Load Balancer (`cluster-xxxxx-public-lb`) Public IP: `cluster-yyyyy-pip-v4`

# Add the _acme-challenge TXT record to api.<DOMAIN>
# Download the certs and key
./acme.sh --renew --dns -d "api.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key

# Issue a new cert for domain *.apps.<DOMAIN>
./acme.sh --issue --dns -d "*.apps.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please

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

# Retrieve the Ingress IP for Azure DNS records
az aro show -n $CLUSTER -g $RESOURCEGROUP --query 'ingressProfiles[0].ip'

# Set up Azure DNS records
# (You can use the IPs but it's probably better to use the alias records to the public IP resources in ase the IP address changes.)

* Create a `*.apps` A record of type Alias to point to the Ingress Load Balancer (`cluster-xxxxx`) Public IP: `cluster-yyyyy-xxxxxxxxxxxxxxxx` (not the outbound PIP)

# Add the _acme-challenge TXT record to apps.<DOMAIN>
# Download the certs and key
./acme.sh --renew --dns -d "*.apps.$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please --fullchain-file fullchain.cer --cert-file file.crt --key-file file.key

# Logic with `oc`

KUBEADMIN_PASSWD=$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER --query "kubeadminPassword" -o tsv)
API_URL=$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)
oc login -u kubeadmin -p $KUBEADMIN_PASSWD --server=$API_URL
oc status

# Note: you might need to wait for DNS propagation

# Configure cluster certs

cd ~/.acme.sh/api.$DOMAIN

# Add an API server named certificate
# See: https://docs.openshift.com/container-platform/4.4/security/certificates/api-server.html

oc create secret tls api-custom-domain \
     --cert=fullchain.cer \
     --key=api.$DOMAIN.key \
     -n openshift-config

oc patch apiserver cluster \
--type=merge -p \
'{"spec":{"servingCerts": {"namedCertificates":
[{"names": ["api.<DOMAIN>"],
"servingCertificate": {"name": "api-custom-domain"}}]}}}'

oc get apiserver cluster -o yaml


cd ~/.acme.sh/\*.apps.$DOMAIN/

# Replacing the default ingress certificate
# See: https://docs.openshift.com/container-platform/4.4/security/certificates/replacing-default-ingress-certificate.html

oc create configmap custom-ca \
     --from-file=ca-bundle.crt \
     -n openshift-config

oc patch proxy/cluster \
     --type=merge \
     --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'

oc create secret tls star-apps-custom-domain \
     --cert=fullchain.cer \
     --key="*.apps.$DOMAIN.key" \
     -n openshift-ingress

oc patch ingresscontroller.operator default \
     --type=merge -p \
     '{"spec":{"defaultCertificate": {"name": "star-apps-custom-domain"}}}' \
     -n openshift-ingress-operator
```
