variable "repo_url" {
  description = "Repo Argo CD pulls from. CI passes the PR's head repo."
  type        = string
  default     = "https://github.com/henry-ward-gh/agent-swarm.git"
}

variable "target_revision" {
  description = "Revision the whole cluster follows. Argo CD pulls from Git, so push before pointing at a branch."
  type        = string
  default     = "main"
}

variable "image_tag" {
  description = "Mock Agent image tag (loaded into kind by task images:load)."
  type        = string
  default     = "dev"
}
