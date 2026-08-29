# COD CloudFormation (default)

Lean buyer stack matching [`../terraform/`](../terraform/). Upload `cod-fargate.yaml` in the CloudFormation console or use the AWS CLI.

```sh
aws cloudformation deploy \
  --region ap-southeast-2 \
  --stack-name compliance-on-demand \
  --template-file cod-fargate.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ContainerImage='<marketplace-ecr>@sha256:<digest>' \
    LicenseKey='<signed-jwt>' \
    MarketplaceProductCode='<listing-product-code>' \
    MarketplaceProductSku='<listing-product-id>'
```

The stack is VPC-internal. Reach `/setup` from a VPN or ECS Exec. `latest` image tags are rejected.

For Multi-AZ, CMK, WAF, and the rest of the Well-Architected extras, use [`../terraform-well-architected/`](../terraform-well-architected/).
