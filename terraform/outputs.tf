# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# AKS Cluster Information
output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "cluster_endpoint" {
  description = "Endpoint for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config.0.host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate
  sensitive   = true
}

# Kubeconfig for connecting to the cluster
output "kube_config" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

# Network Information
output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

# GPU Node Pool Information
output "gpu_node_pool_name" {
  description = "Name of the GPU node pool"
  value       = azurerm_kubernetes_cluster_node_pool.gpu.name
}

output "gpu_vm_size" {
  description = "VM size used for GPU nodes"
  value       = azurerm_kubernetes_cluster_node_pool.gpu.vm_size
}

output "gpu_node_count" {
  description = "Current number of GPU nodes"
  value       = azurerm_kubernetes_cluster_node_pool.gpu.node_count
}

# Monitoring Information
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

# Connection Commands
output "get_credentials_command" {
  description = "Command to get AKS credentials"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "connect_instructions" {
  description = "Instructions for connecting to the cluster"
  value       = <<-EOT
To connect to your AKS cluster, run:

1. Get cluster credentials:
   az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}

2. Verify connection:
   kubectl get nodes

3. Check GPU nodes:
   kubectl get nodes -l accelerator=nvidia

4. Deploy GPU Operator:
   cd ../scripts && ./deploy-gpu-operator.sh
EOT
}
