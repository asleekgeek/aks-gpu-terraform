#!/bin/bash

# Deploy comprehensive monitoring for AKS GPU cluster with Prometheus and Grafana
# This script sets up monitoring for GPU time-slicing workloads

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

# Configuration
NAMESPACE="monitoring"
GRAFANA_ADMIN_PASSWORD="admin123"
PROMETHEUS_RETENTION="30d"
PROMETHEUS_STORAGE="50Gi"

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
        log_info "Monitoring will still be deployed but GPU metrics may not be available"
    else
        log_success "Found $GPU_NODES GPU node(s)"
    fi
    
    # Check for GPU Operator
    if ! kubectl get namespace gpu-operator-resources &> /dev/null; then
        log_warning "GPU Operator namespace not found. Deploy GPU Operator first for GPU metrics"
    else
        log_success "GPU Operator namespace found"
    fi
}

# Add Prometheus Helm repository
add_helm_repo() {
    log_info "Adding Prometheus Helm repository..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo update
    
    log_success "Prometheus Helm repository added and updated"
}

# Create monitoring namespace
create_namespace() {
    log_info "Creating monitoring namespace..."
    
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Monitoring namespace created/updated"
}

# Deploy Prometheus + Grafana stack
deploy_prometheus_stack() {
    log_info "Deploying Prometheus + Grafana stack..."
    
    # Deploy kube-prometheus-stack with GPU monitoring optimizations
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace "$NAMESPACE" \
        --set grafana.enabled=true \
        --set grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" \
        --set grafana.persistence.enabled=true \
        --set grafana.persistence.size=10Gi \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.retention="$PROMETHEUS_RETENTION" \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage="$PROMETHEUS_STORAGE" \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=default \
        --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=2Gi \
        --set nodeExporter.enabled=true \
        --set kubeStateMetrics.enabled=true \
        --wait \
        --timeout=600s
    
    log_success "Prometheus + Grafana stack deployed successfully"
}

# Configure DCGM Exporter ServiceMonitor
configure_dcgm_monitoring() {
    log_info "Configuring DCGM Exporter ServiceMonitor for GPU metrics..."
    
    # Create ServiceMonitor for DCGM Exporter
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nvidia-dcgm-exporter
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: nvidia-dcgm-exporter
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  namespaceSelector:
    matchNames:
    - gpu-operator-resources
  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
EOF
    
    log_success "DCGM Exporter ServiceMonitor configured"
}

# Configure Node Exporter for GPU nodes
configure_node_monitoring() {
    log_info "Configuring enhanced node monitoring..."
    
    # Create ServiceMonitor for enhanced node metrics
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: node-exporter-gpu
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: node-exporter
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: node-exporter
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
    relabelings:
    - sourceLabels: [__meta_kubernetes_pod_node_name]
      targetLabel: instance
    - sourceLabels: [__meta_kubernetes_pod_label_accelerator]
      targetLabel: gpu_node
      regex: nvidia
      replacement: "true"
EOF
    
    log_success "Enhanced node monitoring configured"
}

# Wait for monitoring stack to be ready
wait_for_monitoring() {
    log_info "Waiting for monitoring stack to be ready..."
    
    # Wait for Prometheus
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=prometheus \
        -n "$NAMESPACE" \
        --timeout=300s
    
    # Wait for Grafana
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=grafana \
        -n "$NAMESPACE" \
        --timeout=300s
    
    log_success "Monitoring stack is ready"
}

# Display access information
show_access_info() {
    log_info "=== MONITORING ACCESS INFORMATION ==="
    
    echo
    log_info "Grafana Dashboard:"
    echo "  Local access: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-grafana 3000:80"
    echo "  Then open: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: $GRAFANA_ADMIN_PASSWORD"
    
    echo
    log_info "Prometheus Web UI:"
    echo "  Local access: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
    echo "  Then open: http://localhost:9090"
    
    echo
    log_info "AlertManager:"
    echo "  Local access: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-alertmanager 9093:9093"
    echo "  Then open: http://localhost:9093"
    
    echo
    log_info "Recommended Grafana Dashboards to Import:"
    echo "  - NVIDIA DCGM Exporter Dashboard (ID: 12239)"
    echo "  - Kubernetes GPU Monitoring (ID: 14574)"
    echo "  - Node Exporter Full (ID: 1860)"
    echo "  - Kubernetes Cluster Monitoring (ID: 7249)"
    
    echo
    log_info "Custom GPU Dashboard:"
    echo "  Import kubernetes/monitoring/gpu-dashboard.json for AKS-specific GPU metrics"
}

# Verify installation
verify_monitoring() {
    log_info "Verifying monitoring installation..."
    
    # Check Prometheus
    if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus | grep -q Running; then
        log_success "✓ Prometheus is running"
    else
        log_error "✗ Prometheus is not running"
        return 1
    fi
    
    # Check Grafana
    if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=grafana | grep -q Running; then
        log_success "✓ Grafana is running"
    else
        log_error "✗ Grafana is not running"
        return 1
    fi
    
    # Check ServiceMonitors
    if kubectl get servicemonitor nvidia-dcgm-exporter -n "$NAMESPACE" &> /dev/null; then
        log_success "✓ DCGM ServiceMonitor configured"
    else
        log_warning "⚠ DCGM ServiceMonitor not found (GPU Operator may not be deployed)"
    fi
    
    # Check storage
    if kubectl get pvc -n "$NAMESPACE" | grep -q prometheus; then
        log_success "✓ Prometheus storage configured"
    else
        log_warning "⚠ Prometheus storage not found"
    fi
    
    log_success "Monitoring verification completed"
}

# Main execution
main() {
    log_info "=== AKS GPU MONITORING DEPLOYMENT ==="
    log_info "Deploying Prometheus + Grafana for GPU time-slicing monitoring"
    echo
    
    check_prerequisites
    echo
    
    add_helm_repo
    echo
    
    create_namespace
    echo
    
    deploy_prometheus_stack
    echo
    
    configure_dcgm_monitoring
    echo
    
    configure_node_monitoring
    echo
    
    wait_for_monitoring
    echo
    
    verify_monitoring
    echo
    
    show_access_info
    echo
    
    log_success "=== MONITORING DEPLOYMENT COMPLETED ==="
    echo
    log_info "Next steps:"
    echo "  1. Apply GPU alerting rules: kubectl apply -f kubernetes/monitoring/gpu-alerts.yaml"
    echo "  2. Import custom dashboard: kubernetes/monitoring/gpu-dashboard.json"
    echo "  3. Access Grafana and start monitoring your GPU workloads"
    echo "  4. Consider setting up external access via Ingress or LoadBalancer"
}

# Handle script arguments
case "${1:-}" in
    --verify)
        verify_monitoring
        ;;
    --access-info)
        show_access_info
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo "Options:"
        echo "  --verify      Verify monitoring stack status"
        echo "  --access-info Show access information"
        echo "  --help        Show this help"
        echo "  (no option)   Deploy monitoring stack"
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