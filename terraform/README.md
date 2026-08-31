# COD Terraform (default)

Buyer stack: VPC, one NAT, internal ALB, ECS Fargate (app + worker), Multi-AZ RDS Postgres 16, Multi-AZ ElastiCache Redis, customer-managed KMS, VPC flow logs, and ALB access logs.

This is the template most buyers should run. `checkov -d terraform --config-file terraform/.checkov.yaml` reports zero failed checks. NAT egress (`CKV_AWS_382`) and License Manager `Resource *` (`CKV_AWS_355`) are documented skips because AWS requires them. Secret rotation, dual NAT, WAF, and a second app task stay in [`../terraform-well-architected/`](../terraform-well-architected/).

```sh
cp terraform.tfvars.example terraform.tfvars
# set container_image and license_key
terraform init
terraform apply
```

Required: `container_image` (digest or immutable tag) and `license_key`. Marketplace entitlement is enforced by the image. There is no license bypass.

Optional: `domain`, `certificate_arn`, `allowed_ingress_cidrs` (VPN / shared-services; never `0.0.0.0/0`).

RDS and the ALB have deletion protection on. Before `terraform destroy`:

1. Set `deletion_protection = false` on the RDS instance and `enable_deletion_protection = false` on the ALB
2. `terraform apply`
3. `terraform destroy`

Secrets keep a 7-day recovery window. RDS writes a final snapshot named `<name-prefix>-pg-final`.
