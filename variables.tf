variable "client_id" {}
variable "client_secret" {}

variable "agent_count" {
    default = 4
}

variable "ssh_public_key" {
    default = "~/.ssh/id_rsa.pub"
}

variable "dns_prefix" {
    default = "aks-1"
}

variable cluster_name {
    default = "aks-1"
}

variable kubernetes_version {
    default = "1.11.7"
}

variable resource_group_name {
    default = "aksrg"
}

variable location {
    default = "East US"
}

variable log_analytics_workspace_name {
    default = "aks1LogAnalyticsWorkspaceName"
}

# refer https://azure.microsoft.com/global-infrastructure/services/?products=monitor for log analytics available regions
variable log_analytics_workspace_location {
    default = "eastus"
}

# refer https://azure.microsoft.com/pricing/details/monitor/ for log analytics pricing 
variable log_analytics_workspace_sku {
    default = "PerGB2018"
}
