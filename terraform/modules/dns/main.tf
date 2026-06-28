# ── Route 53 Hosted Zone ──────────────────────────────────────────────────────

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name      = var.domain_name
    Component = "dns"
  }
}

# ── ACM Certificate (wildcard) ────────────────────────────────────────────────
# Wildcard covers all subdomains (petclinic-dev.domain, petclinic.domain, etc.)
# SAN on the apex domain covers direct access to the root if needed.

resource "aws_acm_certificate" "main" {
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  tags = {
    Name      = "${var.project}-${var.environment}-cert"
    Component = "dns"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── DNS Validation Records ────────────────────────────────────────────────────
# ACM requires CNAME records in the hosted zone to prove domain ownership.
# for_each deduplicates validation options (wildcard + apex share one record).

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

# ── Wait for Certificate Validation ──────────────────────────────────────────
# Blocks until ACM confirms DNS validation is complete (~2 min after NS switch).

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
