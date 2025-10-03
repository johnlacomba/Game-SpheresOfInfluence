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

variable "enable_ec2" {
  description = "Provision an EC2 host that runs the Docker stack"
  type        = bool
  default     = true
}

variable "enable_ecs" {
  description = "Provision the ECS/Fargate deployment"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Primary domain name to serve the game from"
  type        = string
  default     = "sphereofinfluence.click"
}

variable "admin_email" {
  description = "Administrative email used for certificate issuance and notifications"
  type        = string
  default     = "admin@sphereofinfluence.click"
}

variable "deployment_mode" {
  description = "Deployment mode passed to quick-deploy.sh (development | production)"
  type        = string
  default     = "production"
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name to attach to the host"
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_ec2 || length(trim(var.ssh_key_name)) > 0
    error_message = "ssh_key_name must be provided when enable_ec2 is true."
  }
}

variable "host_instance_type" {
  description = "Instance type for the EC2 host"
  type        = string
  default     = "t3.small"
}

variable "host_root_volume_size" {
  description = "Root volume size (GiB) for the EC2 host"
  type        = number
  default     = 50
}

variable "allowed_cidrs_http" {
  description = "CIDR blocks allowed to access HTTP (port 80)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_cidrs_https" {
  description = "CIDR blocks allowed to access HTTPS (port 443)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_cidrs_ssh" {
  description = "CIDR blocks allowed to access SSH (port 22)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "git_repo_url" {
  description = "Repository URL cloned on the EC2 host"
  type        = string
  default     = "https://github.com/johnlacomba/Game-SpheresOfInfluence.git"
}

variable "git_branch" {
  description = "Branch to checkout for deployment"
  type        = string
  default     = "main"
}

variable "auto_deploy_on_boot" {
  description = "Run quick-deploy automatically during instance bootstrap"
  type        = bool
  default     = false
}

variable "user_data_additional_commands" {
  description = "Optional bash commands appended to the EC2 user data script"
  type        = string
  default     = ""
}


variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use"
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
    condition     = !var.enable_ecs || length(trim(var.backend_image)) > 0
    error_message = "backend_image must be provided when enable_ecs is true."
  }
}

variable "frontend_image" {
  description = "ECR image URI for the frontend container"
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_ecs || length(trim(var.frontend_image)) > 0
    error_message = "frontend_image must be provided when enable_ecs is true."
  }
}

variable "desired_count" {
  description = "Desired task count for each ECS service"
  type        = number
  default     = 2
}

variable "cognito_domain_prefix" {
  description = "Unique prefix for the Cognito hosted UI domain"
  type        = string
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

variable "oauth_callback_urls" {
  description = "Allowed callback URLs for Cognito hosted UI"
  type        = list(string)
  default     = []
}

variable "oauth_logout_urls" {
  description = "Allowed logout URLs for Cognito hosted UI"
  type        = list(string)
  default     = []
}
