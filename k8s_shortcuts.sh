#!/bin/bash

# Kubernetes Shell Shortcuts and Utilities
# Add this to your ~/.bashrc, ~/.zshrc, or ~/.profile

# Basic kubectl alias
alias k='kubectl'

# Enable kubectl completion for the alias
if command -v kubectl &> /dev/null; then
    source <(kubectl completion bash)
    complete -F __start_kubectl k
fi

# Context Management
# List all contexts
alias kctx='kubectl config get-contexts'

# Get current context
alias kctx-current='kubectl config current-context'

# Switch context function
kctx-switch() {
    if [ -z "$1" ]; then
        echo "Usage: kctx-switch <context-name>"
        echo "Available contexts:"
        kubectl config get-contexts --output=name
        return 1
    fi
    kubectl config use-context "$1"
    echo "Switched to context: $1"
}

# Interactive context switcher
kctx-menu() {
    local contexts=$(kubectl config get-contexts --output=name)
    local current=$(kubectl config current-context)
    
    echo "Current context: $current"
    echo "Available contexts:"
    
    select context in $contexts; do
        if [ -n "$context" ]; then
            kubectl config use-context "$context"
            echo "Switched to context: $context"
            break
        else
            echo "Invalid selection"
        fi
    done
}

# Namespace Management
# List all namespaces
alias kns='kubectl get namespaces'

# Get current namespace
kns-current() {
    kubectl config view --minify --output 'jsonpath={..namespace}' || echo "default"
}

# Set namespace
kns-set() {
    if [ -z "$1" ]; then
        echo "Usage: kns-set <namespace>"
        echo "Available namespaces:"
        kubectl get namespaces --output=name | cut -d/ -f2
        return 1
    fi
    kubectl config set-context --current --namespace="$1"
    echo "Namespace set to: $1"
}

# Interactive namespace switcher
kns-menu() {
    local namespaces=$(kubectl get namespaces --output=name | cut -d/ -f2)
    local current=$(kns-current)
    
    echo "Current namespace: $current"
    echo "Available namespaces:"
    
    select ns in $namespaces; do
        if [ -n "$ns" ]; then
            kubectl config set-context --current --namespace="$ns"
            echo "Namespace set to: $ns"
            break
        else
            echo "Invalid selection"
        fi
    done
}

# Pod Management
# List pods in current namespace
alias kpods='kubectl get pods'
alias kp='kubectl get pods'

# List pods in all namespaces
alias kpods-all='kubectl get pods --all-namespaces'
alias kpa='kubectl get pods --all-namespaces'

# Get pod details
kpod() {
    if [ -z "$1" ]; then
        echo "Usage: kpod <pod-name>"
        return 1
    fi
    kubectl get pod "$1" -o wide
}

# Describe pod
kpod-desc() {
    if [ -z "$1" ]; then
        echo "Usage: kpod-desc <pod-name>"
        return 1
    fi
    kubectl describe pod "$1"
}

# Pod logs
klogs() {
    if [ -z "$1" ]; then
        echo "Usage: klogs <pod-name> [container-name]"
        return 1
    fi
    if [ -n "$2" ]; then
        kubectl logs "$1" -c "$2" -f
    else
        kubectl logs "$1" -f
    fi
}

# Previous pod logs
klogs-prev() {
    if [ -z "$1" ]; then
        echo "Usage: klogs-prev <pod-name> [container-name]"
        return 1
    fi
    if [ -n "$2" ]; then
        kubectl logs "$1" -c "$2" --previous
    else
        kubectl logs "$1" --previous
    fi
}

# Execute into pod
kexec() {
    if [ -z "$1" ]; then
        echo "Usage: kexec <pod-name> [container-name] [command]"
        return 1
    fi
    
    local pod="$1"
    local container="$2"
    local command="${3:-/bin/bash}"
    
    if [ -n "$container" ] && [ "$container" != "/bin/bash" ] && [ "$container" != "/bin/sh" ]; then
        kubectl exec -it "$pod" -c "$container" -- "$command"
    else
        # If second argument looks like a command, use it as command
        if [ "$container" = "/bin/bash" ] || [ "$container" = "/bin/sh" ] || [ -z "$container" ]; then
            command="${container:-/bin/bash}"
            kubectl exec -it "$pod" -- "$command"
        else
            kubectl exec -it "$pod" -c "$container" -- "$command"
        fi
    fi
}

# Service Management
alias ksvc='kubectl get services'
alias kservices='kubectl get services'

# Deployment Management
alias kdep='kubectl get deployments'
alias kdeployments='kubectl get deployments'

# Scale deployment
kscale() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: kscale <deployment-name> <replicas>"
        return 1
    fi
    kubectl scale deployment "$1" --replicas="$2"
}

# ConfigMap and Secret Management
alias kcm='kubectl get configmaps'
alias ksecrets='kubectl get secrets'

# Node Management
alias knodes='kubectl get nodes'
alias knode='kubectl get nodes -o wide'

# Events
alias kevents='kubectl get events --sort-by=.metadata.creationTimestamp'

# Resource Management
# Get all resources
kall() {
    local namespace=""
    if [ "$1" = "-A" ] || [ "$1" = "--all-namespaces" ]; then
        namespace="--all-namespaces"
    fi
    
    echo "=== PODS ==="
    kubectl get pods $namespace
    echo -e "\n=== SERVICES ==="
    kubectl get services $namespace
    echo -e "\n=== DEPLOYMENTS ==="
    kubectl get deployments $namespace
    echo -e "\n=== CONFIGMAPS ==="
    kubectl get configmaps $namespace
    echo -e "\n=== SECRETS ==="
    kubectl get secrets $namespace
}

# Delete pod
kdel-pod() {
    if [ -z "$1" ]; then
        echo "Usage: kdel-pod <pod-name>"
        return 1
    fi
    kubectl delete pod "$1"
}

# Force delete pod
kdel-pod-force() {
    if [ -z "$1" ]; then
        echo "Usage: kdel-pod-force <pod-name>"
        return 1
    fi
    kubectl delete pod "$1" --grace-period=0 --force
}

# Restart deployment
krestart() {
    if [ -z "$1" ]; then
        echo "Usage: krestart <deployment-name>"
        return 1
    fi
    kubectl rollout restart deployment "$1"
}

# Port forwarding
kport() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: kport <pod-name> <local-port:remote-port>"
        echo "Example: kport my-pod 8080:80"
        return 1
    fi
    kubectl port-forward "$1" "$2"
}

# Service port forwarding
kport-svc() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: kport-svc <service-name> <local-port:remote-port>"
        echo "Example: kport-svc my-service 8080:80"
        return 1
    fi
    kubectl port-forward "service/$1" "$2"
}

# Top commands (requires metrics-server)
alias ktop-nodes='kubectl top nodes'
alias ktop-pods='kubectl top pods'

# Quick cluster info
kinfo() {
    echo "=== CLUSTER INFO ==="
    kubectl cluster-info
    echo -e "\n=== CURRENT CONTEXT ==="
    kubectl config current-context
    echo -e "\n=== CURRENT NAMESPACE ==="
    kns-current
    echo -e "\n=== NODES ==="
    kubectl get nodes
    echo -e "\n=== NAMESPACES ==="
    kubectl get namespaces
}

# Watch resources
kwatch() {
    if [ -z "$1" ]; then
        echo "Usage: kwatch <resource-type> [resource-name]"
        echo "Example: kwatch pods"
        echo "Example: kwatch pod my-pod"
        return 1
    fi
    watch kubectl get "$@"
}

# Apply and delete shortcuts
alias kapply='kubectl apply -f'
alias kdel='kubectl delete -f'

# Dry run
kdry() {
    kubectl "$@" --dry-run=client -o yaml
}

# Get YAML
kyaml() {
    kubectl get "$@" -o yaml
}

# Get JSON
kjson() {
    kubectl get "$@" -o json
}

# Help function
khelp() {
    echo "Kubernetes Shell Shortcuts:"
    echo ""
    echo "Context Management:"
    echo "  kctx               - List all contexts"
    echo "  kctx-current       - Get current context"
    echo "  kctx-switch <name> - Switch to context"
    echo "  kctx-menu          - Interactive context switcher"
    echo ""
    echo "Namespace Management:"
    echo "  kns                - List all namespaces"
    echo "  kns-current        - Get current namespace"
    echo "  kns-set <name>     - Set namespace"
    echo "  kns-menu           - Interactive namespace switcher"
    echo ""
    echo "Pod Management:"
    echo "  kpods, kp          - List pods"
    echo "  kpods-all, kpa     - List pods in all namespaces"
    echo "  kpod <name>        - Get pod details"
    echo "  kpod-desc <name>   - Describe pod"
    echo "  klogs <name>       - Follow pod logs"
    echo "  kexec <name>       - Execute into pod"
    echo ""
    echo "Other Resources:"
    echo "  ksvc               - List services"
    echo "  kdep               - List deployments"
    echo "  knodes             - List nodes"
    echo "  kall               - List all main resources"
    echo ""
    echo "Utilities:"
    echo "  kinfo              - Cluster information"
    echo "  kwatch <resource>  - Watch resources"
    echo "  kport <pod> <ports> - Port forward"
    echo "  krestart <deploy>  - Restart deployment"
    echo ""
}

# Display help on first source
echo "Kubernetes shortcuts loaded! Type 'khelp' for available commands."
