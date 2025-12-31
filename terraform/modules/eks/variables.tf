variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to cluster endpoint"
  type        = bool
  default     = true
}

variable "enable_ebs_csi" {
  description = "Enable EBS CSI driver"
  type        = bool
  default     = true
}

variable "enable_efs" {
  description = "Enable EFS CSI driver"
  type        = bool
  default     = true
}

variable "ebs_csi_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  type        = string
  default     = null
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler IRSA"
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "Map of EKS node group configurations"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = number
    taints         = optional(list(object({
      key    = string
      value  = string
      effect = string
    })))
    tags = optional(map(string))
  }))
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
