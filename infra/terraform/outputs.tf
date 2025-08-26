# Outputs for Cloud Native Gauntlet Infrastructure

# VM IP addresses
output "vm_ips" {
  description = "IP addresses of the created VMs"
  value = {
    master = data.multipass_instance.k3s_master.ipv4
    worker = data.multipass_instance.k3s_worker.ipv4
  }
}

# Master node information
output "master_info" {
  description = "Information about the K3s master node"
  value = {
    name = multipass_instance.k3s_master.name
    ip   = data.multipass_instance.k3s_master.ipv4
    cpus = multipass_instance.k3s_master.cpus
    memory = multipass_instance.k3s_master.memory
    disk = multipass_instance.k3s_master.disk
  }
}

# Worker node information
output "worker_info" {
  description = "Information about the K3s worker node"
  value = {
    name = multipass_instance.k3s_worker.name
    ip   = data.multipass_instance.k3s_worker.ipv4
    cpus = multipass_instance.k3s_worker.cpus
    memory = multipass_instance.k3s_worker.memory
    disk = multipass_instance.k3s_worker.disk
  }
}

# Cluster access information
output "cluster_access" {
  description = "Information for accessing the K3s cluster"
  value = {
    master_ip = data.multipass_instance.k3s_master.ipv4
    worker_ip = data.multipass_instance.k3s_worker.ipv4
    kubeconfig_command = "multipass exec k3s-master -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config"
    kubectl_setup = "sed -i 's/127.0.0.1/${data.multipass_instance.k3s_master.ipv4}/g' ~/.kube/config"
  }
} 