# COD Helm chart

Deploys the COD app and worker on Amazon EKS. Does **not** create RDS or ElastiCache.

App and worker default to **2Gi** memory. Set `args`, not `command`, so the image entrypoint still runs migrate.

`marketplace.productCode` and `marketplace.productSku` are required. The image checks AWS Marketplace entitlement at boot. Attach `license-manager:CheckoutLicense` (and Get/Extend/List) to the pod role. There is no skip flag.

See the repository [README](../../README.md#4-amazon-eks) for the install command.
