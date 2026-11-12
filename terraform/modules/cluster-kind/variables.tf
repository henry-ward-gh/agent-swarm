variable "name" {
  description = "kind cluster name."
  type        = string
  default     = "agent-swarm"
}

variable "workers" {
  description = "Number of worker nodes beside the single control-plane node."
  type        = number
  default     = 1

  validation {
    condition     = var.workers >= 0 && floor(var.workers) == var.workers
    error_message = "workers must be a whole number >= 0."
  }
}

variable "node_image" {
  description = "kindest/node image; null uses kind's default for its version."
  type        = string
  default     = null
}

variable "kubeconfig_path" {
  description = "Where kind writes the kubeconfig; null uses kind's default (~/.kube/config)."
  type        = string
  default     = null
}
