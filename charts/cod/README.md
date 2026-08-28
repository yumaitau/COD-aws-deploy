# COD Helm chart

Deploys the COD app and worker on Amazon EKS. Does **not** create RDS or ElastiCache.

App and worker default to **2Gi** memory. Set `args`, not `command`, so the image entrypoint still runs migrate.

See the repository [README](../../README.md#4-amazon-eks) for the install command.
