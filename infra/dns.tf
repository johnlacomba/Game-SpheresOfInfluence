locals {
  manage_zone = local.domain_specified
}

resource "aws_route53_zone" "primary" {
  count = local.manage_zone ? 1 : 0

  name          = local.normalized_domain
  comment       = "Public hosted zone for ${local.project_name}"
  force_destroy = false

  tags = {
    Name = "${local.project_name}-zone"
  }
}

resource "aws_route53_record" "apex_eip" {
  count = local.manage_zone && !local.enable_ecs && local.enable_ec2 ? 1 : 0

  zone_id = aws_route53_zone.primary[0].zone_id
  name    = local.normalized_domain
  type    = "A"
  ttl     = 60
  records = [aws_eip.host[0].public_ip]
}

resource "aws_route53_record" "apex_alb" {
  count = local.manage_zone && local.enable_ecs ? 1 : 0

  zone_id = aws_route53_zone.primary[0].zone_id
  name    = local.normalized_domain
  type    = "A"

  alias {
    name                   = aws_lb.main[0].dns_name
    zone_id                = aws_lb.main[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "www" {
  count = local.manage_zone && !local.enable_ecs && local.enable_ec2 ? 1 : 0

  zone_id = aws_route53_zone.primary[0].zone_id
  name    = "www"
  type    = "CNAME"
  ttl     = 300
  records = [local.normalized_domain]
}

resource "aws_route53_record" "www_alb" {
  count = local.manage_zone && local.enable_ecs ? 1 : 0

  zone_id = aws_route53_zone.primary[0].zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_lb.main[0].dns_name
    zone_id                = aws_lb.main[0].zone_id
    evaluate_target_health = true
  }
}
