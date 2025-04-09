variable "aks_cluster_name_prefix" {
  description = "Prefix for the AKS cluster name. A unique name will be generated."
  type        = string
  # Example: "bth-aks-demo"
}

variable "aks_resource_group_name" {
  description = "Name of the Resource Group to create for the AKS cluster."
  type        = string
  # Example: "bth-rg-demo"
}

variable "kubernetes_version" {
  description = "Desired Kubernetes version for the AKS cluster."
  type        = string
  # Example: "1.28.5" - Check available versions in your region
}

variable "node_pool_name" {
  description = "Name for the default AKS node pool."
  type        = string
  default     = "defaultpool"
}

variable "node_pool_vm_size" {
  description = "VM Size for the AKS nodes. Standard_DS2_v2 is recommended over B-series for performance."
  type        = string
  # Example: "Standard_DS2_v2", "Standard_B2s"
}

variable "node_pool_min_count" {
  description = "Minimum number of nodes for the default node pool."
  type        = number
  default     = 1
}

variable "node_pool_max_count" {
  description = "Maximum number of nodes for the default node pool (for autoscaling)."
  type        = number
  default     = 3
}

variable "enable_auto_scaling" {
  description = "Enable autoscaling for the default node pool."
  type        = bool
  default     = true
}

variable "storage_account_name" {
  description = "Name of the Azure Storage Account for persistent volumes."
  type        = string
}

variable "storage_account_resource_group_name" {
  description = "Resource group name for the Azure Storage Account."
  type        = string
}

variable "storage_container_name" {
  description = "Name of the Azure Blob Storage Container for persistent volumes."
  type        = string
  # Example: "otel-pvc-data"
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace for the deployment."
  type        = string
  # Example: "otel-demo"
}

variable "location" {
  description = "Azure region for all resources (AKS, Storage Account) (e.g., 'East US', 'West Europe')."
  type        = string
}

variable "nginx_ingress_chart_version" {
  description = "Version of the NGINX Ingress Controller Helm chart."
  type        = string
  # Example: "4.10.0"
} 