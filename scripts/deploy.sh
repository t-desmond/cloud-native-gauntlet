#!/bin/bash

# Cloud Native Gauntlet - GitOps Deploy Script
# Deploys Gitea and ArgoCD to a K3s cluster via SSH to master VM
# ArgoCD will then manage the deployment of all other components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
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

# Configure /etc/hosts for local services
configure_hosts_file() {
    local MASTER_IP
    MASTER_IP=$(get_master_ip)
    print_status "Configuring /etc/hosts entries for all services"

    # All services that will eventually be deployed via ArgoCD
    local HOSTS=(
        "task-api.local"      # Backend API
        "keycloak.local"      # Authentication service
        "gitea.local"         # Git repository and CI/CD
        "argocd.local"        # GitOps deployment tool
        "linkerd.local"       # Service mesh dashboard
        "grafana.linkerd.local"   # Observability
        "prometheus.linkerd.local" # Monitoring
    )

    for host in "${HOSTS[@]}"; do
        if grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+$host\$" /etc/hosts; then
            # Entry exists → check if IP matches
            current_ip=$(grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+$host\$" /etc/hosts | awk '{print $1}')
            if [[ "$current_ip" != "$MASTER_IP" ]]; then
                print_status "Updating $host to point to $MASTER_IP"
                # Cross-platform sed: create temp file and replace atomically
                temp_file=$(mktemp)
                sudo sed "s/^.*[[:space:]]$host\$/$MASTER_IP $host/" /etc/hosts > "$temp_file"
                sudo mv "$temp_file" /etc/hosts
            else
                print_status "$host already points to $MASTER_IP (no change needed)"
            fi
        else
            # Entry missing → add it
            print_status "Adding $host → $MASTER_IP"
            echo "$MASTER_IP $host" | sudo tee -a /etc/hosts >/dev/null
        fi
    done
}

# Execute kubectl on master VM
run_kubectl() {
    local MASTER_IP=$(get_master_ip)
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "export KUBECONFIG=/home/ubuntu/.kube/config; $1"
}

# Wait for deployments in namespace
wait_for_deployments() {
    local ns="$1"
    print_status "Waiting for deployments in namespace '$ns'..."
    run_kubectl "kubectl -n $ns wait --for=condition=available deployment --all --timeout=300s 2>/dev/null || true"
}

# Deploy CNPG Operator
deploy_cnpg_operator() {
    print_status "Deploying CNPG Operator..."
    run_kubectl "kubectl apply --server-side -f /home/ubuntu/projects/apps/database/operator.yaml"
    run_kubectl "kubectl wait --for=condition=Available deployment/cnpg-controller-manager -n cnpg-system --timeout=300s"
}

# Deploy Gitea
deploy_gitea() {
    print_status "Deploying Gitea..."
    local gitea_dir="/home/ubuntu/projects/apps/gitops/gitea"
    
    run_kubectl "kubectl apply -f $gitea_dir/namespace.yaml"
    run_kubectl "kubectl apply -f $gitea_dir/db-bootstrap.yaml"
    wait_for_deployments "gitea"
    
    run_kubectl "kubectl apply -f $gitea_dir/pvc.yaml -f $gitea_dir/secret.yaml -f $gitea_dir/deployment.yaml -f $gitea_dir/service.yaml"
    wait_for_deployments "gitea"
    
    run_kubectl "kubectl apply -f $gitea_dir/ingress.yaml"
}

# Update runner manifest with Gitea service IP
update_runner_service_ip() {
    print_status "Updating runner manifest with Gitea service IP..."
    local gitea_service_ip
    gitea_service_ip=$(run_kubectl "kubectl -n gitea get svc gitea -o jsonpath='{.spec.clusterIP}'")
    
    if [[ -z "$gitea_service_ip" ]]; then
        print_error "Could not get Gitea service IP"
        return 1
    fi
    
    print_status "Gitea service IP: $gitea_service_ip"
    
    local MASTER_IP=$(get_master_ip)
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP '
        export KUBECONFIG=/home/ubuntu/.kube/config
        runner_manifest="/home/ubuntu/projects/apps/gitops/gitea/runner.yaml"
        gitea_ip="'"$gitea_service_ip"'"
        
        temp_file=$(mktemp)
        sed "s|http://[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*:3000|http://$gitea_ip:3000|g" "$runner_manifest" > "$temp_file"
        mv "$temp_file" "$runner_manifest"
        
        echo "Updated GITEA_INSTANCE_URL to http://$gitea_ip:3000"
    '
}

# Setup Gitea runner
setup_gitea_runner() {
    print_status "Setting up Gitea runner..."
    echo ""
    print_warn "Visit http://gitea.local → Admin Panel → Actions → Runners → Create new runner"
    echo ""
    
    read -sp "Enter Gitea runner registration token: " runner_token
    echo ""
    
    if [[ -z "$runner_token" ]]; then
        print_warn "No token provided. Skipping runner setup."
        return
    fi
    
    # Update runner manifest with current service IP
    update_runner_service_ip
    
    local MASTER_IP=$(get_master_ip)
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP '
        export KUBECONFIG=/home/ubuntu/.kube/config
        runner_manifest="/home/ubuntu/projects/apps/gitops/gitea/runner.yaml"
        runner_token="'"$runner_token"'"
        
        temp_file=$(mktemp)
        sed "s|token: \"[^\"]*\"|token: \"$runner_token\"|g" "$runner_manifest" > "$temp_file"
        mv "$temp_file" "$runner_manifest"
        kubectl apply -f "$runner_manifest"
    '
}

# Deploy ArgoCD
deploy_argocd() {
    print_status "Deploying ArgoCD..."
    local argocd_dir="/home/ubuntu/projects/apps/gitops/argocd"
    
    run_kubectl "kubectl apply -f $argocd_dir/namespace.yaml"
    run_kubectl "kubectl apply -f $argocd_dir/install.yaml -f $argocd_dir/ingress.yaml -f $argocd_dir/configmap.yaml -n argocd"
    wait_for_deployments "argocd"
}

# Deploy ArgoCD Applications
deploy_argocd_apps() {
    print_status "Deploying ArgoCD Applications..."
    local apps_dir="/home/ubuntu/projects/gitops/applications"
    
    run_kubectl "kubectl apply -f $apps_dir/linkerd-app.yaml -f $apps_dir/database-app.yaml -f $apps_dir/keycloak-app.yaml -f $apps_dir/task-api-app.yaml -n argocd"
    run_kubectl "sleep 10; kubectl get applications -n argocd"
}

# Show deployment status and next steps
show_deployment_status() {
    local MASTER_IP=$(get_master_ip)
    local REGISTRY_IP=$(get_registry_ip)

    print_status "GitOps foundation deployment completed successfully!"
    echo ""
    echo "=========================================="
    echo "           Access Information"
    echo "=========================================="
    echo ""
    echo "🔧 GitOps Tools:"
    echo "   Gitea:  http://gitea.local"
    echo "   ArgoCD: http://argocd.local"
    echo ""
    echo "🏗️  Infrastructure:"
    echo "   Registry: $REGISTRY_IP:5000"
    echo "   Master VM: $MASTER_IP"
    echo ""
    echo "🚀 ArgoCD Managed Services:"
    echo "   • Linkerd Service Mesh (observability & security)"
    echo "   • PostgreSQL Database (CNPG operator)"
    echo "   • Keycloak Identity Provider: http://keycloak.local"
    echo "   • Task API Backend: http://task-api.local/api"
    echo ""
    echo "📊 Observability Stack:"
    echo "   • Linkerd Dashboard: http://linkerd.local"
    echo "   • Grafana: http://grafana.linkerd.local"
    echo "   • Prometheus: http://prometheus.linkerd.local"
    echo ""
    echo "=========================================="
    echo "               Current Status"
    echo "=========================================="
    
    echo ""
    print_status "Gitea Pods:"
    run_kubectl "kubectl get pods -n gitea"
    
    echo ""
    print_status "ArgoCD Pods:"
    run_kubectl "kubectl get pods -n argocd"
    
    echo ""
    echo "=========================================="
    echo "               Next Steps"
    echo "=========================================="
    echo ""
    echo "1. 📁 Set up your application manifests in Gitea repositories"
    echo "2. 🔄 Configure ArgoCD applications to sync from Gitea"
    echo "3. 🚀 Deploy your services via GitOps workflow"
    echo ""
    echo "📚 Component Information:"
    echo "   • Database: CNPG PostgreSQL operator and cluster"
    echo "   • Backend: Rust-based task API with JWT authentication"
    echo "   • Auth: Keycloak for identity and access management"
    echo "   • Mesh: Linkerd service mesh for observability"
    echo "   • Monitoring: Prometheus and Grafana stack"
    echo ""
    echo "🔧 Useful Commands:"
    echo "   kubectl --kubeconfig ~/.kube/config get pods --all-namespaces"
    echo "   kubectl -n gitea port-forward svc/gitea 3000:3000"
    echo "   kubectl -n argocd port-forward svc/argocd-server 8080:443"
    echo ""
    echo "🔐 ArgoCD Initial Password:"
    echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

# Main execution
main() {
    echo "=============================================="
    echo "   Cloud Native Gauntlet - GitOps Deploy"
    echo "=============================================="
    echo ""
    echo "This script deploys the GitOps foundation:"
    echo "• Gitea (Git repository and CI/CD)"
    echo "• ArgoCD (GitOps deployment tool)"
    echo ""
    echo "All other components will be managed by ArgoCD."
    echo ""
    
    check_ssh_access
    configure_hosts_file
    deploy_cnpg_operator
    deploy_gitea
    
    echo ""
    read -p "Do you want to set up the Gitea runner now? (y/N): " setup_runner
    if [[ "$setup_runner" =~ ^[Yy]$ ]]; then
        setup_gitea_runner
    else
        print_warn "Skipping runner setup. You can run this later if needed."
    fi
    
    deploy_argocd
    deploy_argocd_apps
    
    show_deployment_status
    
    echo ""
    print_status "GitOps foundation deployment completed!"
    print_status "Your cluster is now ready for GitOps-managed deployments."
}

main "$@"