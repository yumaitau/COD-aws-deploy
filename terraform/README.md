# COD Terraform (default)

Lean buyer stack: VPC, one NAT, internal ALB, ECS Fargate (app + worker), single-AZ RDS Postgres 16, ElastiCache Redis, Secrets Manager.

This is the template most buyers should run. For Multi-AZ, CMK, WAF, and log/audit extras see [`../terraform-well-architected/`](../terraform-well-architected/).

```sh
cp terraform.tfvars.example terraform.tfvars
# set container_image and license_key
terraform init
terraform apply
```

Required: `container_image` (sha256 digest) and `license_key`.

Optional: `domain`, `certificate_arn`, `allowed_ingress_cidrs` (VPN / shared-services; never `0.0.0.0/0`).

Destroy is a plain `terraform destroy`. Secrets are created with a 0-day recovery window so the stack can tear down cleanly.
