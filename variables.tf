variable "aws_region" {
  type        = string
  description = "AWS region where the frontend bucket is managed."
  default     = "us-east-2"
}

variable "frontend_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for the frontend."
  default     = "products-growshop-bucket-11082026"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.frontend_bucket_name))
    error_message = "frontend_bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "access_logs_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for frontend access logs."
  default     = "products-growshop-access-logs-11082026"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_logs_bucket_name))
    error_message = "access_logs_bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "index_document" {
  type        = string
  description = "Default document served by S3 static website hosting."
  default     = "index.html"
}
