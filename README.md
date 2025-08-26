# Cloud Native Gauntlet

A comprehensive cloud-native project demonstrating Kubernetes deployment, monitoring, and infrastructure automation using K3s and Multipass.

## Project Overview

This project sets up a complete cloud-native environment with:
- **Infrastructure**: Multipass VMs running K3s Kubernetes cluster
- **Applications**: Sample applications deployed to Kubernetes
- **Monitoring**: Prometheus and Grafana for observability
- **Automation**: Terraform and Ansible for infrastructure management

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   K3s Master    │    │   K3s Worker    │
│   (Multipass)   │    │   (Multipass)   │
│                 │    │                 │
│ - Control Plane │    │ - Worker Node   │
│ - etcd          │    │ - Applications  │
│ - API Server    │    │ - Monitoring    │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┘
                    │
         ┌─────────────────┐
         │   Applications  │
         │                 │
         │ - App1          │
         │ - App2          │
         │ - Prometheus    │
         │ - Grafana       │
         └─────────────────┘
```

## Prerequisites

- Multipass installed
- Terraform installed
- Ansible installed
- kubectl installed
- SSH key pair generated (`~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`)

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd cloud-native-gauntlet
   ```

2. **Run the automated setup script**:
   ```bash
   chmod +x scripts/setup.sh
   ./scripts/setup.sh
   ```

3. **Verify the cluster**:
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

4. **Install GitOps with ArgoCD** (optional):
   ```bash
   chmod +x gitops/scripts/install-argocd.sh
   ./gitops/scripts/install-argocd.sh
   ```

5. **Deploy applications** (optional):
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

## Project Structure

```
cloud-native-gauntlet/
├── README.md                    # Project overview and setup instructions
├── .gitignore                   # Git ignore patterns
├── infra/                       # Infrastructure automation
│   ├── ansible/                 # Ansible playbooks for K3s setup
│   └── terraform/               # Terraform for VM creation
├── apps/                        # Application deployments (templates)
│   ├── app1/                    # Sample application 1
│   └── app2/                    # Sample application 2
├── monitoring/                  # Monitoring stack (templates)
├── gitops/                      # GitOps configuration with ArgoCD
│   ├── argocd/                  # ArgoCD application definitions
│   └── scripts/                 # GitOps automation scripts
├── scripts/                     # Automation scripts
└── kustomization/               # Environment-specific configs (templates)
```

## Components

### Infrastructure
- **Terraform**: Creates Multipass VMs (master and worker) with dynamic IP allocation
- **Ansible**: Installs and configures K3s cluster
- **Multipass**: Lightweight VM provider for development

### Applications
- **App1**: Sample web application (template)
- **App2**: Sample API service (template)
- **Prometheus**: Metrics collection (template)
- **Grafana**: Metrics visualization (template)

### Automation
- **setup.sh**: Complete automated setup script (cross-platform)
- **deploy.sh**: Application deployment script

### GitOps
- **ArgoCD**: GitOps continuous deployment tool
- **Application Definitions**: ArgoCD application configurations
- **Automated Sync**: Automatic deployment from Git changes

## Development

### Adding New Applications
1. Replace placeholder files in `apps/` with your actual Kubernetes manifests
2. Update deployment scripts as needed

### Modifying Infrastructure
1. Edit Terraform files in `infra/terraform/`
2. Update Ansible playbooks in `infra/ansible/`
3. Test changes by running `./scripts/setup.sh`

## Troubleshooting

### Common Issues

#### 1. Prerequisites Not Installed
The setup script will check for required tools and provide installation instructions.

#### 2. SSH Key Issues
```bash
# Generate SSH key if missing
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

#### 3. Cluster Access Issues
```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# Check VM connectivity
ping <master-ip>
```

#### 4. Cleanup and Restart
```bash
# Destroy infrastructure
cd infra/terraform
terraform destroy -auto-approve

# Restart setup
./scripts/setup.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

[Add your license here] 