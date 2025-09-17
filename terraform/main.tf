# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# Create Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet-${random_id.suffix.hex}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

# Create Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "${var.cluster_name}-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

# Create Log Analytics Workspace for AKS monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.cluster_name}-law-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_retention_in_days

  tags = var.tags
}

# Create AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.cluster_name}-${random_id.suffix.hex}"
  kubernetes_version  = var.kubernetes_version

  # System node pool (for system workloads)
  default_node_pool {
    name           = "system"
    node_count     = 2
    vm_size        = "Standard_D2s_v3"
    type           = "VirtualMachineScaleSets"
    vnet_subnet_id = azurerm_subnet.aks.id
    max_pods       = 30

    # Only system workloads on this pool
    only_critical_addons_enabled = true

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
      "nodepoolos"    = "linux"
      "app"           = "system-apps"
    }

    tags = var.tags
  }

  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  # Enable monitoring
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Enable auto-scaling
  auto_scaler_profile {
    balance_similar_node_groups      = false
    expander                         = "random"
    max_graceful_termination_sec     = "600"
    max_unready_nodes                = 3
    max_unready_percentage           = 45
    new_pod_scale_up_delay           = "10s"
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scan_interval                    = "10s"
    scale_down_unneeded              = "10m"
    scale_down_unready               = "20m"
    scale_down_utilization_threshold = 0.5
  }

  tags = var.tags

  depends_on = [
    azurerm_subnet.aks,
    azurerm_log_analytics_workspace.main
  ]
}

# Create GPU Node Pool
resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.gpu_vm_size
  node_count            = var.gpu_node_count
  vnet_subnet_id        = azurerm_subnet.aks.id
  max_pods              = 30

  # Enable auto-scaling for GPU nodes
  auto_scaling_enabled = true
  min_count            = var.gpu_min_count
  max_count            = var.gpu_max_count

  # GPU-specific configuration
  node_labels = {
    "nodepool-type" = "gpu"
    "environment"   = var.environment
    "nodepoolos"    = "linux"
    "app"           = "gpu-apps"
    "accelerator"   = "nvidia"
    "gpu-type"      = replace(lower(var.gpu_vm_size), "_", "-")
  }

  # Taint GPU nodes so only GPU workloads are scheduled
  node_taints = [
    "nvidia.com/gpu=true:NoSchedule"
  ]

  tags = merge(var.tags, {
    "nodepool" = "gpu"
    "gpu"      = "nvidia"
  })

  depends_on = [azurerm_kubernetes_cluster.main]
}
