terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  project_name      = var.project_name
  environment       = var.environment
  enable_ecs        = var.enable_ecs
  enable_ec2        = var.enable_ec2
  normalized_domain = lower(trimspace(var.domain_name))
  domain_specified  = local.normalized_domain != ""
  domain_display    = local.domain_specified ? local.normalized_domain : "localhost"
  fallback_domain   = local.domain_specified ? local.normalized_domain : "localhost"
  admin_email       = var.admin_email

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}
