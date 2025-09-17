# General Configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "aks-gpu-rg"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "aks-gpu-terraform"
    ManagedBy   = "terraform"
    Purpose     = "gpu-ml-workloads"
  }
}

# AKS Configuration
variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-gpu-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.28.3"
}

# GPU Node Pool Configuration
variable "gpu_vm_size" {
  description = "VM size for GPU nodes (must be a GPU-enabled SKU)"
  type        = string
  default     = "Standard_NC6s_v3"

  validation {
    condition     = can(regex("^Standard_(NC|ND|NV)", var.gpu_vm_size))
    error_message = "GPU VM size must be a GPU-enabled SKU (NC, ND, or NV series)."
  }
}

variable "gpu_architecture" {
  description = "GPU architecture for optimized configuration (kepler, maxwell, pascal, volta, turing, ampere, hopper)"
  type        = string
  default     = "volta" # Tesla V100 for Standard_NC6s_v3

  validation {
    condition     = contains(["kepler", "maxwell", "pascal", "volta", "turing", "ampere", "hopper", "auto"], var.gpu_architecture)
    error_message = "GPU architecture must be one of: kepler, maxwell, pascal, volta, turing, ampere, hopper, auto."
  }
}

variable "gpu_node_count" {
  description = "Initial number of GPU nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_node_count >= 0 && var.gpu_node_count <= 10
    error_message = "GPU node count must be between 0 and 10."
  }
}

variable "gpu_min_count" {
  description = "Minimum number of GPU nodes for auto-scaling"
  type        = number
  default     = 0

  validation {
    condition     = var.gpu_min_count >= 0 && var.gpu_min_count <= 100
    error_message = "GPU minimum count must be between 0 and 100."
  }
}

variable "gpu_max_count" {
  description = "Maximum number of GPU nodes for auto-scaling"
  type        = number
  default     = 3

  validation {
    condition     = var.gpu_max_count >= 1 && var.gpu_max_count <= 100
    error_message = "GPU maximum count must be between 1 and 100."
  }
}

# Networking Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for the AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Monitoring Configuration
variable "log_analytics_workspace_sku" {
  description = "SKU for Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_retention_in_days" {
  description = "Log retention in days for Log Analytics Workspace"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_in_days >= 30 && var.log_retention_in_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}
