# Azure Kubernetes Service (AKS) with GPU Time-Slicing using NVIDIA GPU Operator

This repository provides a complete Terraform-based solution for setting up an Azure Kubernetes Service (AKS) cluster with GPU-enabled nodes and NVIDIA GPU Operator for GPU time-slicing capabilities.

## 🎯 Overview

This setup enables:

-   Azure AKS cluster with GPU-enabled node pools
-   NVIDIA GPU Operator for GPU resource management
-   GPU time-slicing to share GPUs between multiple workloads
-   Automated deployment using Terraform and Kubernetes manifests

## � Table of Contents

- [Azure Kubernetes Service (AKS) with GPU Time-Slicing using NVIDIA GPU Operator](#azure-kubernetes-service-aks-with-gpu-time-slicing-using-nvidia-gpu-operator)
  - [🎯 Overview](#-overview)
  - [� Table of Contents](#-table-of-contents)
  - [�🚀 Setup Options](#-setup-options)
    - [**☁️ Azure Deployment**](#️-azure-deployment)
    - [**🏢 On-Premises Deployment**](#-on-premises-deployment)
  - [📋 Prerequisites](#-prerequisites)
    - [Required Tools](#required-tools)
    - [Azure Requirements](#azure-requirements)
    - [Verify Prerequisites](#verify-prerequisites)
  - [🚀 Quick Start](#-quick-start)
    - [**⚡ Option A: Azure AKS (Automated)**](#-option-a-azure-aks-automated)
    - [**⚡ Option B: On-Premises (Existing Cluster)**](#-option-b-on-premises-existing-cluster)
    - [**🎛️ What You Get**](#️-what-you-get)
    - [**📚 Detailed Guides**](#-detailed-guides)
  - [📋 Prerequisites](#-prerequisites-1)
  - [📁 Repository Structure](#-repository-structure)
    - [2. Test GPU Workload](#2-test-gpu-workload)
    - [3. Test Time-Slicing](#3-test-time-slicing)
    - [4. Run Validation Script](#4-run-validation-script)
  - [� Monitoring and Observability](#-monitoring-and-observability)
    - [Deploy Monitoring Stack](#deploy-monitoring-stack)
    - [Access Dashboards](#access-dashboards)
    - [GPU Metrics and Alerts](#gpu-metrics-and-alerts)
    - [Troubleshooting Monitoring](#troubleshooting-monitoring)
  - [�🔧 Troubleshooting](#-troubleshooting)
    - [Common Issues](#common-issues)
    - [Logs and Debugging](#logs-and-debugging)
  - [💰 Cost Management \& Cleanup](#-cost-management--cleanup)
    - [Quick Cleanup](#quick-cleanup)
    - [GPU VM Pricing](#gpu-vm-pricing)
    - [Cost Optimization Tips](#cost-optimization-tips)
  - [🧹 Cleanup Options](#-cleanup-options)
  - [🔒 Security Considerations](#-security-considerations)
  - [📚 Additional Resources](#-additional-resources)
    - [**Setup \& Teardown Guides**](#setup--teardown-guides)
    - [**External Documentation**](#external-documentation)
  - [🔄 Setup Method Comparison](#-setup-method-comparison)
  - [🤝 Contributing](#-contributing)
  - [📄 License](#-license)
  - [🆘 Support](#-support)

## �🚀 Setup Options

Choose your preferred setup method:

Get started quickly with the [**Quick Start**](#quick-start) guide, then choose your detailed deployment method:

### **☁️ Azure Deployment**

-   **[Terraform Setup](#azure-deployment-with-terraform)** - Automated infrastructure deployment
-   **[Manual Azure Setup](MANUAL_SETUP.md)** - Step-by-step learning guide

### **🏢 On-Premises Deployment**

-   **[On-Premises Guide](ON_PREMISES_SETUP.md)** - Deploy to existing Kubernetes clusters

All methods provide the same GPU time-slicing capabilities with NVIDIA GPU Operator and comprehensive monitoring.

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

Choose your deployment path and follow the complete process:

### **⚡ Option A: Azure AKS (Automated)**

Complete end-to-end deployment with infrastructure automation:

```bash
# 1. Clone repository
git clone https://github.com/asleekgeek/aks-gpu-terraform.git
cd aks-gpu-terraform

# 2. Azure authentication
az login
az account set --subscription "your-subscription-id"

# 3. Configure Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your settings

# 4. Deploy AKS cluster
cd terraform
terraform init
terraform apply

# 5. Configure kubectl
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw cluster_name)

# 6. Deploy GPU Operator
cd ../scripts
./deploy-gpu-operator.sh

# 7. Deploy monitoring stack
./deploy-monitoring.sh

# 8. Validate deployment
./validate-setup.sh

# 9. Access monitoring dashboards
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000 (admin/admin123)
```

**🎯 Total time: ~20 minutes | Result: Full AKS cluster with GPU time-slicing + monitoring**

### **⚡ Option B: On-Premises (Existing Cluster)**

Deploy to your existing Kubernetes cluster:

```bash
# 1. Clone repository
git clone https://github.com/asleekgeek/aks-gpu-terraform.git
cd aks-gpu-terraform

# 2. Label GPU nodes (replace with your node names)
kubectl label nodes <gpu-node-1> accelerator=nvidia
kubectl label nodes <gpu-node-2> accelerator=nvidia

# 3. Taint GPU nodes (prevent non-GPU workloads)
kubectl taint nodes <gpu-node-1> nvidia.com/gpu=true:NoSchedule
kubectl taint nodes <gpu-node-2> nvidia.com/gpu=true:NoSchedule

# 4. Deploy GPU Operator (on-premises version)
./scripts/deploy-gpu-operator-onprem.sh

# 5. Deploy monitoring stack
./scripts/deploy-monitoring.sh

# 6. Validate deployment
./scripts/validate-setup-onprem.sh

# 7. Access monitoring dashboards
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000 (admin/admin123)
```

**🎯 Total time: ~15 minutes | Result: GPU time-slicing on your cluster + monitoring**

### **🎛️ What You Get**

Both deployment options provide:

✅ **GPU Time-Slicing** - Share GPUs between multiple workloads  
✅ **Enterprise Monitoring** - Prometheus + Grafana with custom GPU dashboards  
✅ **Proactive Alerts** - 15+ GPU health and performance alerts  
✅ **Cost Optimization** - Track GPU utilization and idle time  
✅ **Production Ready** - Comprehensive validation and troubleshooting  

### **📚 Detailed Guides**

-   **Azure Deep Dive**: Continue reading this README for detailed Azure setup
-   **On-Premises Deep Dive**: See [ON_PREMISES_SETUP.md](ON_PREMISES_SETUP.md) for complete on-premises guide
-   **Manual Setup**: See [MANUAL_SETUP.md](MANUAL_SETUP.md) for step-by-step learning

* * *

## 📋 Prerequisites

## 📁 Repository Structure

    aks-gpu-terraform/
    ├── README.md                          # This file (Azure setup overview)
    ├── LICENSE                            # MIT License
    ├── MANUAL_SETUP.md                    # Manual Azure step-by-step setup guide  
    ├── ON_PREMISES_SETUP.md               # On-premises Kubernetes setup guide
    ├── GPU_COMPATIBILITY.md               # GPU compatibility matrix
    ├── TEARDOWN.md                        # Cleanup and teardown guide
    ├── .gitignore                         # Git ignore rules
    ├── terraform/                         # Terraform configuration (Azure only)
    │   ├── main.tf                        # Main Terraform configuration
    │   ├── variables.tf                   # Input variables
    │   ├── outputs.tf                     # Output values
    │   ├── versions.tf                    # Provider versions
    │   └── terraform.tfvars.example       # Example variables file
        ├── kubernetes/                        # Kubernetes manifests (all deployments)
        │   ├── gpu-operator-values.yaml       # Helm values for GPU Operator
        │   ├── gpu-time-slicing-config.yaml   # Time-slicing configuration
        │   ├── monitoring/                     # Monitoring and observability
        │   │   ├── gpu-dashboard.json          # Custom Grafana GPU dashboard
        │   │   └── gpu-alerts.yaml             # PrometheusRule for GPU alerts
        │   └── examples/                      # Example workloads
        │       ├── gpu-test-job.yaml          # Simple GPU test (Azure)
        │       ├── multi-gpu-workload.yaml    # Multi-container GPU sharing (Azure)
        │       ├── gpu-test-onprem.yaml       # Simple GPU test (on-premises)
        │       └── multi-gpu-onprem.yaml      # Multi-container GPU sharing (on-premises)
        └── scripts/                           # Deployment scripts
            ├── deploy-gpu-operator.sh          # GPU Operator deployment (Azure)
            ├── deploy-gpu-operator-onprem.sh   # GPU Operator deployment (on-premises)
            ├── deploy-monitoring.sh            # Monitoring stack deployment (Prometheus/Grafana)
            ├── validate-setup.sh               # Validation script (includes monitoring checks)
            ├── validate-setup-onprem.sh        # On-premises validation script
            └── cleanup.sh                      # Cleanup script (Azure)

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

## � Monitoring and Observability

Monitor your GPU workloads and cluster health with Prometheus, Grafana, and DCGM Exporter.

### Deploy Monitoring Stack

Deploy a complete monitoring solution for GPU time-slicing workloads:

```bash
# Deploy Prometheus, Grafana, and GPU monitoring
./scripts/deploy-monitoring.sh

# Check deployment status
kubectl get pods -n monitoring
```

**What gets deployed:**

-   **Prometheus** - Metrics collection and storage
-   **Grafana** - Visualization dashboards  
-   **DCGM Exporter** - NVIDIA GPU metrics collection
-   **Custom GPU Dashboard** - Pre-configured GPU monitoring
-   **GPU Alerts** - Proactive notifications for GPU issues

### Access Dashboards

```bash
# Access Grafana (default: admin/prom-operator)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open dashboards
open http://localhost:3000  # Grafana
open http://localhost:9090  # Prometheus
```

**Pre-configured Dashboards:**

-   **GPU Overview** - Multi-GPU cluster view
-   **GPU Utilization** - Real-time GPU usage metrics
-   **GPU Time-Slicing Efficiency** - Pod density and sharing metrics
-   **GPU Health** - Temperature, power, and memory monitoring

### GPU Metrics and Alerts

**Key GPU Metrics Available:**

```bash
# View raw GPU metrics
kubectl port-forward -n gpu-operator-resources svc/nvidia-dcgm-exporter 9400:9400
curl http://localhost:9400/metrics | grep DCGM_FI_DEV
```

**Critical Metrics:**

-   `DCGM_FI_DEV_GPU_UTIL` - GPU utilization percentage
-   `DCGM_FI_DEV_GPU_TEMP` - GPU temperature (Celsius)
-   `DCGM_FI_DEV_FB_USED` - GPU memory usage (MB)
-   `DCGM_FI_DEV_POWER_USAGE` - Power consumption (Watts)

**Automated Alerts:**

-   🔥 **High Temperature** (>80°C) - Critical GPU thermal alerts
-   ⚡ **High Utilization** (>90%) - Performance bottleneck warnings
-   💾 **Memory Pressure** (>85%) - GPU memory exhaustion alerts
-   🔋 **Power Consumption** (>300W) - Power efficiency monitoring
-   📊 **Time-Slicing Efficiency** - Under/over-utilization alerts

### Troubleshooting Monitoring

```bash
# Check DCGM Exporter status
kubectl get pods -n gpu-operator-resources | grep dcgm

# Verify metrics collection
kubectl logs -n gpu-operator-resources -l app=nvidia-dcgm-exporter

# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Navigate to Status -> Targets in Prometheus UI

# Restart DCGM Exporter if needed
kubectl delete pods -n gpu-operator-resources -l app=nvidia-dcgm-exporter
```

**Dashboard Import:**
If you need to manually import the GPU dashboard:

1.  Download `kubernetes/monitoring/gpu-dashboard.json`
2.  In Grafana: + → Import → Upload JSON file
3.  Configure Prometheus datasource if prompted

## �🔧 Troubleshooting

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

## 💰 Cost Management & Cleanup

> ⚠️ **IMPORTANT**: GPU VMs are expensive! Always clean up when done.

### Quick Cleanup

```bash
# Emergency cleanup - stops all billing immediately
./scripts/cleanup.sh --emergency

# Interactive cleanup with options
./scripts/cleanup.sh
```

### GPU VM Pricing

-   Standard_NC6s_v3: ~$0.90-2.70/hour (varies by region and Azure plan)
-   **Daily cost**: $21-65 per GPU node
-   **Monthly cost**: $648-1,944 per GPU node
-   Consider using spot instances for development/testing

### Cost Optimization Tips

```bash
# Scale down GPU nodes when not in use
az aks nodepool scale --cluster-name <cluster-name> --name gpupool --node-count 0 --resource-group <rg-name>

# Scale up when needed
az aks nodepool scale --cluster-name <cluster-name> --name gpupool --node-count 1 --resource-group <rg-name>

# Complete teardown (Terraform)
cd terraform/
terraform destroy -auto-approve

# Complete teardown (Manual setup)
./scripts/cleanup.sh --manual
```

For detailed teardown instructions, see **[TEARDOWN.md](TEARDOWN.md)**.

## 🧹 Cleanup Options

| Method                             | Speed   | Safety | Use Case                         |
| ---------------------------------- | ------- | ------ | -------------------------------- |
| `./scripts/cleanup.sh`             | Fast    | High   | Interactive with confirmations   |
| `terraform destroy`                | Medium  | High   | Terraform-managed resources only |
| Azure Portal                       | Slow    | Medium | Visual confirmation              |
| `./scripts/cleanup.sh --emergency` | Fastest | Low    | Stop billing immediately         |

> 💡 **Pro Tip**: Set up Azure Budget alerts to avoid unexpected charges!

## 🔒 Security Considerations

-   GPU nodes run privileged containers for GPU access
-   Ensure proper RBAC configuration
-   Use network policies to isolate GPU workloads
-   Regularly update GPU drivers and operator versions

## 📚 Additional Resources

### **Setup & Teardown Guides**

-   **[Manual Setup Guide](MANUAL_SETUP.md)** - Step-by-step Azure manual deployment
-   **[On-Premises Setup Guide](ON_PREMISES_SETUP.md)** - Deploy to existing Kubernetes clusters
-   **[Complete Teardown Guide](TEARDOWN.md)** - Comprehensive cleanup instructions
-   **[GPU Compatibility Matrix](GPU_COMPATIBILITY.md)** - Complete GPU support guide

### **External Documentation**

-   [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
-   [Azure AKS GPU Documentation](https://docs.microsoft.com/en-us/azure/aks/gpu-cluster)
-   [Kubernetes GPU Scheduling](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
-   [GPU Time-Slicing Guide](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/gpu-sharing.html)

## 🔄 Setup Method Comparison

| Aspect               | Terraform (This Guide)     | [Manual Setup](MANUAL_SETUP.md) | [On-Premises](ON_PREMISES_SETUP.md) |
| -------------------- | -------------------------- | ------------------------------- | ----------------------------------- |
| **Infrastructure**   | Azure AKS                  | Azure AKS                       | Existing Kubernetes                 |
| **Time to Deploy**   | 15-20 minutes              | 30-45 minutes                   | 20-30 minutes                       |
| **Time to Cleanup**  | 2-5 minutes                | 5-10 minutes                    | 5-10 minutes                        |
| **Reproducibility**  | ✅ Fully automated          | ⚠️ Manual steps each time       | ✅ Scriptable                        |
| **Learning Value**   | Medium                     | ✅ High - understand each step   | ✅ High - K8s focused                |
| **Production Ready** | ✅ Infrastructure as Code   | ✅ Same end result               | ✅ Enterprise ready                  |
| **Customization**    | Template-based             | ✅ Full control                  | ✅ Full control                      |
| **Cost Control**     | ✅ Easy `terraform destroy` | Manual resource tracking        | Hardware owned                      |
| **Best For**         | Azure production, teams    | Learning Azure, troubleshooting | On-prem, edge, existing clusters    |

**Recommendations**: 

-   **Azure Cloud**: Start with [Manual Setup](MANUAL_SETUP.md) to learn, then use Terraform for production
-   **On-Premises**: Use [On-Premises Setup](ON_PREMISES_SETUP.md) for existing Kubernetes infrastructure

> 🧹 **Cleanup Reminder**: Use appropriate cleanup methods for your deployment type!

## 🤝 Contributing

1.  Fork the repository
2.  Create a feature branch
3.  Make your changes
4.  Test thoroughly
5.  Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For issues and questions:

1.  Check the troubleshooting section
2.  Review existing GitHub issues
3.  Create a new issue with detailed information
4.  Include logs and configuration details

* * *

**Note**: This setup creates billable Azure resources. Remember to clean up resources when not in use to avoid unnecessary charges.
