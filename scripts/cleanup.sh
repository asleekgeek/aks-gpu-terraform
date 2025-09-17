#!/bin/bash

# Comprehensive cleanup script for AKS GPU setup
# Handles both Terraform and manual deployments
# WARNING: This will delete billable Azure resources!

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_RESOURCE_GROUP="aks-gpu-manual-rg"
DEFAULT_CLUSTER_NAME="aks-gpu-manual"

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

log_cost() {
    echo -e "${PURPLE}[COST SAVINGS]${NC} $1"
}

# Show estimated cost savings
show_cost_info() {
    echo
    log_cost "=== ESTIMATED COST SAVINGS ==="
    log_cost "GPU VMs (Standard_NC6s_v3): ~$0.90-2.70/hour per node"
    log_cost "AKS cluster: ~$0.10/hour (management fee)"
    log_cost "Storage, networking: ~$5-20/month"
    log_cost ""
    log_cost "💰 Deleting this setup saves: $25-100+/day if left running!"
    echo
}

# Detect setup type
detect_setup_type() {
    local terraform_exists=false
    local manual_resources=false
    
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
    
    # Check for Terraform setup
    if [ -d "$TERRAFORM_DIR" ] && ([ -f "$TERRAFORM_DIR/terraform.tfstate" ] || [ -f "$TERRAFORM_DIR/.terraform/terraform.tfstate" ]); then
        terraform_exists=true
    fi
    
    # Check for manual setup resources
    if az group exists --name "$DEFAULT_RESOURCE_GROUP" 2>/dev/null; then
        manual_resources=true
    fi
    
    echo "terraform:$terraform_exists,manual:$manual_resources"
}

# Cleanup Kubernetes resources (common for both setups)
cleanup_kubernetes() {
    log_info "Cleaning up Kubernetes resources..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log_warning "Cannot connect to Kubernetes cluster - skipping K8s cleanup"
        return 0
    fi
    
    # Remove test workloads
    log_info "Removing test workloads..."
    kubectl delete deployment multi-gpu-workload -n gpu-workloads --ignore-not-found=true --timeout=60s
    kubectl delete deployment multi-gpu-test --ignore-not-found=true --timeout=60s
    kubectl delete job gpu-test --ignore-not-found=true --timeout=60s
    kubectl delete job gpu-test-manual --ignore-not-found=true --timeout=60s
    kubectl delete job gpu-monitor -n gpu-workloads --ignore-not-found=true --timeout=60s
    kubectl delete namespace gpu-workloads --ignore-not-found=true --timeout=120s
    
    # Remove GPU Operator
    log_info "Removing NVIDIA GPU Operator..."
    if command -v helm &> /dev/null && helm list -n gpu-operator-resources 2>/dev/null | grep -q gpu-operator; then
        helm uninstall gpu-operator -n gpu-operator-resources --timeout=300s
        log_success "GPU Operator uninstalled"
    else
        log_info "GPU Operator not found or Helm not available"
    fi
    
    # Remove GPU Operator namespace and resources
    kubectl delete namespace gpu-operator-resources --ignore-not-found=true --timeout=120s
    
    # Clean up any remaining GPU-related resources
    kubectl delete clusterpolicy cluster-policy --ignore-not-found=true --timeout=60s
    
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
        
        # Get resource group name from Terraform output
        local rg_name=""
        if terraform output resource_group_name &> /dev/null; then
            rg_name=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
        fi
        
        if [ -n "$rg_name" ]; then
            log_warning "This will destroy ALL resources in resource group: $rg_name"
        else
            log_warning "This will destroy all Azure resources created by Terraform!"
        fi
        
        echo
        read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
        echo
        
        if [[ $REPLY == "DELETE" ]]; then
            log_info "Running terraform destroy..."
            terraform destroy -auto-approve
            
            # Clean up local state files
            rm -f terraform.tfstate*
            rm -rf .terraform/
            
            log_success "Terraform resources destroyed"
            log_cost "💰 Azure resources deleted - billing stopped!"
        else
            log_info "Terraform cleanup cancelled"
            return 1
        fi
    else
        log_info "No Terraform state found - nothing to destroy"
    fi
}

# Cleanup manual Azure resources
cleanup_manual_azure() {
    log_info "Cleaning up manually created Azure resources..."
    
    # Get resource group name from user or use default
    local resource_group=""
    echo
    read -p "Enter resource group name [$DEFAULT_RESOURCE_GROUP]: " resource_group
    resource_group=${resource_group:-$DEFAULT_RESOURCE_GROUP}
    
    # Check if resource group exists
    if ! az group exists --name "$resource_group" 2>/dev/null; then
        log_warning "Resource group '$resource_group' not found"
        return 0
    fi
    
    # Show resources that will be deleted
    log_info "Resources in '$resource_group' that will be deleted:"
    az resource list --resource-group "$resource_group" --output table 2>/dev/null || log_warning "Could not list resources"
    
    echo
    log_warning "This will DELETE ALL resources in resource group: $resource_group"
    log_warning "This action cannot be undone!"
    echo
    read -p "Type 'DELETE' to confirm deletion: " -r
    echo
    
    if [[ $REPLY == "DELETE" ]]; then
        log_info "Deleting resource group '$resource_group'..."
        az group delete --name "$resource_group" --yes --no-wait
        
        log_success "Resource group deletion initiated"
        log_info "Deletion is running in background. Check Azure portal for progress."
        log_cost "💰 All resources in '$resource_group' will be deleted - billing stopped!"
    else
        log_info "Manual cleanup cancelled"
        return 1
    fi
}

# Cleanup local configuration
cleanup_local_config() {
    log_info "Cleaning up local configuration..."
    
    # Remove kubectl contexts (optional)
    echo
    read -p "Remove kubectl contexts for deleted clusters? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # List AKS contexts
        local contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep -E "(aks-gpu|gpu-cluster)" || true)
        
        if [ -n "$contexts" ]; then
            for context in $contexts; do
                log_info "Removing kubectl context: $context"
                kubectl config delete-context "$context" 2>/dev/null || true
            done
        else
            log_info "No AKS GPU contexts found"
        fi
    fi
    
    # Clean up any cached credentials
    echo
    read -p "Clear Azure CLI cache? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        az account clear 2>/dev/null || true
        log_info "Azure CLI cache cleared"
    fi
    
    log_success "Local configuration cleaned up"
}

# Emergency cleanup (force delete everything)
emergency_cleanup() {
    log_error "=== EMERGENCY CLEANUP MODE ==="
    log_warning "This will attempt to delete ALL AKS and GPU-related resources!"
    echo
    read -p "Type 'EMERGENCY' to continue: " -r
    echo
    
    if [[ $REPLY == "EMERGENCY" ]]; then
        # Find all resource groups with AKS/GPU keywords
        log_info "Searching for AKS/GPU resource groups..."
        local rg_list=$(az group list --query "[?contains(name, 'aks') || contains(name, 'gpu')].name" -o tsv 2>/dev/null || true)
        
        if [ -n "$rg_list" ]; then
            echo "Found resource groups:"
            echo "$rg_list"
            echo
            read -p "Delete all these resource groups? Type 'DELETE ALL' to confirm: " -r
            echo
            
            if [[ $REPLY == "DELETE ALL" ]]; then
                for rg in $rg_list; do
                    log_info "Deleting resource group: $rg"
                    az group delete --name "$rg" --yes --no-wait 2>/dev/null || log_warning "Failed to delete $rg"
                done
                log_success "Emergency cleanup initiated for all found resource groups"
            fi
        else
            log_info "No AKS/GPU resource groups found"
        fi
    else
        log_info "Emergency cleanup cancelled"
    fi
}

# Main cleanup menu
main() {
    show_cost_info
    
    log_info "=== AKS GPU CLEANUP SCRIPT ==="
    log_warning "This script removes billable Azure resources!"
    echo
    
    # Detect what type of setup exists
    local setup_info=$(detect_setup_type)
    local terraform_exists=$(echo "$setup_info" | cut -d',' -f1 | cut -d':' -f2)
    local manual_exists=$(echo "$setup_info" | cut -d',' -f2 | cut -d':' -f2)
    
    echo "Detected setup types:"
    [ "$terraform_exists" = "true" ] && echo "  ✓ Terraform deployment found"
    [ "$manual_exists" = "true" ] && echo "  ✓ Manual deployment found"
    [ "$terraform_exists" = "false" ] && [ "$manual_exists" = "false" ] && echo "  ℹ No active deployments detected"
    echo
    
    # Cleanup menu
    echo "Cleanup options:"
    echo "1. Clean up Kubernetes resources only"
    echo "2. Clean up Terraform deployment (if exists)"
    echo "3. Clean up manual Azure resources"
    echo "4. Full cleanup (K8s + Azure resources)"
    echo "5. Local configuration cleanup"
    echo "6. Emergency cleanup (all AKS/GPU resources)"
    echo "7. Exit without changes"
    echo
    
    read -p "Choose an option (1-7): " -n 1 -r
    echo
    echo
    
    case $REPLY in
        1)
            cleanup_kubernetes
            ;;
        2)
            if [ "$terraform_exists" = "true" ]; then
                cleanup_kubernetes
                cleanup_terraform
            else
                log_warning "No Terraform deployment found"
            fi
            ;;
        3)
            cleanup_kubernetes
            cleanup_manual_azure
            ;;
        4)
            cleanup_kubernetes
            if [ "$terraform_exists" = "true" ]; then
                cleanup_terraform
            else
                cleanup_manual_azure
            fi
            ;;
        5)
            cleanup_local_config
            ;;
        6)
            emergency_cleanup
            ;;
        7)
            log_info "Exiting without changes"
            exit 0
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac
    
    echo
    cleanup_local_config
    
    echo
    log_success "=== CLEANUP COMPLETED ==="
    log_cost "💰 Check Azure portal to verify all resources are deleted"
    log_info "💡 Tip: Monitor your Azure billing for a few days to ensure charges stopped"
}

# Handle script arguments
case "${1:-}" in
    --terraform)
        cleanup_kubernetes
        cleanup_terraform
        ;;
    --manual)
        cleanup_kubernetes  
        cleanup_manual_azure
        ;;
    --emergency)
        emergency_cleanup
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo "Options:"
        echo "  --terraform   Clean up Terraform deployment"
        echo "  --manual      Clean up manual deployment"
        echo "  --emergency   Emergency cleanup (all AKS/GPU resources)"
        echo "  --help        Show this help"
        echo "  (no option)   Interactive menu"
        ;;
    "")
        main "$@"
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for available options"
        exit 1
        ;;
esac