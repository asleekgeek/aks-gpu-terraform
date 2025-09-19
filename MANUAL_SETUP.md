# Manual Setup Guide: AKS with GPU Time-Slicing

This guide provides step-by-step instructions for manually setting up an Azure Kubernetes Service (AKS) cluster with GPU time-slicing **without using Terraform**. This is perfect for learning the process, troubleshooting, or environments where Infrastructure as Code isn't preferred.

## 📑 Table of Contents

- [Manual Setup Guide: AKS with GPU Time-Slicing](#manual-setup-guide-aks-with-gpu-time-slicing)
  - [📑 Table of Contents](#-table-of-contents)
  - [🎯 Overview](#-overview)
  - [📋 Prerequisites](#-prerequisites)
    - [Required Tools](#required-tools)
    - [Azure Authentication](#azure-authentication)
    - [Check GPU Quota](#check-gpu-quota)
  - [🏗️ Step 1: Prepare Azure Infrastructure](#️-step-1-prepare-azure-infrastructure)
    - [1.1 Create Resource Group](#11-create-resource-group)
    - [1.2 Create Virtual Network (Optional but Recommended)](#12-create-virtual-network-optional-but-recommended)
    - [1.3 Create Log Analytics Workspace (Optional but Recommended)](#13-create-log-analytics-workspace-optional-but-recommended)
  - [🚀 Step 2: Create AKS Cluster](#-step-2-create-aks-cluster)
    - [2.1 Create AKS Cluster with System Node Pool](#21-create-aks-cluster-with-system-node-pool)
    - [2.2 Get Cluster Credentials](#22-get-cluster-credentials)
  - [🎮 Step 3: Add GPU Node Pool](#-step-3-add-gpu-node-pool)
    - [3.1 Create GPU Node Pool](#31-create-gpu-node-pool)
    - [3.2 Verify GPU Nodes](#32-verify-gpu-nodes)
  - [🔧 Step 4: Install NVIDIA GPU Operator](#-step-4-install-nvidia-gpu-operator)
    - [4.1 Add NVIDIA Helm Repository](#41-add-nvidia-helm-repository)
    - [4.2 Create GPU Operator Namespace](#42-create-gpu-operator-namespace)
    - [4.3 Install GPU Operator](#43-install-gpu-operator)
    - [4.4 Verify GPU Operator Installation](#44-verify-gpu-operator-installation)
  - [⚡ Step 5: Configure GPU Time-Slicing](#-step-5-configure-gpu-time-slicing)
    - [5.1 Create Time-Slicing Configuration](#51-create-time-slicing-configuration)
    - [5.2 Apply Time-Slicing to Cluster Policy](#52-apply-time-slicing-to-cluster-policy)
    - [5.3 Restart Device Plugin to Apply Configuration](#53-restart-device-plugin-to-apply-configuration)
  - [🧪 Step 6: Test GPU Time-Slicing](#-step-6-test-gpu-time-slicing)
    - [6.1 Verify GPU Resources After Time-Slicing](#61-verify-gpu-resources-after-time-slicing)
    - [6.2 Deploy Test GPU Workload](#62-deploy-test-gpu-workload)
    - [6.3 Test Multiple GPU Workloads (Time-Slicing)](#63-test-multiple-gpu-workloads-time-slicing)
  - [📊 Step 7: Monitor and Validate](#-step-7-monitor-and-validate)
    - [7.1 Check GPU Utilization](#71-check-gpu-utilization)
    - [7.2 View Time-Slicing Configuration](#72-view-time-slicing-configuration)
  - [📊 Step 8: GPU Monitoring Setup (Recommended)](#-step-8-gpu-monitoring-setup-recommended)
    - [8.1 Install Prometheus](#81-install-prometheus)
    - [8.2 Configure DCGM ServiceMonitor](#82-configure-dcgm-servicemonitor)
    - [8.3 Install GPU Dashboard](#83-install-gpu-dashboard)
    - [8.4 Configure GPU Alerts](#84-configure-gpu-alerts)
    - [8.5 Access Monitoring Dashboards](#85-access-monitoring-dashboards)
    - [8.6 Verify Monitoring Setup](#86-verify-monitoring-setup)
  - [🧹 Step 9: Cleanup (Optional)](#-step-9-cleanup-optional)
    - [9.1 Remove Test Workloads](#91-remove-test-workloads)
    - [9.2 Scale Down GPU Nodes (Cost Saving)](#92-scale-down-gpu-nodes-cost-saving)
    - [9.3 Complete Cleanup](#93-complete-cleanup)
  - [🎯 Key Differences from Terraform Approach](#-key-differences-from-terraform-approach)
  - [🔧 Troubleshooting Common Issues](#-troubleshooting-common-issues)
    - [GPU Nodes Not Ready](#gpu-nodes-not-ready)
    - [Device Plugin Issues](#device-plugin-issues)
    - [Time-Slicing Not Working](#time-slicing-not-working)
  - [🎉 Success Criteria](#-success-criteria)
- [🧹 10. Manual Teardown and Cleanup](#-10-manual-teardown-and-cleanup)
    - [10.1 Quick Cleanup Commands](#101-quick-cleanup-commands)
    - [10.2 Step-by-Step Manual Teardown](#102-step-by-step-manual-teardown)
      - [Step 1: Remove GPU Workloads](#step-1-remove-gpu-workloads)
      - [Step 2: Uninstall NVIDIA GPU Operator](#step-2-uninstall-nvidia-gpu-operator)
      - [Step 3: Delete Azure Kubernetes Service](#step-3-delete-azure-kubernetes-service)
      - [Step 4: Delete Supporting Azure Resources](#step-4-delete-supporting-azure-resources)
      - [Step 5: Delete Resource Group (Complete Cleanup)](#step-5-delete-resource-group-complete-cleanup)
    - [10.3 Clean Up Local Configuration](#103-clean-up-local-configuration)
    - [10.4 Verification and Cost Monitoring](#104-verification-and-cost-monitoring)
    - [10.5 Automated Cleanup Script](#105-automated-cleanup-script)
    - [10.6 Cost Monitoring Best Practices](#106-cost-monitoring-best-practices)
    - [💰 Cost Impact Summary](#-cost-impact-summary)
  - [�📚 Next Steps](#-next-steps)

## 🎯 Overview

You'll manually create:

1.  Azure Resource Group and networking
2.  AKS cluster with system node pool
3.  GPU-enabled node pool
4.  NVIDIA GPU Operator installation
5.  GPU time-slicing configuration

## 📋 Prerequisites

Ensure you have the following tools installed and configured:

### Required Tools

```bash
# Azure CLI (v2.0+)
az --version

# kubectl (v1.25+)
kubectl version --client

# Helm (v3.0+)
helm version
```

### Azure Authentication

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Verify your account
az account show
```

### Check GPU Quota

```bash
# Check your GPU quota (example for East US)
az vm list-usage --location "East US" --query "[?contains(name.value, 'StandardNC')]" --output table

# If quota is 0, request increase through Azure Portal:
# Portal > Subscriptions > Usage + quotas > Compute > Request increase
```

## 🏗️ Step 1: Prepare Azure Infrastructure

### 1.1 Create Resource Group

```bash
# Set variables for consistency
RESOURCE_GROUP="aks-gpu-manual-rg"
LOCATION="East US"
CLUSTER_NAME="aks-gpu-manual"

# Create resource group
az group create \
    --name $RESOURCE_GROUP \
    --location "$LOCATION"
```

### 1.2 Create Virtual Network (Optional but Recommended)

```bash
# Create VNet for better network control
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name ${CLUSTER_NAME}-vnet \
    --address-prefixes 10.0.0.0/16 \
    --subnet-name ${CLUSTER_NAME}-subnet \
    --subnet-prefixes 10.0.1.0/24

# Get subnet ID for later use
SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name ${CLUSTER_NAME}-vnet \
    --name ${CLUSTER_NAME}-subnet \
    --query id -o tsv)

echo "Subnet ID: $SUBNET_ID"
```

### 1.3 Create Log Analytics Workspace (Optional but Recommended)

```bash
# Create Log Analytics workspace for monitoring
az monitor log-analytics workspace create \
    --resource-group $RESOURCE_GROUP \
    --workspace-name ${CLUSTER_NAME}-logs \
    --location "$LOCATION"

# Get workspace ID for later use
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name ${CLUSTER_NAME}-logs \
    --query id -o tsv)

echo "Workspace ID: $WORKSPACE_ID"
```

## 🚀 Step 2: Create AKS Cluster

### 2.1 Create AKS Cluster with System Node Pool

```bash
# Create AKS cluster (this will take 5-10 minutes)
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location "$LOCATION" \
    --kubernetes-version "1.28.3" \
    --node-count 2 \
    --node-vm-size "Standard_D2s_v3" \
    --vnet-subnet-id "$SUBNET_ID" \
    --enable-addons monitoring \
    --workspace-resource-id "$WORKSPACE_ID" \
    --enable-managed-identity \
    --generate-ssh-keys \
    --only-show-errors

echo "✅ AKS cluster created successfully!"
```

### 2.2 Get Cluster Credentials

```bash
# Get credentials to connect to the cluster
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --overwrite-existing

# Verify connection
kubectl get nodes
kubectl cluster-info
```

## 🎮 Step 3: Add GPU Node Pool

### 3.1 Create GPU Node Pool

```bash
# Add GPU node pool to the cluster
az aks nodepool add \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $CLUSTER_NAME \
    --name gpu \
    --node-count 1 \
    --node-vm-size "Standard_NC6s_v3" \
    --vnet-subnet-id "$SUBNET_ID" \
    --enable-cluster-autoscaler \
    --min-count 0 \
    --max-count 3 \
    --node-taints "nvidia.com/gpu=true:NoSchedule" \
    --labels accelerator=nvidia,gpu-type=tesla-v100,nodepool-type=gpu

echo "✅ GPU node pool created successfully!"
```

### 3.2 Verify GPU Nodes

```bash
# Wait for GPU nodes to be ready (may take 3-5 minutes)
echo "Waiting for GPU nodes to be ready..."
kubectl wait --for=condition=Ready nodes -l accelerator=nvidia --timeout=600s

# Verify GPU nodes
kubectl get nodes -l accelerator=nvidia
kubectl describe nodes -l accelerator=nvidia | grep -E "Name:|nvidia.com/gpu"
```

## 🔧 Step 4: Install NVIDIA GPU Operator

### 4.1 Add NVIDIA Helm Repository

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Verify repository
helm search repo nvidia/gpu-operator
```

### 4.2 Create GPU Operator Namespace

```bash
# Create namespace
kubectl create namespace gpu-operator-resources

# Verify namespace
kubectl get namespaces | grep gpu-operator
```

### 4.3 Install GPU Operator

```bash
# Install GPU Operator with optimized settings
helm install gpu-operator nvidia/gpu-operator \
    --namespace gpu-operator-resources \
    --set operator.defaultRuntime=containerd \
    --set driver.enabled=true \
    --set toolkit.enabled=true \
    --set devicePlugin.enabled=true \
    --set dcgm.enabled=true \
    --set dcgmExporter.enabled=true \
    --set nodeStatusExporter.enabled=true \
    --set migManager.enabled=false \
    --set devicePlugin.config.name=time-slicing-config \
    --set devicePlugin.config.default=any \
    --wait \
    --timeout=600s

echo "✅ GPU Operator installed successfully!"
```

### 4.4 Verify GPU Operator Installation

```bash
# Check GPU Operator pods
kubectl get pods -n gpu-operator-resources

# Wait for all pods to be running
echo "Waiting for GPU Operator pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=gpu-operator \
    -n gpu-operator-resources \
    --timeout=300s

# Verify GPU resources are available
kubectl describe nodes -l accelerator=nvidia | grep -A 10 -B 5 nvidia.com/gpu
```

## ⚡ Step 5: Configure GPU Time-Slicing

### 5.1 Create Time-Slicing Configuration

```bash
# Create time-slicing configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator-resources
data:
  any: |
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 4
        failRequestsGreaterThanOne: true
  
  volta: |
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 6
        failRequestsGreaterThanOne: true
  
  ampere: |
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 8
        failRequestsGreaterThanOne: true
EOF

echo "✅ Time-slicing configuration created!"
```

### 5.2 Apply Time-Slicing to Cluster Policy

```bash
# Patch the ClusterPolicy to enable time-slicing
kubectl patch clusterpolicy cluster-policy --type='merge' -p='
{
  "spec": {
    "devicePlugin": {
      "config": {
        "name": "time-slicing-config",
        "default": "any"
      }
    },
    "mig": {
      "strategy": "none"
    }
  }
}'

echo "✅ ClusterPolicy updated for time-slicing!"
```

### 5.3 Restart Device Plugin to Apply Configuration

```bash
# Delete device plugin pods to restart with new config
kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset

# Wait for device plugin to restart
echo "Waiting for device plugin to restart..."
sleep 20
kubectl wait --for=condition=ready pod \
    -l app=nvidia-device-plugin-daemonset \
    -n gpu-operator-resources \
    --timeout=300s

echo "✅ Device plugin restarted with time-slicing!"
```

## 🧪 Step 6: Test GPU Time-Slicing

### 6.1 Verify GPU Resources After Time-Slicing

```bash
# Check GPU resources (should show 4 GPUs per physical GPU)
kubectl describe nodes -l accelerator=nvidia | grep -E "nvidia.com/gpu.*[0-9]"

# Get detailed GPU information
kubectl get nodes -l accelerator=nvidia -o json | jq '.items[].status.allocatable."nvidia.com/gpu"'
```

### 6.2 Deploy Test GPU Workload

```bash
# Create a simple GPU test job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-test-manual
spec:
  template:
    spec:
      restartPolicy: Never
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
      nodeSelector:
        accelerator: nvidia
      containers:
        - name: gpu-test
          image: nvidia/cuda:12.2-runtime-ubuntu20.04
          command: ["nvidia-smi"]
          resources:
            requests:
              nvidia.com/gpu: 1
            limits:
              nvidia.com/gpu: 1
EOF

# Wait for job to complete
kubectl wait --for=condition=complete job/gpu-test-manual --timeout=180s

# Check job output
kubectl logs job/gpu-test-manual

echo "✅ GPU test completed!"
```

### 6.3 Test Multiple GPU Workloads (Time-Slicing)

```bash
# Deploy multiple GPU workloads to test time-slicing
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-gpu-test
spec:
  replicas: 3  # More than physical GPUs to test time-slicing
  selector:
    matchLabels:
      app: multi-gpu-test
  template:
    metadata:
      labels:
        app: multi-gpu-test
    spec:
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
      nodeSelector:
        accelerator: nvidia
      containers:
        - name: gpu-worker
          image: nvidia/cuda:12.2-runtime-ubuntu20.04
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "GPU Worker \$HOSTNAME starting..."
              nvidia-smi -L
              echo "Running for 60 seconds..."
              sleep 60
              echo "GPU Worker \$HOSTNAME completed"
          resources:
            requests:
              nvidia.com/gpu: 1
            limits:
              nvidia.com/gpu: 1
EOF

# Check if multiple pods are running on the same GPU
echo "Checking multi-GPU deployment..."
kubectl get pods -l app=multi-gpu-test -o wide
kubectl describe pods -l app=multi-gpu-test | grep -E "Node:|nvidia.com/gpu"

echo "✅ Time-slicing test deployed!"
```

## 📊 Step 7: Monitor and Validate

### 7.1 Check GPU Utilization

```bash
# Monitor GPU resources
kubectl top nodes

# Check GPU Operator status
kubectl get pods -n gpu-operator-resources

# View DCGM metrics (if monitoring is set up)
kubectl port-forward -n gpu-operator-resources svc/dcgm-exporter 9400:9400 &
curl http://localhost:9400/metrics | grep DCGM
```

### 7.2 View Time-Slicing Configuration

```bash
# Check current time-slicing config
kubectl get configmap time-slicing-config -n gpu-operator-resources -o yaml

# Check ClusterPolicy
kubectl get clusterpolicy cluster-policy -o yaml | grep -A 10 devicePlugin
```

## 📊 Step 8: GPU Monitoring Setup (Recommended)

Set up comprehensive GPU monitoring with Prometheus and Grafana to track GPU utilization, time-slicing effectiveness, and performance metrics.

### 8.1 Install Prometheus

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install Prometheus with GPU-specific configuration
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set grafana.adminPassword=admin123 \
    --set prometheus.prometheusSpec.retention=7d \
    --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi

echo "✅ Prometheus installed"
```

### 8.2 Configure DCGM ServiceMonitor

```bash
# Create ServiceMonitor for DCGM metrics
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dcgm-exporter
  namespace: monitoring
  labels:
    app: dcgm-exporter
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  namespaceSelector:
    matchNames:
    - gpu-operator-resources
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF

echo "✅ DCGM ServiceMonitor configured"
```

### 8.3 Install GPU Dashboard

```bash
# Create GPU monitoring dashboard
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: gpu-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  gpu-dashboard.json: |
    {
      "dashboard": {
        "id": null,
        "title": "GPU Time-Slicing Monitoring",
        "tags": ["gpu", "nvidia", "kubernetes"],
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "GPU Utilization %",
            "type": "stat",
            "targets": [
              {
                "expr": "avg(DCGM_FI_DEV_GPU_UTIL)",
                "legendFormat": "GPU Utilization"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "GPU Memory Usage",
            "type": "stat",
            "targets": [
              {
                "expr": "avg(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL * 100)",
                "legendFormat": "Memory %"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
          },
          {
            "id": 3,
            "title": "GPU Temperature",
            "type": "graph",
            "targets": [
              {
                "expr": "DCGM_FI_DEV_GPU_TEMP",
                "legendFormat": "Temperature °C"
              }
            ],
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
          }
        ],
        "time": {
          "from": "now-1h",
          "to": "now"
        },
        "refresh": "30s"
      }
    }
EOF

echo "✅ GPU dashboard created"
```

### 8.4 Configure GPU Alerts

```bash
# Create GPU alerting rules
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
  namespace: monitoring
  labels:
    app: kube-prometheus-stack
    release: prometheus
spec:
  groups:
  - name: gpu.rules
    rules:
    - alert: GPUHighUtilization
      expr: avg(DCGM_FI_DEV_GPU_UTIL) > 90
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High GPU utilization detected"
        description: "GPU utilization is above 90% for more than 5 minutes"
    
    - alert: GPUHighTemperature
      expr: max(DCGM_FI_DEV_GPU_TEMP) > 80
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "GPU temperature too high"
        description: "GPU temperature is above 80°C"
    
    - alert: GPUMemoryHigh
      expr: avg(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL * 100) > 85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High GPU memory usage"
        description: "GPU memory usage is above 85%"
EOF

echo "✅ GPU alerts configured"
```

### 8.5 Access Monitoring Dashboards

```bash
# Get Grafana admin password
echo "Grafana Password: admin123"

# Port forward to access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
echo "🎯 Grafana: http://localhost:3000 (admin/admin123)"

# Port forward to access Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
echo "🎯 Prometheus: http://localhost:9090"

# Wait for ports to be ready
sleep 5
echo "✅ Monitoring dashboards ready!"
```

### 8.6 Verify Monitoring Setup

```bash
# Check if DCGM metrics are being collected
echo "🔍 Checking DCGM metrics availability..."
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
sleep 3

# Test if GPU metrics are available (requires curl)
if command -v curl >/dev/null 2>&1; then
    METRICS_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL" | grep -o '"status":"success"' | wc -l)
    if [ "$METRICS_COUNT" -gt 0 ]; then
        echo "✅ GPU metrics are being collected successfully"
    else
        echo "⚠️  GPU metrics not yet available - they may take a few minutes to appear"
    fi
else
    echo "ℹ️  Install curl to test metrics availability, or check Grafana dashboard"
fi

# Show ServiceMonitor status
kubectl get servicemonitor -n monitoring dcgm-exporter -o wide

# Show dashboard and alerts status
kubectl get configmap -n monitoring gpu-dashboard
kubectl get prometheusrule -n monitoring gpu-alerts

echo "🎉 Monitoring setup complete!"
echo ""
echo "📊 Next steps:"
echo "1. Open Grafana at http://localhost:3000"
echo "2. Import the GPU dashboard"
echo "3. Check Prometheus targets at http://localhost:9090/targets"
echo "4. Deploy GPU workloads to see metrics in action"
```

## 🧹 Step 9: Cleanup (Optional)

### 9.1 Remove Test Workloads

```bash
# Clean up test workloads
kubectl delete job gpu-test-manual
kubectl delete deployment multi-gpu-test
```

### 9.2 Scale Down GPU Nodes (Cost Saving)

```bash
# Scale GPU node pool to 0 when not in use
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $CLUSTER_NAME \
    --name gpu \
    --node-count 0

# Scale back up when needed
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $CLUSTER_NAME \
    --name gpu \
    --node-count 1
```

### 9.3 Complete Cleanup

```bash
# Delete entire resource group (if no longer needed)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## 🎯 Key Differences from Terraform Approach

| Aspect              | Manual Setup                   | Terraform                        |
| ------------------- | ------------------------------ | -------------------------------- |
| **Setup Time**      | 30-45 minutes                  | 15-20 minutes                    |
| **Learning Value**  | High - understand each step    | Medium - focus on config         |
| **Reproducibility** | Manual process each time       | Automated and consistent         |
| **Customization**   | Full control over each command | Template-based with variables    |
| **Error Handling**  | Manual troubleshooting         | Built-in validation and rollback |
| **Documentation**   | Step-by-step commands          | Infrastructure as Code           |

## 🔧 Troubleshooting Common Issues

### GPU Nodes Not Ready

```bash
# Check node status
kubectl describe nodes -l accelerator=nvidia

# Check GPU Operator logs
kubectl logs -n gpu-operator-resources -l app=gpu-operator
```

### Device Plugin Issues

```bash
# Check device plugin logs
kubectl logs -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset

# Restart device plugin
kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset
```

### Time-Slicing Not Working

```bash
# Verify configuration
kubectl get configmap time-slicing-config -n gpu-operator-resources -o yaml

# Check ClusterPolicy
kubectl describe clusterpolicy cluster-policy
```

## 🎉 Success Criteria

You'll know the setup is successful when:

-   ✅ GPU nodes show as Ready
-   ✅ `nvidia.com/gpu` resources are available (multiplied by time-slicing factor)
-   ✅ Multiple GPU workloads can run simultaneously on the same physical GPU
-   ✅ GPU Operator pods are all running
-   ✅ Test workloads complete successfully

# 🧹 10. Manual Teardown and Cleanup

> ⚠️ **IMPORTANT**: This setup creates billable Azure resources. GPU VMs can cost $25-100+ per day if left running!

### 10.1 Quick Cleanup Commands

```bash
# Remove all Kubernetes GPU workloads
kubectl delete deployment multi-gpu-test --ignore-not-found=true
kubectl delete job gpu-test-manual --ignore-not-found=true
kubectl delete namespace gpu-workloads --ignore-not-found=true

# Uninstall GPU Operator
helm uninstall gpu-operator -n gpu-operator-resources
kubectl delete namespace gpu-operator-resources --ignore-not-found=true

# Delete the entire resource group (removes ALL resources)
RESOURCE_GROUP="aks-gpu-manual-rg"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "💰 Cleanup initiated - billing will stop soon!"
```

### 10.2 Step-by-Step Manual Teardown

#### Step 1: Remove GPU Workloads

```bash
# List current GPU workloads
kubectl get pods --all-namespaces -o wide | grep nvidia

# Remove test deployments
kubectl delete deployment multi-gpu-test --ignore-not-found=true
kubectl delete job gpu-test-manual --ignore-not-found=true

# Remove custom namespaces
kubectl delete namespace gpu-workloads --ignore-not-found=true

echo "✅ GPU workloads removed"
```

#### Step 2: Uninstall NVIDIA GPU Operator

```bash
# Check current Helm releases
helm list --all-namespaces

# Uninstall GPU Operator
helm uninstall gpu-operator -n gpu-operator-resources

# Wait for pods to terminate
kubectl wait --for=delete pods --all -n gpu-operator-resources --timeout=300s

# Remove namespace
kubectl delete namespace gpu-operator-resources --ignore-not-found=true

# Clean up any remaining cluster-scoped resources
kubectl delete clusterpolicy cluster-policy --ignore-not-found=true

echo "✅ GPU Operator uninstalled"
```

#### Step 3: Delete Azure Kubernetes Service

```bash
# Set variables (use your actual values)
RESOURCE_GROUP="aks-gpu-manual-rg"
CLUSTER_NAME="aks-gpu-manual"

# Delete AKS cluster (this also removes node pools)
echo "🗑️ Deleting AKS cluster..."
az aks delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --yes \
    --no-wait

echo "✅ AKS cluster deletion initiated"
```

#### Step 4: Delete Supporting Azure Resources

```bash
# Delete Log Analytics workspace
echo "🗑️ Deleting Log Analytics workspace..."
az monitor log-analytics workspace delete \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "aks-gpu-logs" \
    --yes \
    --no-wait

# Delete Virtual Network and subnets
echo "🗑️ Deleting virtual network..."
az network vnet delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "aks-gpu-vnet"

echo "✅ Supporting resources deleted"
```

#### Step 5: Delete Resource Group (Complete Cleanup)

```bash
# ⚠️ NUCLEAR OPTION: Delete everything in the resource group
RESOURCE_GROUP="aks-gpu-manual-rg"

# List resources that will be deleted
echo "📋 Resources to be deleted:"
az resource list --resource-group "$RESOURCE_GROUP" --output table

echo ""
echo "⚠️ WARNING: This will delete ALL resources in $RESOURCE_GROUP"
echo "💰 This action will stop all billing for these resources"
echo ""
read -p "Type 'DELETE' to confirm: " confirmation

if [ "$confirmation" = "DELETE" ]; then
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "✅ Resource group deletion initiated"
    echo "💰 All resources will be deleted - billing stopped!"
else
    echo "❌ Deletion cancelled"
fi
```

### 10.3 Clean Up Local Configuration

```bash
# Remove kubectl context
CLUSTER_NAME="aks-gpu-manual"
kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true

# Clear any cached Azure credentials (optional)
az account clear

# Remove Helm repositories (optional)
helm repo remove nvidia

echo "✅ Local configuration cleaned"
```

### 10.4 Verification and Cost Monitoring

```bash
# Verify resource group is deleted
RESOURCE_GROUP="aks-gpu-manual-rg"
if az group exists --name "$RESOURCE_GROUP"; then
    echo "⚠️ Resource group still exists - deletion in progress"
    echo "📊 Check deletion status:"
    az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" -o tsv
else
    echo "✅ Resource group successfully deleted"
fi

# Check for any remaining GPU-related resources
echo "� Checking for remaining GPU resources across all subscriptions..."
az resource list --query "[?contains(type, 'Microsoft.ContainerService') || contains(name, 'gpu') || contains(name, 'nvidia')].{Name:name, Type:type, ResourceGroup:resourceGroup}" --output table
```

### 10.5 Automated Cleanup Script

For convenience, you can use the comprehensive cleanup script:

```bash
# Navigate to the repository root
cd /path/to/aks-gpu-terraform

# Run interactive cleanup
./scripts/cleanup.sh

# Or run specific cleanup modes
./scripts/cleanup.sh --manual     # Clean manual deployment
./scripts/cleanup.sh --terraform  # Clean Terraform deployment
./scripts/cleanup.sh --emergency  # Nuclear option - clean everything
```

### 10.6 Cost Monitoring Best Practices

1.  **Set up Azure Budgets**:
    ```bash
    # Create a budget alert for your subscription
    az consumption budget create \
        --budget-name "AKS-GPU-Budget" \
        --amount 100 \
        --category "Cost" \
        --time-grain "Monthly"
    ```

2.  **Regular Resource Audits**:
    ```bash
    # List expensive resources
    az resource list --query "[?type=='Microsoft.ContainerService/managedClusters' || contains(type, 'Compute')].{Name:name, Type:type, Location:location, ResourceGroup:resourceGroup}" --output table
    ```

3.  **Automated Cleanup Reminders**:
    -   Set calendar reminders to check your Azure resources
    -   Use Azure Automation to automatically shut down development environments
    -   Monitor your billing dashboard regularly

### 💰 Cost Impact Summary

Properly cleaning up this setup saves:

-   **GPU VMs**: $20-65/day per node (Standard_NC6s_v3)
-   **AKS Management**: $2.40/day ($0.10/hour)
-   **Storage & Networking**: $1-5/day
-   **Total Potential Savings**: $25-100+ per day

> 🎯 **Pro Tip**: Always run cleanup immediately after testing to avoid unexpected charges!

## �📚 Next Steps

After completing this manual setup:

1.  **Deploy your ML workloads** with GPU resource requests
2.  **Monitor GPU utilization** and adjust time-slicing as needed
3.  **Set up proper monitoring** with Prometheus and Grafana
4.  **Create cleanup reminders** to avoid unexpected costs
5.  **Implement auto-scaling policies** for cost optimization
6.  **Consider using Terraform** for future deployments for better automation

This manual process gives you deep understanding of how GPU time-slicing works in AKS, making you better equipped to troubleshoot and optimize your GPU workloads!
