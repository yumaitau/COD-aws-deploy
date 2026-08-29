# COD Terraform (default)

Lean buyer stack: VPC, one NAT, internal ALB, ECS Fargate (app + worker), single-AZ RDS Postgres 16, ElastiCache Redis, Secrets Manager.

This is the template most buyers should run. For Multi-AZ, CMK, WAF, and log/audit extras see [`../terraform-well-architected/`](../terraform-well-architected/).

```sh
cp terraform.tfvars.example terraform.tfvars
# set container_image, license_key, marketplace_product_code, marketplace_product_sku
terraform init
terraform apply
```

Required: `container_image` (sha256 digest), `license_key`, `marketplace_product_code`, and `marketplace_product_sku`. There is no license bypass.

Optional: `domain`, `certificate_arn`, `allowed_ingress_cidrs` (VPN / shared-services; never `0.0.0.0/0`).

Destroy is a plain `terraform destroy`. Secrets are created with a 0-day recovery window so the stack can tear down cleanly.
