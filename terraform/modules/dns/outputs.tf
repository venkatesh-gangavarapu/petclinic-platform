output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "zone_name" {
  description = "Route 53 hosted zone domain name"
  value       = aws_route53_zone.main.name
}

output "zone_name_servers" {
  description = "Route 53 nameservers - update these in your domain registrar (Namecheap)"
  value       = aws_route53_zone.main.name_servers
}

output "certificate_arn" {
  description = "Validated ACM certificate ARN (use in ALB Ingress annotations)"
  value       = aws_acm_certificate_validation.main.certificate_arn
}
