#!/bin/bash

# PV Usage Checker Script
# This script checks which deployments/workloads are using a specific PersistentVolume

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}=== $1 ===${NC}"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

# Function to check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq to use this script."
        print_info "Install jq: https://stedolan.github.io/jq/download/"
        exit 1
    fi
}

# Function to validate PV exists
validate_pv() {
    local pv_name=$1
    if ! kubectl get pv "$pv_name" &> /dev/null; then
        print_error "PersistentVolume '$pv_name' not found"
        return 1
    fi
    return 0
}

# Main function to check PV usage
check_pv_usage() {
    local pv_name=$1
    
    print_header "PV Usage Check: $pv_name"
    
    # Validate PV exists
    if ! validate_pv "$pv_name"; then
        return 1
    fi
    
    # Basic PV information
    print_info "Basic PV Information:"
    kubectl get pv "$pv_name" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,NAMESPACE:.spec.claimRef.namespace,CAPACITY:.spec.capacity.storage,STORAGECLASS:.spec.storageClassName,CREATED:.metadata.creationTimestamp
    
    # Get claim information
    local claim_name=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.claimRef.name}' 2>/dev/null)
    local claim_ns=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.claimRef.namespace}' 2>/dev/null)
    
    # Check PV status
    local pv_status=$(kubectl get pv "$pv_name" -o jsonpath='{.status.phase}')
    
    if [ -z "$claim_name" ] || [ "$claim_name" = "null" ]; then
        print_warning "PV '$pv_name' is not bound to any PVC (Status: $pv_status)"
        return 0
    fi
    
    print_success "PV is bound to PVC: $claim_name in namespace: $claim_ns"
    
    # Check if PVC exists
    if ! kubectl get pvc "$claim_name" -n "$claim_ns" &> /dev/null; then
        print_warning "PVC '$claim_name' not found in namespace '$claim_ns'"
        print_warning "This might indicate a dangling PV reference"
        return 0
    fi
    
    # PVC Details
    echo ""
    print_info "PVC Details:"
    kubectl get pvc "$claim_name" -n "$claim_ns" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CAPACITY:.status.capacity.storage,ACCESSMODES:.status.accessModes,STORAGECLASS:.spec.storageClassName,CREATED:.metadata.creationTimestamp
    
    # Find pods using this PVC
    echo ""
    print_info "Searching for pods using PVC '$claim_name'..."
    
    local pods_json=$(kubectl get pods -n "$claim_ns" -o json 2>/dev/null)
    local pods_using_pvc=$(echo "$pods_json" | jq -r --arg pvc "$claim_name" '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name' 2>/dev/null)
    
    if [ -z "$pods_using_pvc" ]; then
        print_warning "No pods found using PVC '$claim_name'"
        print_info "The PVC exists but is not mounted by any pods"
        return 0
    fi
    
    print_success "Found pods using this PVC:"
    
    # Analyze each pod and trace to parent resources
    echo "$pods_using_pvc" | while read -r pod; do
        if [ -n "$pod" ]; then
            analyze_pod "$pod" "$claim_ns" "$claim_name"
        fi
    done
}

# Function to analyze individual pods and trace to parent resources
analyze_pod() {
    local pod_name=$1
    local namespace=$2
    local pvc_name=$3
    
    echo ""
    print_info "Analyzing Pod: $pod_name"
    
    # Get pod details
    local pod_status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)
    local pod_node=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    local pod_created=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
    
    echo "  Status: $pod_status"
    echo "  Node: $pod_node"
    echo "  Created: $pod_created"
    
    # Get owner references
    local owner_json=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0]}' 2>/dev/null)
    
    if [ -z "$owner_json" ] || [ "$owner_json" = "{}" ]; then
        print_warning "  Pod '$pod_name' has no owner (standalone pod)"
        return
    fi
    
    local owner_kind=$(echo "$owner_json" | jq -r '.kind' 2>/dev/null)
    local owner_name=$(echo "$owner_json" | jq -r '.name' 2>/dev/null)
    
    echo "  Immediate Owner: $owner_kind/$owner_name"
    
    # Trace to top-level controller
    case "$owner_kind" in
        "ReplicaSet")
            trace_replicaset "$owner_name" "$namespace"
            ;;
        "StatefulSet")
            echo "  Top-level Controller: StatefulSet/$owner_name"
            get_controller_details "statefulset" "$owner_name" "$namespace"
            ;;
        "DaemonSet")
            echo "  Top-level Controller: DaemonSet/$owner_name"
            get_controller_details "daemonset" "$owner_name" "$namespace"
            ;;
        "Job")
            trace_job "$owner_name" "$namespace"
            ;;
        *)
            echo "  Top-level Controller: $owner_kind/$owner_name"
            ;;
    esac
    
    # Show volume mount details
    show_volume_mounts "$pod_name" "$namespace" "$pvc_name"
}

# Function to trace ReplicaSet to Deployment
trace_replicaset() {
    local rs_name=$1
    local namespace=$2
    
    local deployment_name=$(kubectl get rs "$rs_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
    local deployment_kind=$(kubectl get rs "$rs_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
    
    if [ -n "$deployment_name" ] && [ "$deployment_kind" = "Deployment" ]; then
        echo "  Top-level Controller: Deployment/$deployment_name"
        get_controller_details "deployment" "$deployment_name" "$namespace"
    else
        echo "  Top-level Controller: ReplicaSet/$rs_name"
    fi
}

# Function to trace Job to CronJob
trace_job() {
    local job_name=$1
    local namespace=$2
    
    local cronjob_name=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
    local cronjob_kind=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
    
    if [ -n "$cronjob_name" ] && [ "$cronjob_kind" = "CronJob" ]; then
        echo "  Top-level Controller: CronJob/$cronjob_name"
        get_controller_details "cronjob" "$cronjob_name" "$namespace"
    else
        echo "  Top-level Controller: Job/$job_name"
        get_controller_details "job" "$job_name" "$namespace"
    fi
}

# Function to get controller details
get_controller_details() {
    local controller_type=$1
    local controller_name=$2
    local namespace=$3
    
    case "$controller_type" in
        "deployment")
            local replicas=$(kubectl get deployment "$controller_name" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null)
            local ready_replicas=$(kubectl get deployment "$controller_name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
            echo "    Replicas: $ready_replicas/$replicas"
            ;;
        "statefulset")
            local replicas=$(kubectl get statefulset "$controller_name" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null)
            local ready_replicas=$(kubectl get statefulset "$controller_name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
            echo "    Replicas: $ready_replicas/$replicas"
            ;;
    esac
}

# Function to show volume mount details
show_volume_mounts() {
    local pod_name=$1
    local namespace=$2
    local pvc_name=$3
    
    print_info "  Volume Mount Details:"
    kubectl get pod "$pod_name" -n "$namespace" -o json | jq -r --arg pvc "$pvc_name" '
    .spec.containers[] as $container |
    .spec.volumes[] | select(.persistentVolumeClaim.claimName == $pvc) as $volume |
    $container.volumeMounts[] | select(.name == $volume.name) |
    "    Container: \($container.name) | Mount Path: \(.mountPath) | Volume: \(.name)"'
}

# Function to list all PVs for selection
list_pvs() {
    print_header "Available PersistentVolumes"
    kubectl get pv -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,NAMESPACE:.spec.claimRef.namespace,STORAGECLASS:.spec.storageClassName,CAPACITY:.spec.capacity.storage | head -20
    
    local total_pvs=$(kubectl get pv --no-headers | wc -l)
    if [ "$total_pvs" -gt 19 ]; then
        print_info "Showing first 19 PVs out of $total_pvs total PVs"
        print_info "Use 'kubectl get pv' to see all PVs"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTION] [PV_NAME]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -l, --list          List all PersistentVolumes"
    echo "  -i, --interactive   Interactive mode to select PV"
    echo "  PV_NAME            Check usage for specific PV"
    echo ""
    echo "Examples:"
    echo "  $0 my-pv-name                    # Check specific PV"
    echo "  $0 --list                        # List all PVs"
    echo "  $0 --interactive                 # Interactive selection"
    echo ""
}

# Interactive mode
interactive_mode() {
    print_header "Interactive PV Usage Checker"
    
    echo "Available PersistentVolumes:"
    kubectl get pv -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,STORAGECLASS:.spec.storageClassName --no-headers | nl
    
    echo ""
    read -p "Enter PV name to analyze: " pv_name
    
    if [ -z "$pv_name" ]; then
        print_error "No PV name provided"
        exit 1
    fi
    
    check_pv_usage "$pv_name"
}

# Main script logic
main() {
    # Check prerequisites
    check_kubectl
    check_jq
    
    # Parse command line arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -l|--list)
            list_pvs
            exit 0
            ;;
        -i|--interactive)
            interactive_mode
            exit 0
            ;;
        "")
            print_error "No arguments provided"
            show_usage
            exit 1
            ;;
        *)
            check_pv_usage "$1"
            ;;
    esac
}

# Run main function with all arguments
main "$@"
