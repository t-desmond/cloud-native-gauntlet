#!/bin/bash

# Cloud Native Gauntlet - Deploy Script
# Deploys applications to a K3s cluster via SSH to master VM

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get master VM IP from terraform output
get_master_ip() {
    MASTER_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.master' 2>/dev/null)
    [[ -z "$MASTER_IP" ]] && { print_error "Could not get master IP"; exit 1; }
    echo "$MASTER_IP"
}

# Get registry IP from terraform output
get_registry_ip() {
    REGISTRY_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.registry' 2>/dev/null)
    [[ -z "$REGISTRY_IP" ]] && { print_error "Could not get registry IP"; exit 1; }
    echo "$REGISTRY_IP"
}

# Check SSH access to master VM
check_ssh_access() {
    local MASTER_IP
    MASTER_IP=$(get_master_ip)
    print_status "Checking SSH access to $MASTER_IP..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "echo 'SSH connection successful'" >/dev/null 2>&1 || {
        print_error "Cannot connect to master VM. Run setup.sh first."
        exit 1
    }
}

# Configure /etc/hosts for task-api.local and keycloak.local
configure_hosts_file() {
    local MASTER_IP
    MASTER_IP=$(get_master_ip)
    print_status "Configuring /etc/hosts for task-api.local and keycloak.local..."

    # Check if task-api.local exists in /etc/hosts
    if grep -q "task-api.local" /etc/hosts; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sudo sed -i '' "s/.*task-api.local/$MASTER_IP task-api.local keycloak.local/" /etc/hosts
        else
            sudo sed -i "s/.*task-api.local/$MASTER_IP task-api.local keycloak.local/" /etc/hosts
        fi
    else
        # Add both task-api.local and keycloak.local to /etc/hosts
        echo "$MASTER_IP task-api.local keycloak.local" | sudo tee -a /etc/hosts >/dev/null
    fi
}

# Execute kubectl command on master VM with proper kubeconfig
run_kubectl_on_master() {
    local MASTER_IP
    MASTER_IP=$(get_master_ip)
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
        "kubectl --kubeconfig /home/ubuntu/.kube/config $1"
}

# Deploy database components (CNPG)
deploy_database() {
    print_status "Deploying database components..."
    local MASTER_IP
    MASTER_IP=$(get_master_ip)

    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "
        export KUBECONFIG=/home/ubuntu/.kube/config

        # Create namespace
        kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -

        # Apply CNPG operator manifests
        kubectl delete -f /home/ubuntu/projects/apps/database/cnpg-1.27.0.yaml --ignore-not-found
        kubectl apply --server-side -f /home/ubuntu/projects/apps/database/cnpg-1.27.0.yaml

        # Wait for CNPG operator deployment to be ready
        kubectl -n cnpg-system wait --for=condition=available --timeout=180s deployment/cnpg-controller-manager
    "

    # Apply secrets and CNPG Cluster
    local manifests=(
        "/home/ubuntu/projects/apps/database/db-secret.yaml"
        "/home/ubuntu/projects/apps/database/cluster-app.yaml"
    )

    for manifest in "${manifests[@]}"; do
        print_status "Deleting existing $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config delete -f $manifest --ignore-not-found"
        print_status "Applying $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config apply -f $manifest"
    done

    print_status "Waiting for CNPG cluster to be ready..."
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config wait --for=condition=ready --timeout=300s cluster/cluster-app -n database"
}

# Deploy backend components
deploy_backend() {
    print_status "Deploying backend components..."
    local MASTER_IP
    MASTER_IP=$(get_master_ip)

    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "
        export KUBECONFIG=/home/ubuntu/.kube/config
        kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -
    "

    local manifests=(
        "/home/ubuntu/projects/apps/backend/task-api-secret.yaml"
        "/home/ubuntu/projects/apps/backend/task-api-configmap.yaml"
        "/home/ubuntu/projects/apps/backend/task-api-deployment.yaml"
        "/home/ubuntu/projects/apps/backend/task-api-service.yaml"
        "/home/ubuntu/projects/apps/backend/task-api-ingress.yaml"
    )

    for manifest in "${manifests[@]}"; do
        print_status "Deleting existing $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config delete -f $manifest --ignore-not-found"
        print_status "Applying $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config apply -f $manifest"
    done

    print_status "Waiting for backend deployment to be ready..."
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config wait --for=condition=available --timeout=300s deployment/task-api -n backend"
}

# Deploy auth components (Keycloak)
deploy_auth() {
    print_status "Deploying Keycloak (auth components)..."
    local MASTER_IP
    MASTER_IP=$(get_master_ip)

    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "
        export KUBECONFIG=/home/ubuntu/.kube/config
        kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
    "

    # Secrets and ConfigMap
    local pre_manifests=(
        "/home/ubuntu/projects/apps/auth/keycloak-secret.yaml"
        "/home/ubuntu/projects/apps/auth/keycloak-configmap.yaml"
    )

    for manifest in "${pre_manifests[@]}"; do
        print_status "Deleting existing $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config delete -f $manifest --ignore-not-found"
        print_status "Applying $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config apply -f $manifest"
    done

    # Keycloak deployment
    print_status "Deploying Keycloak deployment..."
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config delete -f /home/ubuntu/projects/apps/auth/keycloak-deployment.yaml --ignore-not-found"
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config apply -f /home/ubuntu/projects/apps/auth/keycloak-deployment.yaml"

    print_status "Waiting for Keycloak deployment to be ready..."
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config wait --for=condition=available --timeout=300s deployment/keycloak -n keycloak"

    # Service and Ingress
    local post_manifests=(
        "/home/ubuntu/projects/apps/auth/keycloak-service.yaml"
        "/home/ubuntu/projects/apps/auth/keycloak-ingress.yaml"
    )

    for manifest in "${post_manifests[@]}"; do
        print_status "Deleting existing $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config delete -f $manifest --ignore-not-found"
        print_status "Applying $(basename $manifest)..."
        ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config apply -f $manifest"
    done
}

# Show deployment status
show_deployment_status() {
    local MASTER_IP
    MASTER_IP=$(get_master_ip)
    local REGISTRY_IP
    REGISTRY_IP=$(get_registry_ip)

    print_status "Deployment completed successfully!"
    echo -e "\nAccess Information:"
    echo "=================="
    echo "Backend API: http://task-api.local/api"
    echo "Health Check: http://task-api.local/api/health"
    echo "Database Port Forward: kubectl port-forward svc/cluster-app-rw 5432:5432 -n database"
    echo "Registry: $REGISTRY_IP:5000"
    echo "Keycloak: http://keycloak.local/auth"

    echo -e "\nPods:"
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config get pods --all-namespaces"

    echo -e "\nServices:"
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl --kubeconfig /home/ubuntu/.kube/config get services --all-namespaces"

    echo "Database:"
    echo "- Port Forward: kubectl port-forward svc/cluster-app-rw 5432:5432 -n database"
    echo "- Connection: psql -U admin -d database -h localhost"

    echo ""
    echo "API Testing Examples:"
    echo "- Login: curl -X POST http://task-api.local/api/auth/login \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{\"email\": \"admin@example.com\", \"password\": \"adminpassword\"}'"

    echo ""
    echo "Keycloak Testing:"
    echo "- Admin Console: http://keycloak.local/"
    echo "- Default credentials: (check keycloak-secret.yaml)"
}

# Main execution
main() {
    echo "=========================================="
    echo "   Cloud Native Gauntlet Deploy Script"
    echo "=========================================="
    echo ""
    check_ssh_access
    configure_hosts_file
    deploy_database
    deploy_backend
    deploy_auth
    show_deployment_status
    print_status "Deployment completed!"
}

main "$@"
