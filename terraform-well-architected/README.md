# COD Terraform — Well-Architected (optional)

Opt-in template. Higher AWS spend than [`../terraform/`](../terraform/). Use this when you already need Multi-AZ and the extra controls; do not start here.

Adds:

- **Reliability:** NAT per AZ, Multi-AZ RDS and Redis, two app tasks, deletion protection, final snapshot
- **Security:** customer-managed KMS, forced Postgres TLS, IAM DB auth, WAF, VPC flow logs, 365-day encrypted logs
- **Operational excellence:** ALB access logs, Performance Insights, enhanced monitoring, Postgres DDL/slow-query logs
- **Rotation:** Secrets Manager rotates the Postgres password only. Session and encryption keys are never rotated.

Same `terraform.tfvars` shape as the default stack (`container_image`, `license_key`, `marketplace_product_code`, `marketplace_product_sku`, `domain`, `allowed_ingress_cidrs`). There is no license bypass.

## Destroy

RDS and the ALB have deletion protection on. Before `terraform destroy`:

1. Set `deletion_protection = false` on the RDS instance and `enable_deletion_protection = false` on the ALB
2. `terraform apply`
3. `terraform destroy`

Secrets keep a 7-day recovery window. RDS writes a final snapshot named `<name-prefix>-pg-final`.

After the first apply, Terraform ignores later `secret_string` drift so a password rotation is not overwritten. Update the license JWT in Secrets Manager, not by re-applying tfvars.
