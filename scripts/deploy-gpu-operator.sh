#!/bin/bash

# Deploy NVIDIA GPU Operator to AKS cluster
# This script installs the GPU Operator with time-slicing configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please run 'az aks get-credentials' first"
        exit 1
    fi
    
    # Check for GPU nodes
    GPU_NODES=$(kubectl get nodes -l accelerator=nvidia --no-headers 2>/dev/null | wc -l)
    if [ "$GPU_NODES" -eq 0 ]; then
        log_warning "No GPU nodes found with label 'accelerator=nvidia'"
        log_info "Available nodes:"
        kubectl get nodes
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Found $GPU_NODES GPU node(s)"
    fi
}

# Add NVIDIA Helm repository
add_helm_repo() {
    log_info "Adding NVIDIA Helm repository..."
    
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    helm repo update
    
    log_success "NVIDIA Helm repository added"
}

# Create namespace for GPU operator
create_namespace() {
    log_info "Creating gpu-operator-resources namespace..."
    
    kubectl create namespace gpu-operator-resources --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Namespace created/updated"
}

# Deploy GPU Operator
deploy_gpu_operator() {
    log_info "Deploying NVIDIA GPU Operator..."
    
    # Get the directory of this script
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    VALUES_FILE="$SCRIPT_DIR/../kubernetes/gpu-operator-values.yaml"
    
    if [ ! -f "$VALUES_FILE" ]; then
        log_error "GPU Operator values file not found: $VALUES_FILE"
        exit 1
    fi
    
    # Install or upgrade GPU Operator
    helm upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator-resources \
        --values "$VALUES_FILE" \
        --wait \
        --timeout=600s
    
    log_success "GPU Operator deployed"
}

# Wait for GPU Operator to be ready
wait_for_operator() {
    log_info "Waiting for GPU Operator to be ready..."
    
    # Wait for essential pods
    kubectl wait --for=condition=ready pod \
        -l app=gpu-operator \
        -n gpu-operator-resources \
        --timeout=300s
    
    log_info "Waiting for device plugin to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=nvidia-device-plugin-daemonset \
        -n gpu-operator-resources \
        --timeout=300s
    
    log_success "GPU Operator is ready"
}

# Apply time-slicing configuration
apply_time_slicing() {
    log_info "Applying GPU time-slicing configuration..."
    
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    CONFIG_FILE="$SCRIPT_DIR/../kubernetes/gpu-time-slicing-config.yaml"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Time-slicing config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    kubectl apply -f "$CONFIG_FILE"
    
    log_info "Restarting device plugin to apply time-slicing configuration..."
    kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset --ignore-not-found=true
    
    # Wait for device plugin to restart
    sleep 10
    kubectl wait --for=condition=ready pod \
        -l app=nvidia-device-plugin-daemonset \
        -n gpu-operator-resources \
        --timeout=300s
    
    log_success "Time-slicing configuration applied"
}

# Verify installation
verify_installation() {
    log_info "Verifying GPU Operator installation..."
    
    # Check GPU nodes
    log_info "GPU nodes:"
    kubectl get nodes -l accelerator=nvidia
    
    # Check GPU resources
    log_info "GPU resources available:"
    kubectl describe nodes -l accelerator=nvidia | grep -E "nvidia.com/gpu|Capacity|Allocatable" | head -20
    
    # Check GPU Operator pods
    log_info "GPU Operator pods:"
    kubectl get pods -n gpu-operator-resources
    
    # Check time-slicing config
    log_info "Time-slicing configuration:"
    kubectl get configmap time-slicing-config -n gpu-operator-resources -o yaml | head -20
    
    log_success "Installation verification complete"
}

# Main execution
main() {
    log_info "Starting NVIDIA GPU Operator deployment..."
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
    
    log_success "NVIDIA GPU Operator deployment completed successfully!"
    echo
    log_info "Next steps:"
    echo "  1. Test GPU functionality: kubectl apply -f ../kubernetes/examples/gpu-test-job.yaml"
    echo "  2. Test time-slicing: kubectl apply -f ../kubernetes/examples/multi-gpu-workload.yaml"
    echo "  3. Monitor GPU usage: kubectl logs -f job/gpu-test"
    echo "  4. Run validation script: ./validate-setup.sh"
}

# Execute main function
main "$@"