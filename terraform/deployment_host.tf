resource "aws_iam_role" "host" {
  count = local.enable_ec2 ? 1 : 0

  name = "${local.project_name}-host-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "host_ssm" {
  count = local.enable_ec2 ? 1 : 0

  role       = aws_iam_role.host[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "host" {
  count = local.enable_ec2 ? 1 : 0

  name = "${local.project_name}-host-profile"
  role = aws_iam_role.host[0].name
}

resource "aws_instance" "host" {
  count = local.enable_ec2 ? 1 : 0

  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.host_instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name
  iam_instance_profile        = aws_iam_instance_profile.host[0].name
  vpc_security_group_ids      = [aws_security_group.host[0].id]

  root_block_device {
    volume_size = var.host_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    project_name          = local.project_name
    domain_name           = local.normalized_domain
    fallback_domain       = local.fallback_domain
    domain_display        = local.domain_display
    admin_email           = local.admin_email
    git_repo_url          = var.git_repo_url
    git_branch            = var.git_branch
    deployment_mode       = var.deployment_mode
    cognito_region        = var.aws_region
    cognito_user_pool_id  = aws_cognito_user_pool.main.id
    cognito_app_client_id = aws_cognito_user_pool_client.main.id
    auto_deploy           = var.auto_deploy_on_boot ? "true" : "false"
    additional_commands   = var.user_data_additional_commands
  })

  tags = local.common_tags
}

resource "aws_eip" "host" {
  count = local.enable_ec2 ? 1 : 0

  domain = "vpc"

  depends_on = [aws_instance.host]

  tags = local.common_tags
}

resource "aws_eip_association" "host" {
  count = local.enable_ec2 ? 1 : 0

  instance_id   = aws_instance.host[0].id
  allocation_id = aws_eip.host[0].id
}

data "aws_ami" "amazon_linux" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
