variable "aws_region" {
  type        = string
  description = "AWS region for every resource. ap-southeast-2 is the default buyer region."
  default     = "ap-southeast-2"

  validation {
    condition     = contains(["ap-southeast-2", "us-east-1"], var.aws_region)
    error_message = "Supported regions are ap-southeast-2 (default) and us-east-1."
  }
}

variable "name_prefix" {
  type        = string
  description = "Short prefix used for AWS resource names."
  default     = "cod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.name_prefix))
    error_message = "name_prefix must be 2-16 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "container_image" {
  type        = string
  description = "Marketplace ECR image digest for app and worker. Must be sha256-pinned. latest is rejected."

  validation {
    condition = (
      can(regex("@sha256:[0-9a-f]{64}$", var.container_image)) &&
      !can(regex(":[Ll][Aa][Tt][Ee][Ss][Tt](@|$)", var.container_image))
    )
    error_message = "container_image must end in @sha256:<64 hex>. Floating tags such as latest are not allowed."
  }
}

variable "license_key" {
  type        = string
  description = "Signed COD license JWT. Stored in Secrets Manager. Never commit the real value."
  sensitive   = true
}

variable "marketplace_product_code" {
  type        = string
  description = "AWS Marketplace product code from the COD listing. Required. There is no license bypass."

  validation {
    condition     = length(trimspace(var.marketplace_product_code)) > 0
    error_message = "marketplace_product_code is required. Subscribe on AWS Marketplace and copy the product code from the listing."
  }
}

variable "marketplace_product_sku" {
  type        = string
  description = "AWS Marketplace product ID (SKU) from the COD listing. Required. There is no license bypass."

  validation {
    condition     = length(trimspace(var.marketplace_product_sku)) > 0
    error_message = "marketplace_product_sku is required. Subscribe on AWS Marketplace and copy the product ID from the listing."
  }
}

variable "domain" {
  type        = string
  description = "Hostname operators use for BETTER_AUTH_URL. Defaults to the internal ALB DNS name when empty."
  default     = ""
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the internal ALB. Use a VPN or shared-services CIDR. Default is the VPC CIDR only. 0.0.0.0/0 and ::/0 are rejected."
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.allowed_ingress_cidrs : (
        can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0" && cidr != "::/0"
      )
    ])
    error_message = "allowed_ingress_cidrs must be specific CIDRs. The stack is VPC-internal; 0.0.0.0/0 and ::/0 are not allowed."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.80.0.0/16"
}

variable "app_cpu" {
  type    = number
  default = 1024
}

variable "app_memory" {
  type        = number
  default     = 2048
  description = "Fargate task memory in MiB. COD needs at least 2 GiB."

  validation {
    condition     = var.app_memory >= 2048
    error_message = "app_memory must be at least 2048 MiB (2 GiB)."
  }
}

variable "worker_cpu" {
  type    = number
  default = 1024
}

variable "worker_memory" {
  type        = number
  default     = 2048
  description = "Fargate worker memory in MiB. COD needs at least 2 GiB."

  validation {
    condition     = var.worker_memory >= 2048
    error_message = "worker_memory must be at least 2048 MiB (2 GiB)."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t4g.small"
}

variable "certificate_arn" {
  type        = string
  description = "Optional ACM certificate ARN. Empty keeps HTTP on the internal ALB for VPC-only access."
  default     = ""
}
