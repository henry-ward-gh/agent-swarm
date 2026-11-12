variable "cluster_name" {
  description = "kind cluster name."
  type        = string
  default     = "agent-swarm"
}

variable "workers" {
  description = "Worker nodes beside the control plane."
  type        = number
  default     = 1
}
