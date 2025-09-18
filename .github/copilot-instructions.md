# AI Coding Assistant Instructions

## Project Overview

This is a **GPU time-slicing** project using NVIDIA GPU Operator that supports multiple deployment scenarios: **Azure Kubernetes Service (AKS)** and **on-premises Kubernetes clusters**. The project enables GPU sharing between multiple workloads through time-slicing configuration.

**Core Architecture**: Kubernetes cluster with GPU nodes, NVIDIA GPU Operator for resource management, and ConfigMap-based time-slicing configuration for GPU sharing between multiple workloads.

## Key Architectural Decisions

### GPU Time-Slicing Strategy

- **MIG is explicitly disabled** - Critical for time-slicing to function (`mig.strategy: "none"`)
- Time-slicing replicas are GPU-architecture specific (2-10 replicas per physical GPU)
- Uses ConfigMap-based configuration switching in `kubernetes/gpu-time-slicing-config.yaml`
- Default configuration is "any" with 4 replicas for broad compatibility

### Node Pool Design

- **System pool**: Standard_D2s_v3, `only_critical_addons_enabled: true`, no GPU workloads
- **GPU pool**: GPU VMs with taints (`nvidia.com/gpu=true:NoSchedule`) and labels (`accelerator: nvidia`)
- Auto-scaling enabled on GPU pool (min 0, max configurable) for cost control

### Cost Management Focus

- All scripts emphasize cost awareness (GPU VMs ~$25-100/day)
- Emergency cleanup modes in `scripts/cleanup.sh`
- Auto-scaling down to 0 nodes when idle
- Multiple teardown paths (Terraform destroy vs. manual cleanup)

## Essential File Relationships

### Terraform Stack (`terraform/`)

- `main.tf`: Dual node pool AKS with GPU-specific taints/labels
- `variables.tf`: GPU architecture validation and time-slicing replica mapping
- `outputs.tf`: Connection commands and cluster info for scripts

### Deployment Pipeline

1. **Terraform**: `terraform apply` → AKS with GPU nodepool
2. **GPU Operator**: `scripts/deploy-gpu-operator.sh` → Helm install with `kubernetes/gpu-operator-values.yaml`
3. **Time-slicing**: Auto-applied via `kubernetes/gpu-time-slicing-config.yaml`
4. **Validation**: `scripts/validate-setup.sh` → 8 comprehensive tests

### Critical Configuration Files

- `kubernetes/gpu-operator-values.yaml`: MIG disabled, device plugin time-slicing config
- `kubernetes/gpu-time-slicing-config.yaml`: Architecture-specific replica mappings
- Both files must stay synchronized on MIG strategy and tolerations

## Development Workflows

## Development Workflows

### Azure Deployment Commands

```bash
# Terraform path (recommended)
cd terraform && terraform apply
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw cluster_name)
cd ../scripts && ./deploy-gpu-operator.sh

# Validation
./validate-setup.sh
```

### On-Premises Deployment Commands

```bash
# Label and taint GPU nodes first
kubectl label nodes <gpu-node> accelerator=nvidia
kubectl taint nodes <gpu-node> nvidia.com/gpu=true:NoSchedule

# Deploy GPU Operator
./scripts/deploy-gpu-operator-onprem.sh

# Validation
./validate-setup-onprem.sh
```

### Testing Patterns

- **Azure**: `kubernetes/examples/gpu-test-job.yaml` (nvidia-smi + CUDA sample)
- **Azure**: `kubernetes/examples/multi-gpu-workload.yaml` (3 pods on 1 GPU)
- **On-Premises**: `kubernetes/examples/gpu-test-onprem.yaml` (on-prem GPU test)
- **On-Premises**: `kubernetes/examples/multi-gpu-onprem.yaml` (on-prem time-slicing test)
- Validation suite: 8 automated tests from cluster connectivity to time-slicing functionality

### Cost Control Commands

```bash
# Scale down (stops GPU billing)
az aks nodepool scale --node-count 0 --name gpu

# Emergency cleanup
./scripts/cleanup.sh --emergency

# Terraform teardown
terraform destroy -auto-approve
```

## Project-Specific Conventions

### GPU Configuration Patterns

- All GPU workloads require tolerations for `nvidia.com/gpu=true:NoSchedule`
- Node selector `accelerator: nvidia` for GPU nodes
- Resource requests use `nvidia.com/gpu: 1` (not fractional due to device plugin design)

### Script Architecture

- All scripts use colored logging functions (`log_info`, `log_error`, etc.)
- Prerequisite checking before main operations
- Timeout-based waiting for Kubernetes resources
- Comprehensive error handling with cleanup on failure

### Validation Strategy

- `validate-setup.sh` runs 8 distinct tests with pass/fail counters
- Tests progress from basic (cluster connectivity) to complex (time-slicing functionality)
- Creates temporary workloads and cleans them up automatically

## Integration Points

### Azure Dependencies

- Requires GPU quota in target region (check with `az vm list-usage`)
- Log Analytics workspace for AKS monitoring (auto-created)
- Virtual network with subnet for pod networking

### Kubernetes Dependencies

- Helm 3.x for NVIDIA GPU Operator installation
- NVIDIA device plugin for GPU resource advertising
- ConfigMap hot-reload for time-slicing configuration changes

### External Systems

- NVIDIA NGC Helm repository (`https://helm.ngc.nvidia.com/nvidia`)
- NVIDIA CUDA container images for testing
- Azure Monitor integration for GPU metrics via DCGM Exporter

## Common Issues & Solutions

### GPU Nodes Not Ready

- Check GPU quota: `az vm list-usage --location "East US" --query "[?contains(name.value, 'StandardNC')]"`
- Verify node taints match tolerations in workloads
- Check GPU Operator pod status in `gpu-operator-resources` namespace

### Time-Slicing Not Working

- Ensure MIG is disabled in both `gpu-operator-values.yaml` and `gpu-time-slicing-config.yaml`
- Restart device plugin: `kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset`
- Verify ConfigMap exists: `kubectl get configmap time-slicing-config -n gpu-operator-resources`

### High Costs

- Use `./scripts/cleanup.sh` for guided teardown options
- Scale GPU nodes to 0: `az aks nodepool scale --node-count 0 --name gpu`
- Monitor Azure billing dashboard regularly

## Testing Strategy

When modifying configurations:

1. Run `./scripts/validate-setup.sh` after changes
2. Test with `kubectl apply -f kubernetes/examples/gpu-test-job.yaml`
3. Verify time-slicing with multiple concurrent pods
4. Check cost implications before leaving running

Focus modifications on time-slicing replica counts, GPU VM sizes, and auto-scaling parameters while preserving the core MIG-disabled + tolerations pattern.
