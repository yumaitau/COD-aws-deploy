# Scripts

## `ecs-redeploy.sh`

Pins running ECS/Fargate services to a new Marketplace image digest and waits until the services are stable. Fargate has no Docker socket, so Watchtower cannot roll images.

```sh
AWS_REGION=ap-southeast-2 \
  ./scripts/ecs-redeploy.sh \
    <cluster> \
    <name-prefix>-app,<name-prefix>-worker \
    '<marketplace-ecr>@sha256:<digest>'
```

By default the script only rewrites container images whose URI contains `compliance-on-demand`. Override with `ECS_IMAGE_MATCH` if your repository name is different.

Requires `aws` and `jq`.
