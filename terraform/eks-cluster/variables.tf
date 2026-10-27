variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the EKS Cluster"
  type        = string
  default     = "my-cluster"
}

variable "cluster_version" {
  description = "Kubernetes Version for EKS"
  type        = string
  default     = "1.31"
}

variable "nodegroup_name" {
  description = "Name of the Managed Nodegroup"
  type        = string
  default     = "my-nodes"
}

variable "node_type" {
  description = "EC2 Instance type for worker nodes"
  type        = string
  default     = "m7i.large"
}

variable "desired_nodes" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "max_nodes" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 30
}
