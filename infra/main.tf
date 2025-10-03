provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  project_name      = var.project_name
  enable_ecs        = var.enable_ecs
  enable_ec2        = var.enable_ec2
  normalized_domain = lower(trimspace(var.domain_name))
  domain_specified  = local.normalized_domain != ""
}
