#!/bin/bash

# AKS Installer Script

# Set speed, bold and color variables
SPEED=40 
bold=$(tput bold) 
normal=$(tput sgr0) 
color='\e[1;32m' # green 
nc='\e[0m'

export AKS_CONTEXT=aks-1
export ISTIO_VERSION=1.1.0-snapshot.6

# Create bin path
if ! ls $HOME/bin &> /dev/null ; then
    echo "${bold}Creating local ~/bin folder...${normal}"
    cd $HOME
    mkdir -p bin
    export PATH=$PATH:$HOME/bin/:$HOME/.local/bin/ 
else
    echo "${bold}Local bin folder already exists.${normal}" 
fi 
echo "********************************************************************************"

# Download Istio latest 
cd $HOME 
export ISTIO_VERSION=1.1.0-snapshot.6 
if ! ls $HOME/istio-$ISTIO_VERSION &> /dev/null ; 
then
    echo "${bold}Downloading Istio...${normal}"
    curl -L https://git.io/getLatestIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
    cd istio-$ISTIO_VERSION
    export PATH=$PATH:$HOME/istio-$ISTIO_VERSION/bin
    cp $HOME/istio-$ISTIO_VERSION/bin/istioctl $HOME/bin/.
    cd $HOME 
else
    echo "${bold}Istio version $ISTIO_VERSION already present.${normal}" 
fi 
echo "********************************************************************************"

# Install kubectx/kubens
if kubectx &> /dev/null ; then
    echo "${bold}kubectx/kubens already installed.${normal}" 
else
    echo "${bold}Installing kubectx for easy cluster context switching...${normal}"
    sudo git clone https://github.com/ahmetb/kubectx $HOME/kubectx
    sudo ln -s $HOME/kubectx/kubectx $HOME/bin/kubectx
    sudo ln -s $HOME/kubectx/kubens $HOME/bin/kubens 
fi 
echo "********************************************************************************"

# Install kubectl aliases
if ls $HOME/kubectl-aliases/ &> /dev/null ; then
    echo "${bold}kubectl-aliases already installed.${normal}" 
else
    echo "${bold}Installing kubectl_aliases...${normal}"
    cd $HOME
    git clone https://github.com/ahmetb/kubectl-aliases.git
    echo "[ -f ~/kubectl-aliases/.kubectl_aliases ] && source ~/kubectl-aliases/.kubectl_aliases" >> $HOME/.bashrc
    source ~/.bashrc 
fi 
echo "********************************************************************************"

# Install Helm
if helm &> /dev/null ; then
    echo "${bold}Helm already installed.${normal}" 
else
    echo "${bold}Installing helm...${normal}"
    curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
    chmod 700 get_helm.sh
    ./get_helm.sh &> /dev/null
    cp /usr/local/bin/helm $HOME/bin/ 
fi 
echo "********************************************************************************"

# Install terraform
if terraform version &> /dev/null ; then
    echo "${bold}Terraform already installed.${normal}" 
else
    echo "${bold}Installing terraform...${normal}"
    cd $HOME
    mkdir terraform11
    cd terraform11
    sudo apt-get install unzip
    wget https://releases.hashicorp.com/terraform/0.11.11/terraform_0.11.11_linux_amd64.zip
    unzip terraform_0.11.11_linux_amd64.zip
    mv terraform $HOME/bin/.
    cd $HOME
    rm -rf terraform11 
fi 
echo "********************************************************************************"

# Install latest kubectl 
KUBECTL_VER=$(kubectl version --client=true -o json | jq .clientVersion.gitVersion)
if ! KUBECTL_VER="\"v.13.3\"" ; then
    echo "${bold}Installing kubectl...${normal}"
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl 
    chmod +x kubectl 
    sudo mv kubectl /google/google-cloud-sdk/bin/. 
else
    echo "${bold}Kubectl already installed.${normal}"
fi
echo "********************************************************************************"

# Install krompt
if ! cat $HOME/.bashrc | grep K-PROMPT &> /dev/null ; then
    cd $HOME
    cat $HOME/terraform-eks/cluster/krompt.txt >> $HOME/.bashrc
    source $HOME/.bashrc 
fi 

# Install az CLI
if ! az --version &> /dev/null ; then
    echo "${bold}Installing az cli...${normal}"
    sudo apt-get install apt-transport-https lsb-release software-properties-common dirmngr -y
    AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-key --keyring /etc/apt/trusted.gpg.d/Microsoft.gpg adv \
        --keyserver packages.microsoft.com \
        --recv-keys BC528686B50D79E339D3721CEB3E94ADBE1229CF
    sudo apt-get update
    sudo apt-get install azure-cli 
else
    echo "${bold}AZ CLI is already installed${normal}"
fi 
echo "********************************************************************************"

# Terraform
echo "${bold}Terraforming AKS...${normal}"
cd $HOME/csp/aks/terraform-aks
terraform init
terraform plan -out out.plan
terraform apply out.plan
echo "********************************************************************************"

# Add kubeconfig
echo "${bold}Creating kubeconfig...${normal}"
echo "$(terraform output kube_config)" > ./azurek8s
if ls $HOME/.kube/config &> /dev/null ; then
    KUBECONFIG=~/.kube/config:./azurek8s kubectl config view --flatten > mergedkub && mv mergedkub ~/.kube/config
else
    cp ./azurek8s ~/.kube/config
fi
echo "********************************************************************************"

# Prep for Istio
echo "${bold}Installing Istio version $ISTIO_VERSION...${normal}" 
cd $HOME/istio-$ISTIO_VERSION

echo "${bold}Creating tiller service account and init...${normal}" 
kubectx $AKS_CONTEXT
kubectl apply -f $HOME/istio-$ISTIO_VERSION/install/kubernetes/helm/helm-service-account.yaml
helm init --service-account tiller
kubectl apply -f $HOME/csp/aks/terraform-aks/cluster-admin-role.yml

echo "${bold}Waiting for tiller...${normal}" 
until timeout 10 helm version; do sleep 10; done

echo "${bold}Updating Helm dependencies for Istio version $ISTIO_VERSION...${normal}" 
helm repo add istio.io "https://gcsweb.istio.io/gcs/istio-prerelease/daily-build/release-1.1-latest-daily/charts/" 
helm dep update $HOME/istio-$ISTIO_VERSION/install/kubernetes/helm/istio

echo "${bold}Installing istio-init chart to bootstrap Istio CRDs...${normal}" 
helm install $HOME/istio-$ISTIO_VERSION/install/kubernetes/helm/istio-init --name istio-init --namespace istio-system

echo "${bold}Ensure all CRDs were committed...${normal}" 
CRDS=$(kubectl get crds | grep 'istio.io\|certmanager.k8s.io' | wc -l) 
until [ $CRDS = "56" ]; do
    echo "Committing CRDS..."
    sleep 10
    CRDS=$(kubectl get crds | grep 'istio.io\|certmanager.k8s.io' | wc -l) 
done
echo "${bold}$CRDS CRDs committed.${normal}"

# Install Istio
echo "${bold}Installing Istio...${normal}"
helm install $HOME/istio-$ISTIO_VERSION/install/kubernetes/helm/istio --name istio --namespace istio-system \
  --set global.controlPlaneSecurityEnabled=true \
  --set grafana.enabled=true \
  --set tracing.enabled=true \
  --set kiali.enabled=true
echo "********************************************************************************"
