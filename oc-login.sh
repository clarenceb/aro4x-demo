#!/bin/bash

source ./aro4-env.sh

KUBEADMIN_PASSWD="$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER --query kubeadminPassword -o tsv)"
API_URL="$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query apiserverProfile.url -o tsv)"
CONSOLE_URL="$(az aro show -g $RESOURCEGROUP -n $CLUSTER --query consoleProfile.url -o tsv)"

oc login -u kubeadmin -p $KUBEADMIN_PASSWD --server=$API_URL

echo "Browse to: $CONSOLE_URL"
