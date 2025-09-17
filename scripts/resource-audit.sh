#!/bin/bash

# Quick verification script to check what resources exist
# Helps determine cleanup needs

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[FOUND]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_cost() {
    echo -e "${PURPLE}[COST]${NC} $1"
}

log_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

echo
log_header "AZURE RESOURCE AUDIT"
echo "🔍 Checking for billable GPU/AKS resources..."
echo

# Check Azure CLI login
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure CLI. Run 'az login' first."
    exit 1
fi

CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
echo "📋 Current subscription: $CURRENT_SUBSCRIPTION"
echo

# Check for AKS clusters
log_header "AKS CLUSTERS"
AKS_CLUSTERS=$(az aks list --query "length([*])" -o tsv 2>/dev/null)
if [ "$AKS_CLUSTERS" -gt 0 ]; then
    log_success "Found $AKS_CLUSTERS AKS cluster(s)"
    az aks list --query "[].{Name:name, ResourceGroup:resourceGroup, Location:location, NodePools:agentPoolProfiles[?vmSize].vmSize, Status:powerState.code}" --output table
    log_cost "💰 Each cluster costs ~$0.10/hour + node costs"
else
    log_info "No AKS clusters found"
fi
echo

# Check for GPU VMs
log_header "GPU VIRTUAL MACHINES"
GPU_VMS=$(az vm list --query "[?contains(hardwareProfile.vmSize, 'NC') || contains(hardwareProfile.vmSize, 'ND') || contains(hardwareProfile.vmSize, 'NV')]" -o tsv 2>/dev/null | wc -l)
if [ "$GPU_VMS" -gt 0 ]; then
    log_success "Found $GPU_VMS GPU VM(s)"
    az vm list --query "[?contains(hardwareProfile.vmSize, 'NC') || contains(hardwareProfile.vmSize, 'ND') || contains(hardwareProfile.vmSize, 'NV')].{Name:name, ResourceGroup:resourceGroup, Size:hardwareProfile.vmSize, Status:powerState}" --output table
    log_cost "💰 GPU VMs cost $20-65+ per day each!"
else
    log_info "No GPU VMs found"
fi
echo

# Check for VMSS (used by AKS node pools)
log_header "VIRTUAL MACHINE SCALE SETS"
VMSS_COUNT=$(az vmss list --query "length([*])" -o tsv 2>/dev/null)
if [ "$VMSS_COUNT" -gt 0 ]; then
    log_success "Found $VMSS_COUNT VMSS instance(s)"
    az vmss list --query "[].{Name:name, ResourceGroup:resourceGroup, Location:location, Capacity:sku.capacity, VMSize:sku.name}" --output table
    log_cost "💰 Scale sets may contain expensive GPU nodes"
else
    log_info "No Virtual Machine Scale Sets found"
fi
echo

# Check for expensive resource groups
log_header "RESOURCE GROUPS (AKS/GPU RELATED)"
RG_LIST=$(az group list --query "[?contains(name, 'aks') || contains(name, 'gpu') || contains(name, 'MC_')]" --output table 2>/dev/null)
if [ -n "$RG_LIST" ]; then
    echo "$RG_LIST"
    log_warning "Found resource groups with AKS/GPU keywords"
else
    log_info "No AKS/GPU resource groups found"
fi
echo

# Check current Kubernetes context
log_header "KUBERNETES CONTEXT"
if command -v kubectl &> /dev/null; then
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
    if [ "$CURRENT_CONTEXT" != "none" ]; then
        log_success "Current kubectl context: $CURRENT_CONTEXT"
        
        # Check for GPU resources
        if kubectl cluster-info &> /dev/null; then
            GPU_NODES=$(kubectl get nodes -l accelerator=nvidia --no-headers 2>/dev/null | wc -l)
            if [ "$GPU_NODES" -gt 0 ]; then
                log_success "Found $GPU_NODES GPU node(s) in cluster"
                kubectl get nodes -l accelerator=nvidia -o wide 2>/dev/null || true
            fi
            
            # Check for GPU Operator
            if kubectl get pods -n gpu-operator-resources &> /dev/null; then
                log_success "NVIDIA GPU Operator is installed"
            fi
        fi
    else
        log_info "No active kubectl context"
    fi
else
    log_info "kubectl not found"
fi
echo

# Check Terraform state
log_header "TERRAFORM STATE"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

if [ -d "$TERRAFORM_DIR" ]; then
    cd "$TERRAFORM_DIR"
    if [ -f "terraform.tfstate" ] || [ -f ".terraform/terraform.tfstate" ]; then
        log_success "Terraform state found"
        if command -v terraform &> /dev/null; then
            # Try to get resource count
            RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l || echo "unknown")
            echo "  Resources in state: $RESOURCE_COUNT"
            
            # Try to get resource group name
            RG_NAME=$(terraform output resource_group_name 2>/dev/null || echo "unknown")
            if [ "$RG_NAME" != "unknown" ]; then
                echo "  Managed resource group: $RG_NAME"
            fi
        fi
    else
        log_info "No Terraform state found"
    fi
else
    log_info "No Terraform directory found"
fi
echo

# Estimated costs summary
log_header "COST ESTIMATION"
TOTAL_COST_LOW=0
TOTAL_COST_HIGH=0

if [ "$AKS_CLUSTERS" -gt 0 ]; then
    AKS_DAILY_COST=$(echo "$AKS_CLUSTERS * 2.4" | bc -l 2>/dev/null || echo "$AKS_CLUSTERS * 2")
    echo "AKS Management: $AKS_CLUSTERS clusters × $2.40/day = ~$$AKS_DAILY_COST/day"
    TOTAL_COST_LOW=$(echo "$TOTAL_COST_LOW + $AKS_DAILY_COST" | bc -l 2>/dev/null || echo $((TOTAL_COST_LOW + AKS_DAILY_COST)))
    TOTAL_COST_HIGH=$(echo "$TOTAL_COST_HIGH + $AKS_DAILY_COST" | bc -l 2>/dev/null || echo $((TOTAL_COST_HIGH + AKS_DAILY_COST)))
fi

if [ "$GPU_VMS" -gt 0 ]; then
    GPU_DAILY_LOW=$(echo "$GPU_VMS * 21" | bc -l 2>/dev/null || echo "$((GPU_VMS * 21))")
    GPU_DAILY_HIGH=$(echo "$GPU_VMS * 65" | bc -l 2>/dev/null || echo "$((GPU_VMS * 65))")
    echo "GPU VMs: $GPU_VMS nodes × $21-65/day = ~$$GPU_DAILY_LOW-$$GPU_DAILY_HIGH/day"
    TOTAL_COST_LOW=$(echo "$TOTAL_COST_LOW + $GPU_DAILY_LOW" | bc -l 2>/dev/null || echo $((TOTAL_COST_LOW + GPU_DAILY_LOW)))
    TOTAL_COST_HIGH=$(echo "$TOTAL_COST_HIGH + $GPU_DAILY_HIGH" | bc -l 2>/dev/null || echo $((TOTAL_COST_HIGH + GPU_DAILY_HIGH)))
fi

echo "Storage & Networking: ~$1-5/day"
TOTAL_COST_LOW=$(echo "$TOTAL_COST_LOW + 1" | bc -l 2>/dev/null || echo $((TOTAL_COST_LOW + 1)))
TOTAL_COST_HIGH=$(echo "$TOTAL_COST_HIGH + 5" | bc -l 2>/dev/null || echo $((TOTAL_COST_HIGH + 5)))

if (( $(echo "$TOTAL_COST_LOW > 0" | bc -l 2>/dev/null || [ $TOTAL_COST_LOW -gt 0 ]) )); then
    echo
    log_cost "💰 ESTIMATED DAILY COST: $$TOTAL_COST_LOW - $$TOTAL_COST_HIGH"
    MONTHLY_LOW=$(echo "$TOTAL_COST_LOW * 30" | bc -l 2>/dev/null || echo $((TOTAL_COST_LOW * 30)))
    MONTHLY_HIGH=$(echo "$TOTAL_COST_HIGH * 30" | bc -l 2>/dev/null || echo $((TOTAL_COST_HIGH * 30)))
    log_cost "💰 ESTIMATED MONTHLY COST: $$MONTHLY_LOW - $$MONTHLY_HIGH"
    echo
    log_warning "⚠️  Resources are currently BILLABLE!"
    echo "🧹 Run './scripts/cleanup.sh' to clean up resources"
else
    log_success "✅ No expensive resources detected"
fi

echo
log_header "RECOMMENDED ACTIONS"

if (( $(echo "$TOTAL_COST_LOW > 20" | bc -l 2>/dev/null || [ ${TOTAL_COST_LOW%.*} -gt 20 ] 2>/dev/null || false) )); then
    echo "🚨 HIGH COST ALERT: Consider immediate cleanup!"
    echo "   → Run: ./scripts/cleanup.sh --emergency"
elif (( $(echo "$TOTAL_COST_LOW > 0" | bc -l 2>/dev/null || [ ${TOTAL_COST_LOW%.*} -gt 0 ] 2>/dev/null || false) )); then
    echo "⚠️  Active billable resources detected"
    echo "   → Run: ./scripts/cleanup.sh"
    echo "   → Or scale down: az aks nodepool scale --node-count 0"
else
    echo "✅ No immediate action needed"
fi

echo "🔍 For detailed cleanup: see TEARDOWN.md"
echo "📊 Monitor costs: Azure Portal → Cost Management"
echo