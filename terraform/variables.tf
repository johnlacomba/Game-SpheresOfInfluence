variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Base name for all resources"
  type        = string
  default     = "spheres-of-influence"
}

variable "environment" {
  description = "Environment name included in tagged resources"
  type        = string
  default     = "production"
}

variable "enable_ec2" {
  description = "Provision an EC2 host for the Docker deployment"
  type        = bool
  default     = true
}

variable "enable_ecs" {
  description = "Provision the optional ECS/Fargate deployment"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Primary domain name for the application"
  type        = string
  default     = "sphereofinfluence.click"
}

variable "admin_email" {
  description = "Administrative email used for certificate issuance and notifications"
  type        = string
  default     = "admin@sphereofinfluence.click"
}

variable "deployment_mode" {
  description = "Deployment mode passed to quick-deploy.sh"
  type        = string
  default     = "production"
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name attached to the host"
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_ec2 || length(trimspace(var.ssh_key_name)) > 0
    error_message = "ssh_key_name must be provided when enable_ec2 is true."
  }
}

variable "host_instance_type" {
  description = "Instance type for the EC2 deployment host"
  type        = string
  default     = "t3.small"
}

variable "host_root_volume_size" {
  description = "Root volume size (GiB) for the EC2 host"
  type        = number
  default     = 50
}

variable "allowed_cidrs_http" {
  description = "CIDR blocks allowed to access HTTP (80)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_cidrs_https" {
  description = "CIDR blocks allowed to access HTTPS (443)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_cidrs_ssh" {
  description = "CIDR blocks allowed to access SSH (22)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "git_repo_url" {
  description = "Repository URL cloned on the EC2 host"
  type        = string
  default     = "https://github.com/johnlacomba/Game-SpheresOfInfluence.git"
}

variable "git_branch" {
  description = "Branch checked out during deployment"
  type        = string
  default     = "main"
}

variable "auto_deploy_on_boot" {
  description = "Run quick-deploy automatically after instance bootstrap"
  type        = bool
  default     = false
}

variable "user_data_additional_commands" {
  description = "Optional bash commands appended to the EC2 user data script"
  type        = string
  default     = ""
}

variable "cognito_domain_prefix" {
  description = "Unique prefix for the Cognito hosted UI domain"
  type        = string
}

variable "oauth_callback_urls" {
  description = "Allowed callback URLs for the Cognito hosted UI"
  type        = list(string)
  default     = []
}

variable "oauth_logout_urls" {
  description = "Allowed logout URLs for the Cognito hosted UI"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones used for public subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.40.10.0/24", "10.40.11.0/24"]
}

variable "backend_image" {
  description = "ECR image URI for the backend container"
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_ecs || length(trimspace(var.backend_image)) > 0
    error_message = "backend_image must be provided when enable_ecs is true."
  }
}

variable "frontend_image" {
  description = "ECR image URI for the frontend container"
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_ecs || length(trimspace(var.frontend_image)) > 0
    error_message = "frontend_image must be provided when enable_ecs is true."
  }
}

variable "desired_count" {
  description = "Desired task count for ECS services"
  type        = number
  default     = 2
}

variable "game_tick_ms" {
  description = "Tick duration in milliseconds"
  type        = number
  default     = 1000
}

variable "game_width" {
  description = "Width of the game board"
  type        = number
  default     = 64
}

variable "game_height" {
  description = "Height of the game board"
  type        = number
  default     = 64
}

variable "game_resource_tiles" {
  description = "Number of resource tiles to seed"
  type        = number
  default     = 220
}
