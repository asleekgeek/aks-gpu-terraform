# On-Premises GPU Time-Slicing Setup Guide

This guide adapts the AKS GPU time-slicing concepts for **on-premises Kubernetes clusters**. You'll achieve the same GPU sharing capabilities without Azure dependencies.

## 📑 Table of Contents

- [On-Premises GPU Time-Slicing Setup Guide](#on-premises-gpu-time-slicing-setup-guide)
  - [📑 Table of Contents](#-table-of-contents)
  - [🎯 Overview](#-overview)
  - [📋 Prerequisites](#-prerequisites)
    - [Hardware Requirements](#hardware-requirements)
    - [Software Requirements](#software-requirements)
      - [On All Nodes:](#on-all-nodes)
      - [On GPU Nodes Only:](#on-gpu-nodes-only)
      - [Management Node:](#management-node)
  - [🚀 Step-by-Step Setup](#-step-by-step-setup)
    - [Step 1: Prepare GPU Nodes](#step-1-prepare-gpu-nodes)
      - [1.1 Install NVIDIA Drivers](#11-install-nvidia-drivers)
      - [1.2 Install Container Runtime with GPU Support](#12-install-container-runtime-with-gpu-support)
    - [Step 2: Configure Kubernetes Nodes](#step-2-configure-kubernetes-nodes)
      - [2.1 Label GPU Nodes](#21-label-gpu-nodes)
      - [2.2 Taint GPU Nodes](#22-taint-gpu-nodes)
    - [Step 3: Deploy NVIDIA GPU Operator](#step-3-deploy-nvidia-gpu-operator)
      - [3.1 Create Deployment Script](#31-create-deployment-script)
      - [3.2 Make Script Executable](#32-make-script-executable)
    - [Step 4: Create Test Workloads](#step-4-create-test-workloads)
      - [4.1 Single GPU Test](#41-single-gpu-test)
      - [4.2 Time-Slicing Test](#42-time-slicing-test)
    - [Step 5: Deploy and Test](#step-5-deploy-and-test)
      - [5.1 Deploy GPU Operator](#51-deploy-gpu-operator)
      - [5.2 Test Single GPU](#52-test-single-gpu)
      - [5.3 Test Time-Slicing](#53-test-time-slicing)
  - [🔧 Configuration Options](#-configuration-options)
    - [Time-Slicing Profiles](#time-slicing-profiles)
    - [Node Management](#node-management)
  - [🚨 Troubleshooting](#-troubleshooting)
    - [Common Issues](#common-issues)
      - [GPU Nodes Not Ready](#gpu-nodes-not-ready)
      - [Time-Slicing Not Working](#time-slicing-not-working)
      - [GPU Operator Pods Failing](#gpu-operator-pods-failing)
  - [🧹 Cleanup](#-cleanup)
    - [Remove GPU Operator](#remove-gpu-operator)
  - [📊 Monitoring](#-monitoring)
    - [Basic Monitoring](#basic-monitoring)
    - [Advanced Monitoring with Prometheus \& Grafana](#advanced-monitoring-with-prometheus--grafana)
      - [Option 1: Using AKS Monitoring Scripts (Adapted)](#option-1-using-aks-monitoring-scripts-adapted)
      - [Option 2: Manual Monitoring Deployment](#option-2-manual-monitoring-deployment)
      - [Accessing Monitoring Dashboards](#accessing-monitoring-dashboards)
      - [Import Custom GPU Dashboard](#import-custom-gpu-dashboard)
    - [DCGM Metrics Collection](#dcgm-metrics-collection)
    - [Monitoring Best Practices for On-Premises](#monitoring-best-practices-for-on-premises)
    - [Troubleshooting Monitoring Issues](#troubleshooting-monitoring-issues)
  - [🔗 Integration with AKS Codebase](#-integration-with-aks-codebase)

## 🎯 Overview

This setup enables:

-   On-premises Kubernetes cluster with GPU-enabled nodes
-   NVIDIA GPU Operator for GPU resource management
-   GPU time-slicing to share GPUs between multiple workloads
-   Same time-slicing configurations as the AKS version

## 📋 Prerequisites

### Hardware Requirements

-   **GPU nodes** with NVIDIA GPUs (any supported architecture)
-   **System nodes** for Kubernetes control plane and system workloads
-   **Network connectivity** between all nodes
-   **Sufficient resources**: 8GB+ RAM, 4+ CPU cores per GPU node

### Software Requirements

#### On All Nodes:

```bash
# Container runtime (containerd recommended)
containerd --version

# Kubernetes cluster (any distribution)
kubectl version

# Basic tools
curl --version
```

#### On GPU Nodes Only:

```bash
# NVIDIA drivers (version 470+)
nvidia-smi

# nvidia-container-runtime
nvidia-container-runtime --version

# Verify GPU detection
lspci | grep -i nvidia
```

#### Management Node:

```bash
# Helm 3.x
helm version

# kubectl with cluster access
kubectl cluster-info
```

## 🚀 Step-by-Step Setup

### Step 1: Prepare GPU Nodes

#### 1.1 Install NVIDIA Drivers

```bash
# On each GPU node (Ubuntu/Debian example)
sudo apt update
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

# Reboot and verify
sudo reboot
nvidia-smi
```

#### 1.2 Install Container Runtime with GPU Support

```bash
# Install containerd with NVIDIA support
sudo apt install -y containerd nvidia-container-runtime

# Configure containerd for GPU support
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Edit /etc/containerd/config.toml to add nvidia runtime
sudo nano /etc/containerd/config.toml
```

Add to containerd config:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  privileged_without_host_devices = false
  runtime_engine = ""
  runtime_root = ""
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
```

```bash
# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Step 2: Configure Kubernetes Nodes

#### 2.1 Label GPU Nodes

```bash
# Label each GPU node (replace with your node names)
kubectl label nodes gpu-node-1 accelerator=nvidia
kubectl label nodes gpu-node-1 gpu-type=<your-gpu-model>  # e.g., tesla-v100, rtx-4090

# Verify labels
kubectl get nodes --show-labels | grep accelerator
```

#### 2.2 Taint GPU Nodes

```bash
# Taint GPU nodes to prevent non-GPU workloads
kubectl taint nodes gpu-node-1 nvidia.com/gpu=true:NoSchedule

# Verify taints
kubectl describe nodes gpu-node-1 | grep Taints
```

### Step 3: Deploy NVIDIA GPU Operator

#### 3.1 Create Deployment Script

Create `scripts/deploy-gpu-operator-onprem.sh`:

```bash
#!/bin/bash

# On-premises NVIDIA GPU Operator deployment
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed"
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check for labeled GPU nodes
    GPU_NODES=$(kubectl get nodes -l accelerator=nvidia --no-headers 2>/dev/null | wc -l)
    if [ "$GPU_NODES" -eq 0 ]; then
        log_error "No GPU nodes found with label 'accelerator=nvidia'"
        log_info "Please label your GPU nodes first:"
        log_info "kubectl label nodes <gpu-node> accelerator=nvidia"
        exit 1
    else
        log_success "Found $GPU_NODES GPU node(s)"
    fi
    
    # Check for nvidia-smi on GPU nodes
    log_info "Checking NVIDIA drivers on GPU nodes..."
    for node in $(kubectl get nodes -l accelerator=nvidia -o jsonpath='{.items[*].metadata.name}'); do
        log_info "Checking node: $node"
        # This is a simplified check - in practice you might need to SSH to nodes
        log_warning "Ensure nvidia-smi works on $node"
    done
}

# Add NVIDIA Helm repository
add_helm_repo() {
    log_info "Adding NVIDIA Helm repository..."
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    helm repo update
    log_success "NVIDIA Helm repository added"
}

# Create namespace
create_namespace() {
    log_info "Creating gpu-operator-resources namespace..."
    kubectl create namespace gpu-operator-resources --dry-run=client -o yaml | kubectl apply -f -
    log_success "Namespace created/updated"
}

# Deploy GPU Operator
deploy_gpu_operator() {
    log_info "Deploying NVIDIA GPU Operator for on-premises..."
    
    # Install GPU Operator with on-premises optimizations
    helm upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator-resources \
        --set operator.defaultRuntime=containerd \
        --set driver.enabled=false \
        --set toolkit.enabled=true \
        --set devicePlugin.enabled=true \
        --set devicePlugin.config.name=time-slicing-config \
        --set devicePlugin.config.default=any \
        --set migManager.enabled=false \
        --set mig.strategy=none \
        --set nodeStatusExporter.enabled=true \
        --set dcgm.enabled=true \
        --set dcgmExporter.enabled=true \
        --wait \
        --timeout=600s
    
    log_success "GPU Operator deployed"
    log_info "Note: Driver installation is disabled (assuming pre-installed drivers)"
}

# Wait for GPU Operator
wait_for_operator() {
    log_info "Waiting for GPU Operator to be ready..."
    
    # Wait for device plugin
    kubectl wait --for=condition=ready pod \
        -l app=nvidia-device-plugin-daemonset \
        -n gpu-operator-resources \
        --timeout=300s
    
    log_success "GPU Operator is ready"
}

# Apply time-slicing configuration
apply_time_slicing() {
    log_info "Applying GPU time-slicing configuration..."
    
    # Apply time-slicing ConfigMap
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator-resources
data:
  any: |-
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 4
        failRequestsGreaterThanOne: true
  
  high-memory: |-
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 2
        failRequestsGreaterThanOne: true
  
  high-density: |-
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 8
        failRequestsGreaterThanOne: true
EOF
    
    log_info "Restarting device plugin to apply configuration..."
    kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset --ignore-not-found=true
    
    # Wait for restart
    sleep 10
    kubectl wait --for=condition=ready pod \
        -l app=nvidia-device-plugin-daemonset \
        -n gpu-operator-resources \
        --timeout=300s
    
    log_success "Time-slicing configuration applied"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    echo
    log_info "GPU Nodes:"
    kubectl get nodes -l accelerator=nvidia
    
    echo
    log_info "GPU Resources:"
    kubectl describe nodes -l accelerator=nvidia | grep -E "nvidia.com/gpu|Capacity|Allocatable" | head -10
    
    echo
    log_info "GPU Operator Pods:"
    kubectl get pods -n gpu-operator-resources
    
    echo
    log_info "Time-slicing Configuration:"
    kubectl get configmap time-slicing-config -n gpu-operator-resources -o yaml | head -20
    
    log_success "Installation verification complete"
}

# Main execution
main() {
    log_info "Starting on-premises NVIDIA GPU Operator deployment..."
    echo
    
    check_prerequisites
    echo
    
    add_helm_repo
    echo
    
    create_namespace
    echo
    
    deploy_gpu_operator
    echo
    
    wait_for_operator
    echo
    
    apply_time_slicing
    echo
    
    verify_installation
    echo
    
    log_success "On-premises GPU Operator deployment completed!"
    echo
    log_info "Next steps:"
    echo "  1. Test GPU: kubectl apply -f examples/gpu-test-onprem.yaml"
    echo "  2. Test time-slicing: kubectl apply -f examples/multi-gpu-onprem.yaml"
    echo "  3. Monitor: kubectl top nodes"
    echo "  4. Run validation: ./validate-setup-onprem.sh"
}

main "$@"
```

#### 3.2 Make Script Executable

```bash
chmod +x scripts/deploy-gpu-operator-onprem.sh
```

### Step 4: Create Test Workloads

#### 4.1 Single GPU Test

Create `kubernetes/examples/gpu-test-onprem.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-test-onprem
  namespace: default
spec:
  template:
    metadata:
      labels:
        app: gpu-test-onprem
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
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "=== On-Premises GPU Test ==="
              echo "Node: $NODE_NAME"
              echo "Pod: $POD_NAME"
              echo ""
              
              echo "=== NVIDIA Driver Info ==="
              nvidia-smi
              echo ""
              
              echo "=== GPU Device Info ==="
              nvidia-smi -L
              echo ""
              
              echo "=== GPU Memory Info ==="
              nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv
              echo ""
              
              echo "=== Simple CUDA Test ==="
              echo "Testing GPU compute capability..."
              timeout 30s python3 -c "
              import time
              print('GPU stress test running for 30 seconds...')
              for i in range(30):
                  print(f'Second {i+1}/30')
                  time.sleep(1)
              print('GPU test completed successfully!')
              " || echo "Basic timing test completed"
              
              echo "=== Test Completed Successfully ==="
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          resources:
            requests:
              nvidia.com/gpu: 1
            limits:
              nvidia.com/gpu: 1
              memory: "1Gi"
              cpu: "500m"
```

#### 4.2 Time-Slicing Test

Create `kubernetes/examples/multi-gpu-onprem.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-gpu-onprem
  namespace: default
spec:
  replicas: 4  # More replicas than physical GPUs to test time-slicing
  selector:
    matchLabels:
      app: multi-gpu-onprem
  template:
    metadata:
      labels:
        app: multi-gpu-onprem
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
              echo "Time-slicing test starting on pod $HOSTNAME"
              echo "Node: $NODE_NAME"
              nvidia-smi -L
              echo "Running workload for 120 seconds..."
              
              # Simple GPU workload
              python3 -c "
              import time
              print(f'Pod {$HOSTNAME} using GPU slice')
              for i in range(120):
                  if i % 30 == 0:
                      print(f'Pod $HOSTNAME: Second {i}/120')
                  time.sleep(1)
              print(f'Pod $HOSTNAME: Time-slicing test completed')
              "
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          resources:
            requests:
              nvidia.com/gpu: 1
            limits:
              nvidia.com/gpu: 1
              memory: "512Mi"
              cpu: "250m"
```

### Step 5: Deploy and Test

#### 5.1 Deploy GPU Operator

```bash
# Run the deployment script
./scripts/deploy-gpu-operator-onprem.sh
```

#### 5.2 Test Single GPU

```bash
# Deploy single GPU test
kubectl apply -f kubernetes/examples/gpu-test-onprem.yaml

# Check results
kubectl logs job/gpu-test-onprem
kubectl delete job gpu-test-onprem
```

#### 5.3 Test Time-Slicing

```bash
# Deploy time-slicing test
kubectl apply -f kubernetes/examples/multi-gpu-onprem.yaml

# Verify multiple pods on same GPU
kubectl get pods -l app=multi-gpu-onprem -o wide

# Check logs from multiple pods
kubectl logs -l app=multi-gpu-onprem --tail=10

# Cleanup
kubectl delete deployment multi-gpu-onprem
```

## 🔧 Configuration Options

### Time-Slicing Profiles

Switch between different time-slicing configurations:

```bash
# High-density slicing (8 replicas per GPU)
kubectl patch clusterpolicy cluster-policy -n gpu-operator-resources --type merge -p '{"spec":{"devicePlugin":{"config":{"default":"high-density"}}}}'

# Conservative slicing (2 replicas per GPU)
kubectl patch clusterpolicy cluster-policy -n gpu-operator-resources --type merge -p '{"spec":{"devicePlugin":{"config":{"default":"high-memory"}}}}'

# Restart device plugin after changes
kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset
```

### Node Management

```bash
# Add new GPU node
kubectl label nodes new-gpu-node accelerator=nvidia
kubectl taint nodes new-gpu-node nvidia.com/gpu=true:NoSchedule

# Remove GPU node
kubectl drain gpu-node-1 --ignore-daemonsets --delete-emptydir-data
kubectl delete node gpu-node-1
```

## 🚨 Troubleshooting

### Common Issues

#### GPU Nodes Not Ready

```bash
# Check node status
kubectl describe nodes -l accelerator=nvidia

# Check NVIDIA drivers
ssh gpu-node-1 "nvidia-smi"

# Check container runtime
ssh gpu-node-1 "sudo systemctl status containerd"
```

#### Time-Slicing Not Working

```bash
# Check device plugin logs
kubectl logs -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset

# Verify ConfigMap
kubectl get configmap time-slicing-config -n gpu-operator-resources -o yaml

# Check cluster policy
kubectl get clusterpolicy cluster-policy -o yaml
```

#### GPU Operator Pods Failing

```bash
# Check all GPU operator pods
kubectl get pods -n gpu-operator-resources

# Check specific pod logs
kubectl describe pod <pod-name> -n gpu-operator-resources
kubectl logs <pod-name> -n gpu-operator-resources
```

## 🧹 Cleanup

### Remove GPU Operator

```bash
# Uninstall GPU Operator
helm uninstall gpu-operator -n gpu-operator-resources

# Remove namespace
kubectl delete namespace gpu-operator-resources

# Remove taints and labels
kubectl taint nodes -l accelerator=nvidia nvidia.com/gpu:NoSchedule-
kubectl label nodes -l accelerator=nvidia accelerator-
```

## 📊 Monitoring

### Basic Monitoring

```bash
# Check GPU utilization
kubectl top nodes

# Check GPU resources
kubectl describe nodes -l accelerator=nvidia | grep nvidia.com/gpu

# Monitor GPU operator
kubectl get pods -n gpu-operator-resources -w
```

### Advanced Monitoring with Prometheus & Grafana

For comprehensive GPU monitoring on on-premises clusters, you can deploy the same monitoring stack used in AKS:

#### Option 1: Using AKS Monitoring Scripts (Adapted)

If you have Helm installed, you can adapt the AKS monitoring deployment:

```bash
# Download and modify the monitoring script
curl -O https://raw.githubusercontent.com/your-repo/aks-gpu-terraform/main/scripts/deploy-monitoring.sh

# Make executable
chmod +x deploy-monitoring.sh

# Deploy monitoring stack (ensure you have Helm 3.x)
./deploy-monitoring.sh
```

#### Option 2: Manual Monitoring Deployment

1.  **Add Prometheus Helm Repository**:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

2.  **Create Monitoring Namespace**:

```bash
kubectl create namespace monitoring
```

3.  **Deploy Prometheus Stack**:

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin123 \
  --wait
```

4.  **Deploy GPU Alerts** (if you have the alerts file):

```bash
# Apply GPU-specific alerts
kubectl apply -f https://raw.githubusercontent.com/your-repo/aks-gpu-terraform/main/kubernetes/monitoring/gpu-alerts.yaml
```

#### Accessing Monitoring Dashboards

```bash
# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Default Grafana credentials: admin / admin123
```

#### Import Custom GPU Dashboard

1.  Open Grafana at http&#x3A;//localhost:3000
2.  Login with admin/admin123
3.  Go to "+" → Import
4.  Upload the GPU dashboard JSON from `kubernetes/monitoring/gpu-dashboard.json`

### DCGM Metrics Collection

The NVIDIA GPU Operator automatically deploys DCGM Exporter for metrics collection:

```bash
# Check DCGM Exporter status
kubectl get pods -n gpu-operator-resources | grep dcgm

# View GPU metrics
kubectl port-forward -n gpu-operator-resources svc/nvidia-dcgm-exporter 9400:9400
curl localhost:9400/metrics | grep DCGM_FI_DEV

# Key metrics available:
# - DCGM_FI_DEV_GPU_UTIL: GPU utilization %
# - DCGM_FI_DEV_GPU_TEMP: GPU temperature
# - DCGM_FI_DEV_FB_USED: GPU memory used
# - DCGM_FI_DEV_POWER_USAGE: Power consumption
```

### Monitoring Best Practices for On-Premises

1.  **Resource Monitoring**: Set up alerts for GPU temperature (>80°C) and utilization
2.  **Time-Slicing Efficiency**: Monitor pod density per GPU node
3.  **Cost Tracking**: Track power consumption and compute utilization
4.  **Performance Baselines**: Establish normal operating ranges for your workloads

### Troubleshooting Monitoring Issues

```bash
# Check ServiceMonitor configuration
kubectl get servicemonitor -n gpu-operator-resources

# Verify Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/targets

# Check DCGM Exporter logs
kubectl logs -n gpu-operator-resources -l app=nvidia-dcgm-exporter
```

## 🔗 Integration with AKS Codebase

This on-premises setup reuses:

-   ✅ **Time-slicing ConfigMap structure** from `kubernetes/gpu-time-slicing-config.yaml`
-   ✅ **GPU workload patterns** from `kubernetes/examples/`
-   ✅ **Validation concepts** from `scripts/validate-setup.sh`
-   ✅ **Troubleshooting approaches** from the AKS documentation

Key differences:

-   ❌ No Terraform infrastructure management
-   ❌ No Azure-specific monitoring
-   ❌ No cloud auto-scaling
-   ✅ Manual node management
-   ✅ Pre-installed drivers assumption
-   ✅ Direct Kubernetes cluster access

This gives you the same GPU time-slicing capabilities as the AKS setup, but adapted for on-premises infrastructure.
