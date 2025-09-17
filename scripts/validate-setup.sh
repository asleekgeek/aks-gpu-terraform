#!/bin/bash

# Validate AKS GPU setup with time-slicing
# This script performs comprehensive validation of the GPU setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters for tests
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

# Test execution helpers
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo
    log_info "Running test: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if $test_function; then
        log_success "PASSED: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "FAILED: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Check cluster connectivity
test_cluster_connectivity() {
    kubectl cluster-info &> /dev/null
}

# Test 2: Check GPU nodes
test_gpu_nodes() {
    local gpu_nodes
    gpu_nodes=$(kubectl get nodes -l accelerator=nvidia --no-headers 2>/dev/null | wc -l)
    
    if [ "$gpu_nodes" -gt 0 ]; then
        log_info "Found $gpu_nodes GPU node(s)"
        kubectl get nodes -l accelerator=nvidia
        return 0
    else
        log_error "No GPU nodes found"
        return 1
    fi
}

# Test 3: Check GPU Operator installation
test_gpu_operator() {
    local namespace="gpu-operator-resources"
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        log_error "GPU Operator namespace not found"
        return 1
    fi
    
    # Check for GPU Operator pods
    local operator_pods
    operator_pods=$(kubectl get pods -n "$namespace" -l app=gpu-operator --no-headers 2>/dev/null | wc -l)
    
    if [ "$operator_pods" -gt 0 ]; then
        log_info "GPU Operator pods found"
        kubectl get pods -n "$namespace" -l app=gpu-operator
        return 0
    else
        log_error "No GPU Operator pods found"
        return 1
    fi
}

# Test 4: Check device plugin
test_device_plugin() {
    local namespace="gpu-operator-resources"
    
    # Check device plugin pods
    local device_plugin_pods
    device_plugin_pods=$(kubectl get pods -n "$namespace" -l app=nvidia-device-plugin-daemonset --no-headers 2>/dev/null | grep Running | wc -l)
    
    if [ "$device_plugin_pods" -gt 0 ]; then
        log_info "Device plugin pods running: $device_plugin_pods"
        kubectl get pods -n "$namespace" -l app=nvidia-device-plugin-daemonset
        return 0
    else
        log_error "No running device plugin pods found"
        return 1
    fi
}

# Test 5: Check GPU resources
test_gpu_resources() {
    # Check if nodes report GPU resources
    local gpu_capacity
    gpu_capacity=$(kubectl get nodes -l accelerator=nvidia -o jsonpath='{range .items[*]}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | grep -v '^$' | wc -l)
    
    if [ "$gpu_capacity" -gt 0 ]; then
        log_info "GPU resources reported by nodes:"
        kubectl get nodes -l accelerator=nvidia -o custom-columns=NAME:.metadata.name,GPU_CAPACITY:.status.capacity.nvidia\.com/gpu,GPU_ALLOCATABLE:.status.allocatable.nvidia\.com/gpu
        return 0
    else
        log_error "No GPU resources found on nodes"
        return 1
    fi
}

# Test 6: Check time-slicing configuration
test_time_slicing_config() {
    local namespace="gpu-operator-resources"
    
    # Check if time-slicing config exists
    if kubectl get configmap time-slicing-config -n "$namespace" &> /dev/null; then
        log_info "Time-slicing configuration found"
        
        # Show configuration details
        local replicas
        replicas=$(kubectl get configmap time-slicing-config -n "$namespace" -o jsonpath='{.data.any}' | grep -o 'replicas: [0-9]*' | head -1)
        log_info "Configuration: $replicas"
        return 0
    else
        log_error "Time-slicing configuration not found"
        return 1
    fi
}

# Test 7: Test GPU workload
test_gpu_workload() {
    local test_job_name="gpu-validation-test"
    
    log_info "Deploying test GPU workload..."
    
    # Create test job
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $test_job_name
  namespace: default
spec:
  backoffLimit: 2
  template:
    metadata:
      labels:
        app: gpu-validation-test
    spec:
      restartPolicy: Never
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
      nodeSelector:
        accelerator: nvidia
      containers:
        - name: gpu-test
          image: nvidia/cuda:12.2-runtime-ubuntu20.04
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "GPU Test Starting..."
              nvidia-smi -L
              nvidia-smi --query-gpu=name,memory.total --format=csv
              echo "GPU Test Completed Successfully"
          resources:
            requests:
              nvidia.com/gpu: 1
            limits:
              nvidia.com/gpu: 1
EOF

    # Wait for job to complete
    local timeout=180
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local job_status
        job_status=$(kubectl get job "$test_job_name" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
        
        if [ "$job_status" = "Complete" ]; then
            log_info "Test job completed successfully"
            kubectl logs job/"$test_job_name"
            kubectl delete job "$test_job_name" &> /dev/null || true
            return 0
        elif [ "$job_status" = "Failed" ]; then
            log_error "Test job failed"
            kubectl describe job "$test_job_name"
            kubectl logs job/"$test_job_name" || true
            kubectl delete job "$test_job_name" &> /dev/null || true
            return 1
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    log_error "Test job timed out"
    kubectl delete job "$test_job_name" &> /dev/null || true
    return 1
}

# Test 8: Test time-slicing functionality
test_time_slicing_functionality() {
    local deployment_name="time-slicing-test"
    
    log_info "Testing time-slicing with multiple GPU requests..."
    
    # Create deployment with more replicas than physical GPUs
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $deployment_name
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: time-slicing-test
  template:
    metadata:
      labels:
        app: time-slicing-test
    spec:
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
      nodeSelector:
        accelerator: nvidia
      containers:
        - name: gpu-worker
          image: nvidia/cuda:12.2-runtime-ubuntu20.04
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "Time-slicing test starting on pod \$HOSTNAME"
              nvidia-smi -L
              echo "Running for 60 seconds..."
              sleep 60
              echo "Time-slicing test completed on pod \$HOSTNAME"
          resources:
            requests:
              nvidia.com/gpu: 1
            limits:
              nvidia.com/gpu: 1
EOF

    # Wait for pods to be running
    sleep 10
    
    local running_pods
    running_pods=$(kubectl get pods -l app=time-slicing-test --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [ "$running_pods" -ge 2 ]; then
        log_info "Time-slicing working: $running_pods pods running with GPU requests"
        kubectl get pods -l app=time-slicing-test -o wide
        
        # Clean up
        kubectl delete deployment "$deployment_name" &> /dev/null || true
        return 0
    else
        log_error "Time-slicing not working: only $running_pods pod(s) running"
        kubectl describe pods -l app=time-slicing-test
        kubectl delete deployment "$deployment_name" &> /dev/null || true
        return 1
    fi
}

# Show cluster summary
show_cluster_summary() {
    echo
    log_info "=== CLUSTER SUMMARY ==="
    
    echo
    log_info "Kubernetes Cluster Info:"
    kubectl cluster-info
    
    echo
    log_info "GPU Nodes:"
    kubectl get nodes -l accelerator=nvidia -o wide
    
    echo
    log_info "GPU Resources:"
    kubectl describe nodes -l accelerator=nvidia | grep -A 5 -B 5 nvidia.com/gpu
    
    echo
    log_info "GPU Operator Pods:"
    kubectl get pods -n gpu-operator-resources
    
    echo
    log_info "Time-slicing Configuration:"
    kubectl get configmap time-slicing-config -n gpu-operator-resources -o yaml | head -30
}

# Main validation function
main() {
    echo
    log_info "=== AKS GPU VALIDATION SCRIPT ==="
    log_info "This script validates the AKS cluster with GPU time-slicing setup"
    echo
    
    # Run all tests
    run_test "Cluster Connectivity" test_cluster_connectivity
    run_test "GPU Nodes Detection" test_gpu_nodes
    run_test "GPU Operator Installation" test_gpu_operator
    run_test "Device Plugin Status" test_device_plugin
    run_test "GPU Resources Availability" test_gpu_resources
    run_test "Time-slicing Configuration" test_time_slicing_config
    run_test "GPU Workload Execution" test_gpu_workload
    run_test "Time-slicing Functionality" test_time_slicing_functionality
    
    # Show summary
    echo
    log_info "=== VALIDATION SUMMARY ==="
    echo "Tests run: $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All validation tests passed! ✓"
        show_cluster_summary
        
        echo
        log_info "=== NEXT STEPS ==="
        echo "1. Deploy your ML workloads with GPU requests"
        echo "2. Monitor GPU utilization with: kubectl top nodes"
        echo "3. Check GPU metrics with DCGM Exporter"
        echo "4. Test different time-slicing configurations as needed"
        
        exit 0
    else
        log_error "Some validation tests failed! ✗"
        echo
        log_info "Check the error messages above and:"
        echo "1. Ensure GPU Operator is properly deployed"
        echo "2. Verify time-slicing configuration"
        echo "3. Check pod logs for more details"
        echo "4. Run './deploy-gpu-operator.sh' if needed"
        
        exit 1
    fi
}

# Execute main function
main "$@"