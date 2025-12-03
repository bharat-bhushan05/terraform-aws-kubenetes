variable "subnet_id" {
  description = "The Subnet ID where instances will be launched"
  type        = string
}

variable "master_sg_id" {
  description = "Security Group ID for Master Node"
  type        = string
}

variable "worker_sg_id" {
  description = "Security Group ID for Worker Nodes"
  type        = string
}

variable "key_name" {
  description = "SSH Key pair name"
  type        = string
  default     = ""
}

variable "private_key" {
  description = "SSH private key for connecting to instances"
  type        = string
  sensitive   = true
}
