#!/bin/bash

# Cloud Native Gauntlet - Setup Script
# This script sets up the K3s cluster with master and worker nodes using Terraform + Ansible
# Compatible with macOS and Ubuntu

set -e

echo "Starting Cloud Native Gauntlet Setup..."

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
    
    cat > inventory.ini << EOF
[master]
k3s-master ansible_host=$MASTER_IP ansible_user=ubuntu

[workers]
k3s-worker ansible_host=$WORKER_IP ansible_user=ubuntu

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
    
    print_status "Ansible inventory updated!"
    cd ../..
}

# Set up SSH access to VMs
setup_ssh_access() {
    print_status "Setting up SSH access to VMs..."
    
    MASTER_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.master')
    WORKER_IP=$(cd infra/terraform && terraform output -json vm_ips | jq -r '.worker')
    
    # Copy SSH key to VMs using multipass first
    print_status "Copying SSH key to master node..."
    multipass exec k3s-master -- mkdir -p /home/ubuntu/.ssh
    cat ~/.ssh/id_rsa.pub | multipass exec k3s-master -- tee -a /home/ubuntu/.ssh/authorized_keys
    
    print_status "Copying SSH key to worker node..."
    multipass exec k3s-worker -- mkdir -p /home/ubuntu/.ssh
    cat ~/.ssh/id_rsa.pub | multipass exec k3s-worker -- tee -a /home/ubuntu/.ssh/authorized_keys
    
    # Set proper permissions
    multipass exec k3s-master -- chmod 700 /home/ubuntu/.ssh
    multipass exec k3s-master -- chmod 600 /home/ubuntu/.ssh/authorized_keys
    multipass exec k3s-worker -- chmod 700 /home/ubuntu/.ssh
    multipass exec k3s-worker -- chmod 600 /home/ubuntu/.ssh/authorized_keys
    
    print_status "SSH access configured!"
}

# Run Ansible provisioning
run_ansible_provisioning() {
    print_status "Running Ansible provisioning..."
    
    cd infra/ansible
    
    # Run the Ansible playbook
    if ansible-playbook -i inventory.ini provision.yml -v; then
        print_status "Ansible provisioning completed successfully!"
    else
        print_error "Ansible provisioning failed!"
        exit 1
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
    echo ""
}

# Cleanup function for error handling
cleanup() {
    print_error "Setup failed. You may want to clean up resources:"
    echo "- Destroy Terraform infrastructure: cd infra/terraform && terraform destroy"
    echo "- Remove kubeconfig: rm ~/.kube/config"
}

# Main execution
main() {
    # Set up error handling
    trap cleanup ERR
    
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

main "$@"