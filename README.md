# Azure Kubernetes Service (AKS) with GPU Time-Slicing using NVIDIA GPU Operator

This repository provides a complete Terraform-based solution for setting up an Azure Kubernetes Service (AKS) cluster with GPU-enabled nodes and NVIDIA GPU Operator for GPU time-slicing capabilities.

## 🎯 Overview

This setup enables:

-   Azure AKS cluster with GPU-enabled node pools
-   NVIDIA GPU Operator for GPU resource management
-   GPU time-slicing to share GPUs between multiple workloads
-   Automated deployment using Terraform and Kubernetes manifests

## 📋 Prerequisites

Before you begin, ensure you have the following tools installed:

### Required Tools

-   [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (v2.0+)
-   [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) (v1.0+)
-   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (v1.25+)
-   [Helm](https://helm.sh/docs/intro/install/) (v3.0+)

### Azure Requirements

-   Active Azure subscription
-   Sufficient quota for GPU VMs (Standard_NC series or Standard_ND series)
-   Contributor access to the subscription or resource group

### Verify Prerequisites

```bash
# Check Azure CLI
az --version

# Check Terraform
terraform version

# Check kubectl
kubectl version --client

# Check Helm
helm version
```

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd aks-gpu-terraform
```

### 2. Azure Authentication

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Verify your account
az account show
```

### 3. Configure Variables

```bash
# Copy the example variables file
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit the variables file with your preferred settings
nano terraform/terraform.tfvars
```

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
cd terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### 5. Configure kubectl

```bash
# Get AKS credentials
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw cluster_name)

# Verify connection
kubectl get nodes
```

### 6. Deploy NVIDIA GPU Operator

```bash
# Deploy the GPU Operator
cd ../scripts
./deploy-gpu-operator.sh

# Verify GPU nodes
kubectl get nodes -l accelerator=nvidia
```

### 7. Configure GPU Time-Slicing

```bash
# Apply time-slicing configuration
kubectl apply -f ../kubernetes/gpu-time-slicing-config.yaml

# Restart the GPU Operator DaemonSet
kubectl patch daemonset nvidia-device-plugin-daemonset -n gpu-operator-resources -p '{"spec":{"template":{"metadata":{"annotations":{"date":"'$(date +%s)'"}}}}}' || true
```

## 📁 Repository Structure

    aks-gpu-terraform/
    ├── README.md                          # This file
    ├── .gitignore                         # Git ignore rules
    ├── terraform/                         # Terraform configuration
    │   ├── main.tf                        # Main Terraform configuration
    │   ├── variables.tf                   # Input variables
    │   ├── outputs.tf                     # Output values
    │   ├── versions.tf                    # Provider versions
    │   └── terraform.tfvars.example       # Example variables file
    ├── kubernetes/                        # Kubernetes manifests
    │   ├── gpu-operator-values.yaml       # Helm values for GPU Operator
    │   ├── gpu-time-slicing-config.yaml   # Time-slicing configuration
    │   └── examples/                      # Example workloads
    │       ├── gpu-test-job.yaml          # Simple GPU test
    │       └── multi-gpu-workload.yaml    # Multi-container GPU sharing
    └── scripts/                           # Deployment scripts
        ├── deploy-gpu-operator.sh          # GPU Operator deployment
        ├── validate-setup.sh               # Validation script
        └── cleanup.sh                      # Cleanup script

## ⚙️ Configuration Options

### Terraform Variables

| Variable              | Description                      | Default            | Required |
| --------------------- | -------------------------------- | ------------------ | -------- |
| `resource_group_name` | Name of the Azure resource group | `aks-gpu-rg`       | No       |
| `location`            | Azure region for resources       | `East US`          | No       |
| `cluster_name`        | Name of the AKS cluster          | `aks-gpu-cluster`  | No       |
| `node_count`          | Number of GPU nodes              | `1`                | No       |
| `vm_size`             | VM size for GPU nodes            | `Standard_NC6s_v3` | No       |
| `kubernetes_version`  | Kubernetes version               | `1.28.0`           | No       |

### GPU Time-Slicing Configuration

The time-slicing configuration allows you to specify:

-   Number of GPU replicas per physical GPU
-   Resource sharing strategy
-   GPU memory partitioning

## 🧪 Testing and Validation

### 1. Verify GPU Availability

```bash
# Check GPU nodes
kubectl get nodes -l accelerator=nvidia

# Check GPU resources
kubectl describe nodes -l accelerator=nvidia | grep nvidia.com/gpu
```

### 2. Test GPU Workload

```bash
# Deploy a test GPU job
kubectl apply -f kubernetes/examples/gpu-test-job.yaml

# Check job status
kubectl get jobs gpu-test

# View job logs
kubectl logs job/gpu-test
```

### 3. Test Time-Slicing

```bash
# Deploy multiple GPU workloads
kubectl apply -f kubernetes/examples/multi-gpu-workload.yaml

# Verify workloads are running on the same GPU
kubectl get pods -o wide
```

### 4. Run Validation Script

```bash
# Run comprehensive validation
./scripts/validate-setup.sh
```

## 🔧 Troubleshooting

### Common Issues

1.  **Insufficient GPU Quota**

    ```bash
    # Check quota
    az vm list-usage --location "East US" --query "[?contains(name.value, 'StandardNC')]"

    # Request quota increase through Azure portal
    ```

2.  **GPU Operator Pods Stuck**

    ```bash
    # Check GPU Operator status
    kubectl get pods -n gpu-operator-resources

    # Check node conditions
    kubectl describe nodes -l accelerator=nvidia
    ```

3.  **Time-Slicing Not Working**

    ```bash
    # Verify configuration
    kubectl get configmap time-slicing-config -n gpu-operator-resources -o yaml

    # Restart device plugin
    kubectl delete pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset
    ```

### Logs and Debugging

```bash
# GPU Operator logs
kubectl logs -n gpu-operator-resources -l app=gpu-operator

# Device plugin logs
kubectl logs -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset

# Node feature discovery logs
kubectl logs -n gpu-operator-resources -l app=node-feature-discovery
```

## 💰 Cost Management

### GPU VM Pricing

-   Standard_NC6s_v3: ~$0.90/hour (varies by region)
-   Consider using spot instances for development/testing
-   Implement auto-scaling to minimize costs

### Cost Optimization Tips

```bash
# Scale down GPU nodes when not in use
az aks nodepool scale --cluster-name <cluster-name> --name gpupool --node-count 0 --resource-group <rg-name>

# Scale up when needed
az aks nodepool scale --cluster-name <cluster-name> --name gpupool --node-count 1 --resource-group <rg-name>
```

## 🔒 Security Considerations

-   GPU nodes run privileged containers for GPU access
-   Ensure proper RBAC configuration
-   Use network policies to isolate GPU workloads
-   Regularly update GPU drivers and operator versions

## 📚 Additional Resources

-   [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
-   [Azure AKS GPU Documentation](https://docs.microsoft.com/en-us/azure/aks/gpu-cluster)
-   [Kubernetes GPU Scheduling](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
-   [GPU Time-Slicing Guide](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/gpu-sharing.html)

## 🤝 Contributing

1.  Fork the repository
2.  Create a feature branch
3.  Make your changes
4.  Test thoroughly
5.  Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:

1.  Check the troubleshooting section
2.  Review existing GitHub issues
3.  Create a new issue with detailed information
4.  Include logs and configuration details

* * *

**Note**: This setup creates billable Azure resources. Remember to clean up resources when not in use to avoid unnecessary charges.
