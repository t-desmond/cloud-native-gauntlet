#!/bin/bash

# Cloud Native Gauntlet - Setup Script
# This script sets up the K3s cluster with master and worker nodes using Terraform + Ansible
# Compatible with macOS and Ubuntu

set -e
trap cleanup ERR SIGINT SIGTERM

echo "Starting Cloud Native Gauntlet Setup..."


RUN_LOCAL_REGISTRY=false
TERRAFORM_APPLIED=false

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

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        print_status "Detected macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="ubuntu"
        print_status "Detected Ubuntu/Linux"
    else
        print_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

# Check prerequisites based on OS
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform >/dev/null 2>&1; then
        print_error "Terraform is required but not installed."
        print_status "Install Terraform:"
        if [[ "$OS" == "macos" ]]; then
            echo "  brew install terraform"
        else
            echo "  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -"
            echo "  sudo apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com \$(lsb_release -cs)\""
            echo "  sudo apt-get update && sudo apt-get install terraform"
        fi
        exit 1
    fi
    
    # Check Ansible
    if ! command -v ansible >/dev/null 2>&1; then
        print_error "Ansible is required but not installed."
        print_status "Install Ansible:"
        if [[ "$OS" == "macos" ]]; then
            echo "  brew install ansible"
        else
            echo "  sudo apt update && sudo apt install ansible"
        fi
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        print_error "kubectl is required but not installed."
        print_status "Install kubectl:"
        if [[ "$OS" == "macos" ]]; then
            echo "  brew install kubectl"
        else
            echo "  sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl"
            echo "  sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg"
            echo "  echo \"deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main\" | sudo tee /etc/apt/sources.list.d/kubernetes.list"
            echo "  sudo apt-get update && sudo apt-get install -y kubectl"
        fi
        exit 1
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required but not installed."
        if [[ "$OS" == "macos" ]]; then
            echo "  brew install jq"
        else
            echo "  sudo apt install jq"
        fi
        exit 1
    fi
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        print_error "SSH public key not found at ~/.ssh/id_rsa.pub"
        print_status "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    fi
    
    print_status "All prerequisites are satisfied!"
}

# Create infrastructure
create_infrastructure() {
    print_status "Creating infrastructure with Terraform..."
    
    cd infra/terraform
    
    terraform init
    terraform apply -auto-approve

    # Mark Terraform as applied
    TERRAFORM_APPLIED=true
    
    MASTER_IP=$(terraform output -json vm_ips | jq -r '.master')
    WORKER_IP=$(terraform output -json vm_ips | jq -r '.worker')
    
    print_status "Infrastructure created successfully!"
    print_status "Master IP: $MASTER_IP"
    print_status "Worker IP: $WORKER_IP"
    
    cd ../..
}

# Update Ansible inventory with actual IPs
update_inventory() {
    print_status "Updating Ansible inventory..."
    
    cd infra/ansible
    
    MASTER_IP=$(cd ../terraform && terraform output -json vm_ips | jq -r '.master')
    WORKER_IP=$(cd ../terraform && terraform output -json vm_ips | jq -r '.worker')
    REGISTRY_IP=$(cd ../terraform && terraform output -json vm_ips | jq -r '.registry')
    
    cat > inventory.ini << EOF
[master]
k3s-master ansible_host=$MASTER_IP ansible_user=ubuntu

[workers]
k3s-worker ansible_host=$WORKER_IP ansible_user=ubuntu

[registry]
docker-registry ansible_host=$REGISTRY_IP ansible_user=ubuntu

[k3s:children]
master
workers

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
registry_host=$REGISTRY_IP
registry_port=5000
EOF
    
    print_status "Ansible inventory updated!"
    cd ../..
}

# Set up SSH access to VMs
setup_ssh_access() {
    print_status "Setting up SSH access to VMs..."

    # Get VM IPs from Terraform
    VM_IPS=$(cd infra/terraform && terraform output -json vm_ips)

    # Define node names and their corresponding IPs in arrays
    NODES=("k3s-master" "k3s-worker" "docker-registry")
    IPS=(
        $(echo "$VM_IPS" | jq -r '.master')
        $(echo "$VM_IPS" | jq -r '.worker')
        $(echo "$VM_IPS" | jq -r '.registry')
    )

    # Loop over each node and configure SSH access
    for i in "${!NODES[@]}"; do
        NODE=${NODES[$i]}
        IP=${IPS[$i]}

        print_status "Copying SSH key to $NODE ($IP)..."

        # Create .ssh directory and copy public key
        multipass exec $NODE -- mkdir -p /home/ubuntu/.ssh
        cat ~/.ssh/id_rsa.pub | multipass exec $NODE -- tee -a /home/ubuntu/.ssh/authorized_keys
        multipass exec $NODE -- chmod 700 /home/ubuntu/.ssh
        multipass exec $NODE -- chmod 600 /home/ubuntu/.ssh/authorized_keys
    done

    print_status "SSH access configured for all nodes!"
}

# Run Ansible provisioning
run_ansible_provisioning() {
    print_status "Running Ansible provisioning..."
    
    cd infra/ansible
    
    # Always run K3s configuration
    if ansible-playbook -i inventory.ini configure-k3s.yml -v; then
        print_status "K3s provisioning completed successfully!"
    else
        print_error "K3s provisioning failed!"
        exit 1
    fi

    # Conditionally run the registry playbook
    if [ "$RUN_LOCAL_REGISTRY" = true ]; then
        print_status "Running local registry playbook..."
        if ansible-playbook -i inventory.ini setup-registry.yml -v; then
            print_status "Local registry setup completed successfully!"
        else
            print_error "Local registry setup failed!"
        fi
    fi
    
    cd ../..
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    MASTER_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.master')
    
    # Create .kube directory if it doesn't exist
    mkdir -p ~/.kube
    
    # Copy kubeconfig from master
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
    
    # Update kubeconfig with correct IP (OS-specific sed command)
    if [[ "$OS" == "macos" ]]; then
        sed -i '' "s/127.0.0.1/$MASTER_IP/g" ~/.kube/config
    else
        sed -i "s/127.0.0.1/$MASTER_IP/g" ~/.kube/config
    fi
    
    chmod 600 ~/.kube/config
    
    print_status "kubectl configured successfully!"
}

# Wait for cluster to be ready
wait_for_cluster() {
    print_status "Waiting for cluster to be ready..."
    
    # Wait for nodes to be ready
    for i in {1..30}; do
        if kubectl get nodes 2>/dev/null | grep -q "Ready"; then
            NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
            if [ "$NODE_COUNT" -eq 2 ]; then
                print_status "Cluster is ready with both nodes!"
                break
            fi
        fi
        print_status "Waiting for nodes to be ready... (attempt $i/30)"
        sleep 10
    done
    
    # Show cluster status
    print_status "Current cluster status:"
    kubectl get nodes -o wide
}

# Display cluster information
show_cluster_info() {
    print_status "Cluster setup completed successfully!"
    echo ""
    echo "Access Information:"
    echo "=================="
    
    MASTER_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.master')
    WORKER_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.worker')
    
    echo "K3s Master IP: $MASTER_IP"
    echo "K3s Worker IP: $WORKER_IP"
    
    if [ "$RUN_LOCAL_REGISTRY" = true ]; then
        REGISTRY_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.registry')
        echo "Local Docker Registry IP: $REGISTRY_IP"
        echo "Registry Port: 5000"
    fi

    echo ""
    echo "Cluster Management:"
    echo "- kubectl is configured and ready to use"
    echo "- Check cluster status: kubectl get nodes"
    echo "- Check pods: kubectl get pods --all-namespaces"
    echo "- Kubeconfig location: ~/.kube/config"
    echo ""
    echo "VM Access:"
    echo "- Master: ssh ubuntu@$MASTER_IP"
    echo "- Worker: ssh ubuntu@$WORKER_IP"
    
    if [ "$RUN_LOCAL_REGISTRY" = true ]; then
        echo "- Registry: ssh ubuntu@$REGISTRY_IP"
    fi
    
    echo ""
}

# Cleanup function for error handling
cleanup() {
    print_error "Setup interrupted or failed. Cleaning up resources..."

    if [ "$TERRAFORM_APPLIED" = true ]; then
        print_status "[INFO] Destroying Terraform-managed infrastructure..."
        cd infra/terraform
        terraform destroy -auto-approve
        cd ../..
    else
        print_status "[INFO] Terraform was not applied. No resources to destroy."
    fi

    # Remove kubeconfig if it exists
    if [ -f ~/.kube/config ]; then
        print_status "[INFO] Removing kubeconfig..."
        rm -f ~/.kube/config
    fi

    exit 1
}

# Main execution
main() {
    echo "=========================================="
    echo "   Cloud Native Gauntlet Setup Script"
    echo "=========================================="
    echo ""
    
    detect_os
    check_prerequisites
    create_infrastructure
    update_inventory
    setup_ssh_access
    run_ansible_provisioning
    configure_kubectl
    wait_for_cluster
    show_cluster_info
    
    print_status "Setup completed successfully!"
}

# Parse script arguments
for arg in "$@"; do
    case $arg in
        --local-registry)
            RUN_LOCAL_REGISTRY=true
            shift
            ;;
        *)
            ;;
    esac
done

main "$@"