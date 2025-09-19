# 🧹 Complete Teardown Guide

> ⚠️ **CRITICAL**: GPU VMs are expensive! This guide helps you clean up ALL billable resources quickly.

## � Table of Contents

- [🧹 Complete Teardown Guide](#-complete-teardown-guide)
  - [� Table of Contents](#-table-of-contents)
  - [�🚨 Quick Emergency Cleanup](#-quick-emergency-cleanup)
  - [💰 Cost Impact](#-cost-impact)
  - [🎯 Cleanup Methods](#-cleanup-methods)
    - [Method 1: Automated Script (Recommended)](#method-1-automated-script-recommended)
    - [Method 2: Terraform Cleanup](#method-2-terraform-cleanup)
    - [Method 3: Manual Azure CLI Cleanup](#method-3-manual-azure-cli-cleanup)
  - [🔍 Verification Steps](#-verification-steps)
    - [1. Check Resource Groups](#1-check-resource-groups)
    - [2. Check Expensive Resources](#2-check-expensive-resources)
    - [3. Verify Billing Impact](#3-verify-billing-impact)
  - [🎛️ Selective Cleanup Options](#️-selective-cleanup-options)
    - [Keep AKS, Remove GPU Workloads Only](#keep-aks-remove-gpu-workloads-only)
    - [Remove GPU Nodes, Keep Cluster](#remove-gpu-nodes-keep-cluster)
  - [🚨 Common Cleanup Issues](#-common-cleanup-issues)
    - [Issue: "Resource group not found"](#issue-resource-group-not-found)
    - [Issue: "Resources still exist after group deletion"](#issue-resources-still-exist-after-group-deletion)
    - [Issue: "Terraform state locked"](#issue-terraform-state-locked)
    - [Issue: "Cannot delete AKS - nodes still exist"](#issue-cannot-delete-aks---nodes-still-exist)
  - [📊 Monitoring and Alerts](#-monitoring-and-alerts)
    - [Set Up Cost Alerts](#set-up-cost-alerts)
    - [Daily Resource Check](#daily-resource-check)
  - [🛡️ Prevention Best Practices](#️-prevention-best-practices)
  - [🎯 Complete Cleanup Checklist](#-complete-cleanup-checklist)
  - [🆘 Emergency Contacts](#-emergency-contacts)

## �🚨 Quick Emergency Cleanup

If you need to stop billing **immediately**:

```bash
# Run the automated cleanup script
./scripts/cleanup.sh --emergency

# Or delete everything manually
az group list --query "[?contains(name, 'aks') || contains(name, 'gpu')].name" -o tsv | xargs -I {} az group delete --name {} --yes --no-wait
```

## 💰 Cost Impact

| Resource Type            | Hourly Cost    | Daily Cost    | Monthly Cost   |
| ------------------------ | -------------- | ------------- | -------------- |
| Standard_NC6s_v3 (1 GPU) | $0.90-2.70     | $21.60-64.80  | $648-1,944     |
| AKS Management           | $0.10          | $2.40         | $72            |
| Storage & Networking     | $0.05-0.20     | $1.20-4.80    | $36-144        |
| **TOTAL per node**       | **$1.05-3.00** | **$25.20-72** | **$756-2,160** |

> 💡 **With 3 GPU nodes**: You could save **$75-216 per day** by cleaning up!

## 🎯 Cleanup Methods

### Method 1: Automated Script (Recommended)

```bash
# Interactive cleanup with cost warnings
./scripts/cleanup.sh

# Specific cleanup modes
./scripts/cleanup.sh --terraform    # Terraform-managed resources
./scripts/cleanup.sh --manual      # Manually created resources
./scripts/cleanup.sh --emergency   # Everything with 'aks' or 'gpu' in name
```

### Method 2: Terraform Cleanup

```bash
cd terraform/
terraform destroy -auto-approve
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Method 3: Manual Azure CLI Cleanup

```bash
# Quick resource group deletion
RESOURCE_GROUP="aks-gpu-manual-rg"  # or your RG name
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
```

## 🔍 Verification Steps

### 1. Check Resource Groups

```bash
# List all resource groups with AKS/GPU
az group list --query "[?contains(name, 'aks') || contains(name, 'gpu') || contains(name, 'MC_')].{Name:name, Location:location, State:properties.provisioningState}" --output table
```

### 2. Check Expensive Resources

```bash
# Find remaining GPU/AKS resources
az resource list --query "[?(type=='Microsoft.ContainerService/managedClusters' || contains(type, 'Compute/virtualMachines') || contains(type, 'Compute/virtualMachineScaleSets'))].{Name:name, Type:type, ResourceGroup:resourceGroup, Location:location}" --output table
```

### 3. Verify Billing Impact

```bash
# Check current subscription costs (requires permissions)
az consumption usage list --top 10 --output table 2>/dev/null || echo "💡 Check Azure portal for billing details"
```

## 🎛️ Selective Cleanup Options

### Keep AKS, Remove GPU Workloads Only

```bash
# Remove only GPU-specific components
kubectl delete namespace gpu-operator-resources gpu-workloads --ignore-not-found=true
helm uninstall gpu-operator -n gpu-operator-resources --ignore-not-found=true

# Scale down GPU node pool to 0 (stops VM billing)
az aks nodepool update \
    --resource-group "your-rg" \
    --cluster-name "your-cluster" \
    --name "gpunodepool" \
    --min-count 0 \
    --max-count 0 \
    --node-count 0
```

### Remove GPU Nodes, Keep Cluster

```bash
# Delete entire GPU node pool
az aks nodepool delete \
    --resource-group "your-rg" \
    --cluster-name "your-cluster" \
    --name "gpunodepool" \
    --no-wait
```

## 🚨 Common Cleanup Issues

### Issue: "Resource group not found"

```bash
# Check if resources moved to managed resource groups
az resource list --query "[?contains(resourceGroup, 'MC_')].{Name:name, ResourceGroup:resourceGroup}" --output table
```

### Issue: "Resources still exist after group deletion"

```bash
# Some resources may be in other subscriptions or regions
az account list --query "[].{Name:name, SubscriptionId:id, State:state}" --output table
az account set --subscription "other-subscription-id"
# Repeat cleanup
```

### Issue: "Terraform state locked"

```bash
# Force unlock (use carefully)
cd terraform/
terraform force-unlock <lock-id>
terraform destroy -auto-approve
```

### Issue: "Cannot delete AKS - nodes still exist"

```bash
# Force delete cluster policy first
kubectl delete clusterpolicy cluster-policy --ignore-not-found=true

# Then force delete cluster
az aks delete --resource-group "rg-name" --name "cluster-name" --yes --no-wait
```

## 📊 Monitoring and Alerts

### Set Up Cost Alerts

```bash
# Create budget alert for $50/month
az consumption budget create \
    --budget-name "GPU-Development-Budget" \
    --amount 50 \
    --category "Cost" \
    --time-grain "Monthly" \
    --start-date $(date -u +%Y-%m-01T00:00:00Z) \
    --end-date $(date -u -d "+1 year" +%Y-%m-01T00:00:00Z)
```

### Daily Resource Check

```bash
# Add to your daily routine or cron job
#!/bin/bash
echo "🔍 Daily Azure Resource Check - $(date)"
echo "GPU VMs: $(az vm list --query "length([?contains(hardwareProfile.vmSize, 'NC')])" -o tsv)"
echo "AKS Clusters: $(az aks list --query "length([*])" -o tsv)"
echo "💰 Estimated daily cost: \$$(az consumption usage list --top 1 --query "[0].pretaxCost" -o tsv 2>/dev/null || echo "Check portal")"
```

## 🛡️ Prevention Best Practices

1.  **Always set auto-shutdown**:
    ```bash
    # Set node pool to auto-scale to 0 when idle
    az aks update --resource-group "rg" --name "cluster" --cluster-autoscaler-profile scale-down-delay-after-add=1m,scale-down-unneeded-time=1m
    ```

2.  **Use development subscriptions** with spending limits

3.  **Tag all resources** for easy identification:
    ```bash
    az group create --name "my-rg" --location "eastus" --tags "Environment=Development" "Project=GPU-ML" "Owner=yourname"
    ```

4.  **Set up automatic cleanup** with Azure Automation or GitHub Actions

## 🎯 Complete Cleanup Checklist

-   [ ] Kubernetes GPU workloads removed
-   [ ] NVIDIA GPU Operator uninstalled
-   [ ] GPU node pools deleted
-   [ ] AKS cluster deleted (or scaled to 0)
-   [ ] Virtual networks deleted
-   [ ] Log Analytics workspaces deleted
-   [ ] Resource groups deleted
-   [ ] kubectl contexts removed
-   [ ] Terraform state cleaned
-   [ ] Azure billing verified (no unexpected charges)
-   [ ] Cost alerts configured for future

## 🆘 Emergency Contacts

If you notice unexpected high charges:

1.  **Immediate**: Run `./scripts/cleanup.sh --emergency`
2.  **Azure Support**: Create billing support ticket
3.  **Cost Management**: Use Azure Cost Management + Billing portal
4.  **Spending Limit**: Enable on development subscriptions

* * *

> 💡 **Remember**: It's always cheaper to recreate resources than to leave them running!
>
> 🎯 **Best Practice**: Clean up immediately after testing, recreate when needed.
