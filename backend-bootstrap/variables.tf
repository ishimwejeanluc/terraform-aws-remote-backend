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
  description = "AWS region for backend resources"
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
  default = "devops-lab-tf-state-123456789" 
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "devops-lab-tf-lock"
}
