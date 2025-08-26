#!/bin/bash

# Cloud Native Gauntlet - Deploy Script
# This script deploys applications to the K3s cluster
# Compatible with macOS and Ubuntu

set -e

echo "Deploying applications to K3s cluster..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is configured
check_kubectl() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "kubectl is not configured or cluster is not accessible"
        print_status "Please run the setup script first: ./scripts/setup.sh"
        exit 1
    fi
    
    print_status "Kubernetes cluster is accessible"
}

# Deploy monitoring stack
deploy_monitoring() {
    print_status "Deploying monitoring stack..."
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy monitoring components
    kubectl apply -f monitoring/
    
    print_status "Monitoring stack deployed"
}

# Deploy applications
deploy_applications() {
    print_status "Deploying applications..."
    
    # Deploy App1
    kubectl apply -f apps/app1/
    
    # Deploy App2
    kubectl apply -f apps/app2/
    
    print_status "Applications deployed"
}

# Wait for deployments to be ready
wait_for_deployments() {
    print_status "Waiting for deployments to be ready..."
    
    # Wait for monitoring deployments
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring || true
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring || true
    
    # Wait for application deployments
    kubectl wait --for=condition=available --timeout=300s deployment/app1 || true
    kubectl wait --for=condition=available --timeout=300s deployment/app2 || true
    
    print_status "Deployments are ready"
}

# Display deployment status
show_deployment_status() {
    print_status "Deployment completed successfully!"
    echo ""
    echo "Deployment Status:"
    echo "=================="
    
    echo "Cluster Nodes:"
    kubectl get nodes
    echo ""
    
    echo "All Pods:"
    kubectl get pods --all-namespaces
    echo ""
    
    echo "Services:"
    kubectl get services --all-namespaces
    echo ""
    
    # Get cluster IP for access information
    MASTER_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.master' 2>/dev/null || echo "N/A")
    
    if [[ "$MASTER_IP" != "N/A" ]]; then
        echo "Access Information:"
        echo "=================="
        echo "Applications:"
        echo "- App1: http://$MASTER_IP:30003"
        echo "- App2: http://$MASTER_IP:30004"
        echo ""
        echo "Monitoring:"
        echo "- Grafana: http://$MASTER_IP:30001 (admin/admin)"
        echo "- Prometheus: http://$MASTER_IP:30002"
        echo ""
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "   Cloud Native Gauntlet Deploy Script"
    echo "=========================================="
    echo ""
    
    check_kubectl
    deploy_monitoring
    deploy_applications
    wait_for_deployments
    show_deployment_status
    
    echo "Deployment completed successfully!"
}

main "$@" 