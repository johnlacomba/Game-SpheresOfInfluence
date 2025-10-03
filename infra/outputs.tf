output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "Cognito User Pool client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_domain" {
  description = "Cognito hosted UI domain"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = local.enable_ecs ? aws_lb.main[0].dns_name : ""
}

output "frontend_url" {
  description = "Public URL for the frontend"
  value = local.enable_ecs ? "http://${aws_lb.main[0].dns_name}" : (
    local.enable_ec2 && local.domain_specified ? "https://${local.normalized_domain}" : (
      local.enable_ec2 ? "http://${aws_eip.host[0].public_ip}" : ""
    )
  )
}

output "backend_url" {
  description = "Public URL for the backend"
  value = local.enable_ecs ? "http://${aws_lb.main[0].dns_name}:8080" : (
    local.enable_ec2 && local.domain_specified ? "https://${local.normalized_domain}/api" : (
      local.enable_ec2 ? "http://${aws_eip.host[0].public_ip}:8080" : ""
    )
  )
}

output "ec2_public_ip" {
  description = "Public IP assigned to the EC2 deployment host"
  value       = local.enable_ec2 ? aws_eip.host[0].public_ip : ""
}

output "ec2_instance_id" {
  description = "Instance ID of the EC2 deployment host"
  value       = local.enable_ec2 ? aws_instance.host[0].id : ""
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.domain_specified ? aws_route53_zone.primary[0].zone_id : ""
}

output "route53_name_servers" {
  description = "Nameservers for the hosted zone"
  value       = local.domain_specified ? aws_route53_zone.primary[0].name_servers : []
}
