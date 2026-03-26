variable "project_name" {
  description = "Project name prefix for resource tagging"
  type        = string
  default     = "devops-lab"
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "availability_zone" {
  description = "Availability zone for the public subnet"
  type        = string
  default     = "eu-west-1a"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_ingress_cidr" {
  description = "CIDR block allowed to SSH (use your public IP/32)"
  type        = string

  validation {
    condition     = can(regex("/\\d+$", var.ssh_ingress_cidr))
    error_message = "ssh_ingress_cidr must be a valid CIDR (example: 203.0.113.10/32)."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH"
  type        = string
}
