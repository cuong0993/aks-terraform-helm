variable "kubernetes_version" {
  description = "The k8s version to deploy eg: '1.8.5', '1.10.5' etc"
  default     = "1.29.4"
}

variable "vm_size" {
  description = "The VM_SKU to use for the agents in the cluster"
  default     = "Standard_B2ms"
}

variable "node_count" {
  description = "The number of agents nodes to provision in the cluster"
  default     = "2"
}

variable "resource_group_name" {
  description = "Name of the azure resource group."
  default     = "cuond1"
}

variable "resource_group_location" {
  description = "Location of the azure resource group."
  default     = "westeurope"
}

variable "sp_name" {
  default = "aks-test-sp"
}
