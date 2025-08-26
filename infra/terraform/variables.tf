# Variables for Cloud Native Gauntlet Infrastructure

# Master node configuration
variable "master_cpus" {
  description = "Number of CPUs for master node"
  type        = number
  default     = 4
}

variable "master_memory" {
  description = "Memory for master node"
  type        = string
  default     = "6G"
}

variable "master_disk" {
  description = "Disk size for master node"
  type        = string
  default     = "30G"
}

# Worker node configuration
variable "worker_cpus" {
  description = "Number of CPUs for worker node"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory for worker node"
  type        = string
  default     = "4G"
}

variable "worker_disk" {
  description = "Disk size for worker node"
  type        = string
  default     = "20G"
}

# VM configuration
variable "vm_image" {
  description = "Ubuntu image version"
  type        = string
  default     = "22.04"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# Network configuration
variable "vm_names" {
  description = "Names for the VMs"
  type        = map(string)
  default = {
    master = "k3s-master"
    worker = "k3s-worker"
  }
} 