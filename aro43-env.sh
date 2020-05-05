#!/bin/bash

# Source this file into your shell
# $ source ./aro43.sh

export ARO_LOCATION=eastus # Choose your region
export ARO_CLUSTER=aro4cbx # Set your cluster name

export ARO_RESOURCEGROUP="aro-v4-${ARO_LOCATION}"
export ARO_VNET=aro4vnet
