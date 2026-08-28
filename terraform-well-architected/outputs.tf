output "internal_alb_dns_name" {
  description = "Internal ALB hostname. Open http(s)://<this>/setup from a VPC path, or tunnel to 127.0.0.1:3000."
  value       = aws_lb.app.dns_name
}

output "setup_url" {
  description = "First-admin URL using the internal ALB."
  value       = "${var.certificate_arn != "" ? "https" : "http"}://${var.domain != "" ? var.domain : aws_lb.app.dns_name}/setup"
}

output "runtime_secret_arn" {
  description = "Secrets Manager ARN holding generated runtime secrets. Retrieve the setup token from the runtime secret. Values are not printed."
  value       = aws_secretsmanager_secret.runtime.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_app_service_name" {
  value = aws_ecs_service.app.name
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "unsubscribe_note" {
  value = "Unsubscribe = delete this stack. Postgres, Redis, and evidence stay in the buyer account until you destroy those resources or take a snapshot."
}

output "access_note" {
  value = "This stack is VPC-internal. Reach /setup from a VPN, shared-services CIDR, or SSM port-forward. It is not published to the internet."
}

output "destroy_note" {
  value = "Before terraform destroy, set deletion_protection=false on the RDS instance and enable_deletion_protection=false on the ALB, then apply. Secrets keep a 7-day recovery window. RDS writes a final snapshot named <name-prefix>-pg-final."
}
