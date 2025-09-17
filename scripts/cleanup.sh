#!/bin/bash

# Cleanup script for AKS GPU Terraform setup
# This script removes all resources created by the terraform configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Cleanup Kubernetes resources
cleanup_kubernetes() {
    log_info "Cleaning up Kubernetes resources..."
    
    # Remove test workloads
    kubectl delete deployment multi-gpu-workload -n gpu-workloads --ignore-not-found=true
    kubectl delete job gpu-test --ignore-not-found=true
    kubectl delete job gpu-monitor -n gpu-workloads --ignore-not-found=true
    kubectl delete namespace gpu-workloads --ignore-not-found=true
    
    # Remove GPU Operator
    if helm list -n gpu-operator-resources | grep -q gpu-operator; then
        log_info "Removing GPU Operator..."
        helm uninstall gpu-operator -n gpu-operator-resources
    fi
    
    # Remove GPU Operator namespace
    kubectl delete namespace gpu-operator-resources --ignore-not-found=true
    
    log_success "Kubernetes resources cleaned up"
}

# Cleanup Terraform resources
cleanup_terraform() {
    log_info "Cleaning up Terraform resources..."
    
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log_error "Terraform directory not found: $TERRAFORM_DIR"
        return 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    # Check if terraform state exists
    if [ -f "terraform.tfstate" ] || [ -f ".terraform/terraform.tfstate" ]; then
        log_warning "This will destroy all Azure resources created by Terraform!"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            terraform destroy -auto-approve
            log_success "Terraform resources destroyed"
        else
            log_info "Terraform cleanup cancelled"
        fi
    else
        log_info "No Terraform state found - nothing to destroy"
    fi
}

# Main cleanup function
main() {
    echo
    log_info "=== AKS GPU CLEANUP SCRIPT ==="
    log_warning "This script will remove all resources created by this setup"
    echo
    
    # Ask for confirmation
    read -p "Do you want to cleanup Kubernetes resources? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_kubernetes
        echo
    fi
    
    read -p "Do you want to cleanup Terraform resources (Azure resources)? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_terraform
        echo
    fi
    
    log_info "Cleanup completed!"
    echo
    log_info "Manual cleanup steps (if needed):"
    echo "1. Remove any remaining Azure resources through the Azure portal"
    echo "2. Delete local Terraform state files if needed"
    echo "3. Remove kubectl context: kubectl config delete-context <context-name>"
}

# Execute main function
main "$@"