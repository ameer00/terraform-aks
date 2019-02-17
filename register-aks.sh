#!/bin/bash

# Set speed, bold and color variables
SPEED=40
bold=$(tput bold)
normal=$(tput sgr0)
color='\e[1;32m' # green
nc='\e[0m'

# Define variables
echo "${bold}Define variables...${normal}"
export PROJECT_ID=$(gcloud config get-value project)
export GKE_CONNECT_SA=gke-connect-sa
export USER=$(gcloud config list account --format "value(core.account)")
export LOCAL_KEY_PATH="$HOME/csp/aks/creds/$GKE_CONNECT_SA.json"
export KSA=aks-admin-sa
export AKS_CONTEXT=aks-1
export DESIRED_IMAGE="gcr.io/gkeconnect/gkeconnect-gce:gkeconnect_20190213_00_03-aks"
echo "********************************************************************************"

# Install gcloud alpha update
ALPHA_CHECK=$(gcloud alpha container cluster-registrations list --location=us-central1 --format=json)
if ! [ "$ALPHA_CHECK" ] ; then 
    echo "${bold}Installing gcloud alpha components for cluster registration...${normal}"
    sudo gcloud components repositories add \
        https://storage.googleapis.com/gkehub-gcloud-dist-tt/components-2.json
    sudo gcloud components update --quiet
else
    echo "${bold}Gcloud alpha components already installed.${normal}"
fi
echo "********************************************************************************"

# Create cluster role admin binding
if ! kubectl get clusterrolebinding user-cluster-admin &> /dev/null ; then
    echo "${bold}Create cluster role admin binding...${normal}"
    kubectl create clusterrolebinding user-cluster-admin \
    --clusterrole cluster-admin --user $USER --context $AKS_CONTEXT
else
    echo "${bold}Admin cluster role already exists.${normal}"
fi
echo "********************************************************************************"

# Add IAM permissions
echo "${bold}Add IAM permissions...${normal}"
gcloud projects add-iam-policy-binding $PROJECT_ID --member user:$USER --role roles/owner
# gcloud projects add-iam-policy-binding $PROJECT_ID --member user:$USER \
# --role roles/clusterregistry.admin --role roles/iam.serviceAccountAdmin \
# --role roles/iam.serviceAccountKeyAdmin --role roles/resourcemanager.projectIamAdmin
echo "********************************************************************************"

# Enable APIs
REGISTRY_API=$(gcloud services list --filter=clusterregistry.googleapis.com --format=json | jq -r .[].config.name)
CONTAINER_API=$(gcloud services list --filter=container.googleapis.com --format=json | jq -r .[].config.name)
if [ "$REGISTRY_API" != "clusterregistry.googleapis.com" -o "$CONTAINER_API" != "container.googleapis.com" ] ; then
    echo "${bold}Enable APIs...${normal}"
    gcloud services enable container.googleapis.com clusterregistry.googleapis.com 
else
    echo "${bold}Required APIs already enabled.${normal}"
fi
echo "********************************************************************************"

# Create Service Account for the GKE Connect Agent
SA_EXISTS=$(gcloud iam service-accounts list --format=json | jq -r .[].email | grep gke-connect-sa)
if [ -z $SA_EXISTS ]; then
    echo "${bold}Create Service Account for the GKE Connect Agent...${normal}"
    gcloud iam service-accounts create $GKE_CONNECT_SA --project=$PROJECT_ID
    gcloud projects add-iam-policy-binding \
        $PROJECT_ID \
        --member="serviceAccount:$GKE_CONNECT_SA@$PROJECT_ID.iam.gserviceaccount.com" \
        --role="roles/clusterregistry.connect"
else
    echo "${bold}$SA_EXISTS Service Account already exists.${normal}"
fi
echo "********************************************************************************"

# Download the Service Account JSON key
if ! [ -z $LOCAL_KEY_PATH ]; then
    echo "${bold}Download the Service Account JSON key...${normal}"
    gcloud iam service-accounts keys create $LOCAL_KEY_PATH --iam-account=$GKE_CONNECT_SA@$PROJECT_ID.iam.gserviceaccount.com --project=$PROJECT_ID
else
    echo "${bold}Service Account JSON Key already exists.${normal}"
fi
echo "********************************************************************************"

# Register the cluster
AKS_REGISTERED=$(gcloud alpha container cluster-registrations list --location=us-central1 --format=json | jq -r .[].metadata.name)
if ! [ "$AKS_REGISTERED" == "$AKS_CONTEXT" ]; then
    echo "${bold}Registering the cluster...${normal}"
    gcloud alpha container cluster-registrations create $AKS_CONTEXT --quiet \
        --from-kubeconfig=$HOME/.kube/config \
        --context=$AKS_CONTEXT \
        --service-account-key-file=$LOCAL_KEY_PATH \
        --location=us-central1 \
        --project=$PROJECT_ID
else
    echo "${bold}Cluster $AKS_REGISTERED is already registered.${normal}"
fi
echo "********************************************************************************"

# Update the gke-connect-agent deployment image
CURRENT_IMAGE=$(kubectl get deploy gke-connect-agent -n gke-connect-ameer-csp1-aks-1 -ojson | jq -r .spec.template.spec.containers[].image)
if ! [ "$CURRENT_IMAGE" == "$DESIRED_IMAGE" ]; then
    kubectl set image deployment/gke-connect-agent -n gke-connect-ameer-csp1-aks-1 gke-connect-agent=$DESIRED_IMAGE --context $AKS_CONTEXT
    echo "${bold}Now running the desired gke-connect agent image.${normal}"
else
    echo "${bold}Already running the desired gke-connect agent image.${normal}"
fi

# Create a Kubernetes Service Account for authenticating to the API Server
KSA_EXISTS=$(kubectl get serviceaccounts aks-admin-sa --context $AKS_CONTEXT -ojson | jq -r .metadata.name)
if ! [ "$KSA_EXISTS" == "$KSA" ] ; then
    echo "${bold}Creating a Kubernetes Service Account for authenticating to the API Server...${normal}"
    kubectl create serviceaccount $KSA --context $AKS_CONTEXT
else:
    echo "${bold}$KSA_EXISTS already exists in $AKS_CONTEXT cluster.${normal}"
fi
echo "********************************************************************************"

# Give the Kubernetes Service Account view role
if ! kubectl get clusterrolebinding aks-admin-sa-binding &> /dev/null ; then
    echo "${bold}Give the Kubernetes Service Account cluster-admin role...${normal}"
    kubectl create clusterrolebinding $KSA-binding \
    --clusterrole cluster-admin --serviceaccount default:$KSA --context $AKS_CONTEXT
else
    echo "${bold}$KSA already has cluster admin rights.${normal}"
fi
echo "********************************************************************************"

# Get the secret Token for authenticating
echo "${bold}Get the secret Token for authenticating...${normal}"
kubectl --kubeconfig $HOME/.kube/config describe secret \
-n default --context $AKS_CONTEXT \
$(kubectl --kubeconfig $HOME/.kube/config get secrets -n default | grep "^$KSA" | cut -f1 -d ' ') | grep -E "^token" $1 | cut -f2 -d ':' | tr -d " "
echo "********************************************************************************"

