terraform {
  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4.2"
    }
  }
}

provider "multipass" {}

# Control plane
resource "multipass_instance" "k3s_master" {
  name   = "k3s-master"
  cpus   = 4
  memory = "6G"
  disk   = "30G"
  image  = "22.04"

  # Use templatefile to inject your SSH key into cloud-init
  cloudinit_file = templatefile("${path.module}/cloud-init.tpl.yaml", {
    ssh_pub_key = local.ssh_pub_key
  })
}

# Worker node
resource "multipass_instance" "k3s_worker" {
  name   = "k3s-worker"
  cpus   = 2
  memory = "4G"
  disk   = "20G"
  image  = "22.04"

  # Use templatefile to inject your SSH key into cloud-init
  cloudinit_file = templatefile("${path.module}/cloud-init.tpl.yaml", {
    ssh_pub_key = local.ssh_pub_key
  })
}

# Load SSH public key
locals {
  ssh_pub_key = file("~/.ssh/id_rsa.pub")
}

# read the master VM after creation
data "multipass_instance" "k3s_master" {
  name = multipass_instance.k3s_master.name
}

# read the worker VM after creation
data "multipass_instance" "k3s_worker" {
  name = multipass_instance.k3s_worker.name
}

# output master and worker IPs
output "vm_ips" {
  value = {
    master = data.multipass_instance.k3s_master.ipv4
    worker = data.multipass_instance.k3s_worker.ipv4
  }
}

output "rendered_cloudinit" {
  value = templatefile("${path.module}/cloud-init.tpl.yaml", {
    ssh_pub_key = local.ssh_pub_key
  })
}