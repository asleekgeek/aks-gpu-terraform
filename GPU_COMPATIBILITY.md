# GPU Compatibility Guide

This setup is designed to work with **any Azure GPU VM configuration**, with special optimization for **non-MIG scenarios**. Here's the comprehensive compatibility matrix:

## ✅ **Fully Compatible GPU Types**

### **Non-MIG GPUs (Primary Target)**

-   ✅ **Tesla K80** (Kepler) - NC6, NC12, NC24
-   ✅ **Tesla M60** (Maxwell) - NV6, NV12, NV24  
-   ✅ **Tesla P40** (Pascal) - ND6s, ND12s, ND24s
-   ✅ **Tesla P100** (Pascal) - NC6s_v2, NC12s_v2, NC24s_v2
-   ✅ **Tesla V100** (Volta) - NC6s_v3, NC12s_v3, NC24s_v3, ND40rs_v2
-   ✅ **Tesla T4** (Turing) - NC4as_T4_v3, NC8as_T4_v3, NC16as_T4_v3, NC64as_T4_v3
-   ✅ **Tesla A100** (Ampere) in non-MIG mode - ND96asr_v4, ND96amsr_A100_v4
-   ✅ **H100** (Hopper) in non-MIG mode - Future Azure VM sizes

### **MIG-Capable GPUs in Non-MIG Mode**

-   ✅ **A100** with MIG disabled (recommended for time-slicing)
-   ✅ **H100** with MIG disabled (recommended for time-slicing)

## 🔧 **Configuration Matrix**

| GPU Family | Architecture | Time-Slicing Replicas | Memory per Slice           | Use Case             |
| ---------- | ------------ | --------------------- | -------------------------- | -------------------- |
| Tesla K80  | Kepler       | 2                     | ~6GB                       | Light ML workloads   |
| Tesla M60  | Maxwell      | 2                     | ~4GB                       | Graphics/VDI         |
| Tesla P40  | Pascal       | 4                     | ~6GB                       | Training/Inference   |
| Tesla P100 | Pascal       | 4                     | ~4GB                       | HPC/Training         |
| Tesla V100 | Volta        | 6                     | ~2.7GB                     | Heavy ML/Training    |
| Tesla T4   | Turing       | 4                     | ~4GB                       | Inference optimized  |
| Tesla A100 | Ampere       | 8                     | ~5GB (40GB) / ~10GB (80GB) | Large scale ML       |
| H100       | Hopper       | 10                    | ~8GB                       | Transformer training |

## 🚀 **Setup Instructions by GPU Type**

### **For Tesla V100 (Default - NC6s_v3)**

```bash
# terraform/terraform.tfvars
gpu_vm_size = "Standard_NC6s_v3"
gpu_architecture = "volta"
```

### **For Tesla A100 (ND96asr_v4)**

```bash
# terraform/terraform.tfvars
gpu_vm_size = "Standard_ND96asr_v4"
gpu_architecture = "ampere"
```

Apply configuration:

```bash
kubectl patch configmap time-slicing-config -n gpu-operator-resources --patch '{"data":{"default":"ampere"}}'
```

### **For Tesla T4 (NC4as_T4_v3)**

```bash
# terraform/terraform.tfvars
gpu_vm_size = "Standard_NC4as_T4_v3"
gpu_architecture = "turing"
```

Apply configuration:

```bash
kubectl patch configmap time-slicing-config -n gpu-operator-resources --patch '{"data":{"default":"turing"}}'
```

### **For Legacy Tesla K80 (NC6)**

```bash
# terraform/terraform.tfvars
gpu_vm_size = "Standard_NC6"
gpu_architecture = "kepler"
```

Apply configuration:

```bash
kubectl patch configmap time-slicing-config -n gpu-operator-resources --patch '{"data":{"default":"kepler"}}'
```

## ⚙️ **MIG vs Time-Slicing Decision Matrix**

| Scenario                          | Recommendation  | Reason                                         |
| --------------------------------- | --------------- | ---------------------------------------------- |
| **Multiple small ML models**      | ✅ Time-Slicing  | Better resource utilization, easier management |
| **Batch inference workloads**     | ✅ Time-Slicing  | Dynamic sharing, auto-scaling                  |
| **Development/Testing**           | ✅ Time-Slicing  | Flexible, cost-effective                       |
| **Strict isolation required**     | 🔄 Consider MIG | Hardware-level isolation                       |
| **Large memory per workload**     | 🔄 Consider MIG | Guaranteed memory allocation                   |
| **Legacy GPUs (K80, P100, V100)** | ✅ Time-Slicing  | MIG not available                              |

## 🔧 **Switching Configurations**

### **Change Time-Slicing Density:**

```bash
# For development (more slices)
kubectl patch configmap time-slicing-config -n gpu-operator-resources --patch '{"data":{"default":"dev-high-density"}}'

# For production (fewer slices)
kubectl patch configmap time-slicing-config -n gpu-operator-resources --patch '{"data":{"default":"prod-conservative"}}'

# Restart device plugin
kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset
```

### **Enable MIG (for A100/H100 only):**

```bash
# Update ClusterPolicy
kubectl patch clusterpolicy cluster-policy --patch '{"spec":{"mig":{"strategy":"single"}}}'

# Update GPU Operator
helm upgrade gpu-operator nvidia/gpu-operator -n gpu-operator-resources --set migManager.enabled=true
```

## 🚨 **Important Notes**

### **Time-Slicing Limitations:**

-   ⚠️ **No memory isolation** - processes share GPU memory
-   ⚠️ **Cooperative scheduling** - relies on workload cooperation
-   ⚠️ **Best for I/O bound workloads** - compute-heavy tasks may see performance impact

### **Azure-Specific Considerations:**

-   ✅ **All NC/ND/NV series supported**
-   ✅ **Auto-scaling works** with any GPU VM size
-   ⚠️ **Quota limits** vary by region and subscription
-   💰 **Cost scales** with VM size (K80 &lt; T4 &lt; V100 &lt; A100 &lt; H100)

### **Driver Compatibility:**

-   ✅ **NVIDIA Driver 535+** supports all current Azure GPU VMs
-   ✅ **CUDA 12.2+** compatible with all architectures
-   ✅ **GPU Operator** handles driver installation automatically

## 🧪 **Testing Different Configurations**

Use the validation script to test any configuration:

```bash
./scripts/validate-setup.sh
```

For specific GPU architecture testing:

```bash
# Test with different slice configurations
kubectl apply -f kubernetes/examples/multi-gpu-workload.yaml

# Monitor GPU utilization
kubectl top nodes
nvidia-smi dmon -s u
```

This setup provides maximum flexibility across Azure's entire GPU portfolio while optimizing for the most common use case: **non-MIG time-slicing for cost-effective ML workloads**.
