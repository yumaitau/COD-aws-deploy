# COD AWS deploy

Buyer-hosted [Compliance on Demand (COD)](https://complianceondemand.com.au) on AWS. Subscribe on AWS Marketplace **before** you pull the image or create a stack. The publisher does not host your data.

This repository is Terraform, CloudFormation, Helm, ECS task definitions, and deploy scripts. The application image lives in AWS Marketplace ECR after you subscribe.

AWS Marketplace always shows `docker login` + `docker pull` for container listings. That snippet only proves the subscription can pull the image. It does not create a VPC, ECS, RDS, Redis, or IAM. Use this repo to launch the product.

The default stack is **VPC-internal**: internal ALB, no public IPs on tasks, ALB ingress limited to the VPC CIDR (or a VPN / shared-services CIDR you pass in). `0.0.0.0/0` and `::/0` are rejected. It is not published to the internet.

## Choose a template

Start with `terraform/` unless you already know you need the Well-Architected extras. That optional stack costs more (dual NAT, WAF, secret rotation). Keep one app task — the Marketplace seat is `Count=1`.

| Path | Use when |
| --- | --- |
| [`terraform/`](terraform/) | **Default.** One NAT, Multi-AZ RDS and Redis, CMK, flow logs, ALB access logs, one app task, 2 GiB task memory. Checkov reports zero failed checks. |
| [`cloudformation/cod-fargate.yaml`](cloudformation/cod-fargate.yaml) | Lean stack in the AWS console or CLI (single-AZ, no CMK). |
| [`terraform-well-architected/`](terraform-well-architected/) | **Optional.** Dual NAT, WAF, and Secrets Manager rotation on top of the default controls. |
| [`charts/cod/`](charts/cod/) | EKS. You still provision RDS + ElastiCache yourself. |
| [`ecs/`](ecs/) | Sample Fargate task definitions matching the lean stack. |
| [`scripts/ecs-redeploy.sh`](scripts/ecs-redeploy.sh) | Pin running services to a new image digest. |

App and worker **base memory is 2 GiB**. Terraform rejects a lower Fargate size. Helm requests and limits default to `2Gi`.

```
                    VPN / DX / SSM
                          |
                   +------v------+
                   | Internal ALB|
                   +------+------+
                          |
              +-----------+-----------+
              |                       |
         +----v----+            +-----v-----+
         | COD app |            | COD worker|
         |  2 GiB  |            |   2 GiB   |
         +----+----+            +-----+-----+
              |                       |
         +----v----+            +-----v-----+
         |   RDS   |            |   Redis   |
         | Postgres|            | ElastiCache|
         +---------+            +-----------+
```

NAT is only for outbound scans (cloud and SaaS APIs). Tasks themselves have no public IP.

## Prerequisites

- An AWS account and credentials that can create VPC, ECS, RDS, ElastiCache, IAM, and Secrets Manager
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2
- Terraform >= 1.6 **or** permission to upload CloudFormation
- A Marketplace subscription to COD
- The Marketplace ECR image digest (`…@sha256:<64 hex>`) or immutable tag (`:1.0.N`)
- The signed COD license JWT issued for this buyer
- A path into the VPC: VPN, Direct Connect, or ECS Exec / SSM

Supported regions: Australia only — `ap-southeast-2` (Sydney, default) or `ap-southeast-4` (Melbourne). Marketplace ECR remains in `us-east-1` because AWS hosts that registry.

## 1. ECS Fargate — Terraform (default)

```sh
git clone https://github.com/yumaitau/COD-aws-deploy.git
cd COD-aws-deploy/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

1. Set `container_image` to the Marketplace ECR digest or immutable tag. `latest` is rejected.
2. Set `license_key` to the signed JWT. Do not commit the real value.
3. Leave `domain` empty to use the internal ALB DNS name, or set the hostname operators will type.
4. Leave `allowed_ingress_cidrs` empty to allow only the VPC CIDR. Add a VPN or shared-services CIDR if you have one. Do not use `0.0.0.0/0`.
5. Optionally set `certificate_arn` for HTTPS on the internal ALB.

```sh
terraform init
terraform apply
terraform output setup_url
aws secretsmanager get-secret-value --secret-id "$(terraform output -raw runtime_secret_arn)" \
  --query SecretString --output text
```

The stack does not print secrets. Pull the setup token from Secrets Manager, then open `/setup` from a VPC path.

Health from the app task:

```sh
aws ecs execute-command \
  --cluster "$(terraform output -raw ecs_cluster_name)" \
  --task <app-task-id> \
  --container app \
  --interactive \
  --command "curl -sS 'http://127.0.0.1:3000/api/health?probe=live'"
```

What the default stack creates:

- VPC with public, private, and data subnets in two AZs (ALB needs two subnets)
- One NAT gateway
- Internal ALB, drop-invalid-headers on
- ECS Fargate cluster: `cod-app` (desired 1) and `cod-worker` (desired 1), 1024 CPU / 2048 MiB each
- RDS PostgreSQL 16, private, encrypted, `rds.force_ssl=1`, `sslmode=verify-full`
- ElastiCache Redis 7.1, in-transit and at-rest encryption, AUTH token
- Secrets Manager runtime secret (license, setup token, DB URL, Redis URL, session and encryption keys)
- CloudWatch log groups, 30-day retention
- ECS Exec on both services
- Encrypted EFS at `/app/data` so the app and worker share assessor packs, security documents, and branding (Compose used local named volumes on one host)
- Private S3 bucket for nightly Postgres dumps (`terraform output backup_bucket`, `ALIGNR_BACKUP_DESTINATION=s3://…/nightly`)
- S3 bucket for SBOM CLI binaries (`terraform output sbom_cli_bucket`). The Marketplace image does not ship those binaries. Copy signed files into `terraform/sbom-cli/` (names `cod-sbom-darwin-arm64`, `cod-sbom-darwin-amd64`, `cod-sbom-windows-amd64.exe`) before apply, or `aws s3 cp` them to `s3://<bucket>/sbom-cli/` after.

Destroy is a plain `terraform destroy`. Secrets use a 0-day recovery window so the stack can tear down cleanly.

Full variable notes: [`terraform/README.md`](terraform/README.md).

## 2. ECS Fargate — CloudFormation

Same lean stack as the default Terraform. No Well-Architected extras.

Console: Create stack → Upload `cloudformation/cod-fargate.yaml` → set **ContainerImage** and **LicenseKey** → acknowledge IAM → Create.

CLI:

```sh
cd cloudformation
cp parameters.example.json parameters.json
# edit ContainerImage and LicenseKey

aws cloudformation deploy \
  --region ap-southeast-2 \
  --stack-name compliance-on-demand \
  --template-file cod-fargate.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $(python3 -c 'import json; print(" ".join("%s=%s" % (p["ParameterKey"], p["ParameterValue"]) for p in json.load(open("parameters.json"))))')
```

Details: [`cloudformation/README.md`](cloudformation/README.md).

## 3. Optional Well-Architected Terraform

Same variables as the default. Higher AWS spend. Do not start here.

Adds:

- NAT per AZ, Multi-AZ Postgres and Redis
- Customer-managed KMS for RDS, Redis, Secrets, and logs
- WAF on the internal ALB
- VPC flow logs, ALB access logs, 365-day encrypted logs
- RDS Performance Insights and enhanced monitoring
- Secrets Manager rotation of the **Postgres password only** (session and encryption keys stay put)
- RDS and ALB deletion protection

```sh
cd terraform-well-architected
cp terraform.tfvars.example terraform.tfvars
# set container_image and license_key
terraform init
terraform apply
```

Before destroy, turn off deletion protection on RDS and the ALB, then apply, then destroy. Secrets keep a 7-day recovery window. RDS writes `<name-prefix>-pg-final`.

After the first apply, Terraform ignores later secret-string drift so a password rotation is not overwritten. Update the license JWT in Secrets Manager, not by re-applying tfvars.

Details: [`terraform-well-architected/README.md`](terraform-well-architected/README.md).

## 4. Amazon EKS

Helm does **not** create RDS or Redis. Provision those first (private subnets, TLS, AUTH on Redis), then:

```sh
helm upgrade --install cod charts/cod --namespace cod --create-namespace \
  --set image.repository='<marketplace-ecr>' \
  --set image.digest='sha256:<digest>' \
  --set licenseKey='<signed-jwt>' \
  --set databaseUrl='postgresql://cod:...@...:5432/cod?schema=public&sslmode=verify-full' \
  --set redisUrl='rediss://:...@...:6379' \
  --set domain='cod.example.com'
```

Set `args`, not `command`, so the image entrypoint still runs migrate. Default `arch: amd64` matches the Fargate stack. App and worker request **2Gi** memory. Keep both replica counts at 1. Persistence needs an RWX StorageClass (EFS CSI) so app and worker share `/app/data`.

Terminate HTTPS on your Ingress or load balancer. The chart ships a ClusterIP Service on port 3000.

## First admin

1. Subscribe and deploy.
2. Read the runtime secret (`ALIGNR_SETUP_TOKEN`).
3. From a VPC path, open `http(s)://<internal-alb>/setup` (or tunnel to `127.0.0.1:3000` via ECS Exec).
4. Create the first admin with that token.

Settings shows a licence fingerprint only. It never prints the raw JWT.

## Licence and image pin

- Subscribe on AWS Marketplace before you pull or deploy. The image calls License Manager `CheckoutLicense` (`standard_workspace` Count=1) at boot and `AWS::Marketplace::Usage` every 15 minutes. Product identity is baked into the image. There is no skip flag.
- Pin a Marketplace ECR digest (`@sha256:…`) or immutable tag (`:1.0.N` or `:sha-<7>`). Templates reject `latest`.
- Pass the signed JWT as `license_key` / `LicenseKey`. Store it in Secrets Manager.

RDS connections use `sslmode=verify-full` with the Amazon RDS global CA bundle baked into the image (`NODE_EXTRA_CA_CERTS` / `PGSSLROOTCERT`).

## Updates

Watchtower is not used. Fargate has no Docker socket.

```sh
# Terraform: change container_image, then
terraform apply

# CloudFormation
aws cloudformation deploy \
  --region ap-southeast-2 \
  --stack-name compliance-on-demand \
  --template-file cloudformation/cod-fargate.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ContainerImage='<marketplace-ecr>@sha256:<digest>'

# Existing cluster, no template apply
AWS_REGION=ap-southeast-2 \
  ./scripts/ecs-redeploy.sh <cluster> <name-prefix>-app,<name-prefix>-worker \
  '<ecr>@sha256:<digest>'
```

`ecs-redeploy.sh` rewrites task definitions whose image URI contains `compliance-on-demand` (override with `ECS_IMAGE_MATCH`) and waits for the services to stabilize. See [`scripts/README.md`](scripts/README.md).

## Size and cost

| Resource | Default | Well-Architected |
| --- | --- | --- |
| App / worker memory | 2 GiB (minimum) | 2 GiB (minimum) |
| NAT | 1 | 1 per AZ |
| RDS | `db.t4g.medium`, single-AZ | Multi-AZ, PI, enhanced monitoring |
| Redis | `cache.t4g.small`, 1 node | 2 nodes, automatic failover |
| Logs | 30 days | 365 days + KMS + flow logs + ALB logs |
| WAF / CMK / rotation | off | on |

You pay AWS directly for Fargate, ALB, NAT, RDS, ElastiCache, Secrets Manager, CloudWatch, and (optional stack) WAF, KMS, and extra NAT. Marketplace contract charges are separate.

## Destroy / unsubscribe

Cancel the Marketplace subscription **and** delete the stack. Scan data, evidence, and Postgres stay in the buyer account until you destroy or snapshot those resources.

```sh
# Default Terraform
cd terraform && terraform destroy

# CloudFormation
aws cloudformation delete-stack --stack-name compliance-on-demand

# Well-Architected Terraform — disable deletion protection first, then
cd terraform-well-architected && terraform destroy
```

## Image environment

The COD image reads these process environment names. Terraform, CloudFormation, and Helm set them for you.

| Name | Purpose |
| --- | --- |
| `DATABASE_URL` | RDS Postgres (`sslmode=verify-full`) |
| `REDIS_URL` | ElastiCache (BullMQ), `rediss://` |
| `BETTER_AUTH_SECRET` | Session signing |
| `ENCRYPTION_MASTER_KEY` | AES-256 for integration credentials |
| `ALIGNR_LICENSE_KEY` | Signed license JWT |
| `ALIGNR_SETUP_TOKEN` | One-time first admin |
| `ALIGNR_INSTALL_ID` | Binds cached licence attestations to this deploy |
| `ALIGNR_DOMAIN` | Hostname for links and cookies |
| `HOSTNAME` / `PORT` | `0.0.0.0:3000` |

Health: `GET /api/health` — 200 when the database is up and the licence is not locked; 503 if the licence is locked or the system is critical.

Do not put long-lived AWS keys in the task definition. Per-workspace cloud-scan credentials are stored encrypted in Postgres.

## IAM

| Role | Purpose |
| --- | --- |
| Execution | Pull the image, write logs, `secretsmanager:GetSecretValue` |
| Task | ECS Exec (`ssmmessages:*`) and License Manager (`CheckoutLicense`, `GetLicense`, `CheckInLicense`, `ExtendLicenseConsumption`, `ListReceivedLicenses`; Resource `*` is required by AWS). Attach extra policies in the buyer account if tasks must call your own AWS APIs |

## CI

Pushes and pull requests to `main` run [`.github/workflows/security.yml`](.github/workflows/security.yml): Terraform fmt and validate, Helm lint, Checkov, Gitleaks, and Trivy.

## Support

https://complianceondemand.com.au
