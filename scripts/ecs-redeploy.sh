#!/usr/bin/env bash
# Pin running ECS/Fargate services to a new image digest and force a
# deployment. Watchtower cannot do this: Fargate has no docker.sock.
#
# Usage:
#   AWS_REGION=ap-southeast-2 \
#   ./scripts/ecs-redeploy.sh <cluster> <svc1,svc2> <image@sha256:digest>
#
# Replaces container images whose URI contains ECS_IMAGE_MATCH (default
# compliance-on-demand). COD Marketplace stacks pass the Marketplace ECR digest.

set -euo pipefail

CLUSTER="${1:?cluster name}"
SERVICES_CSV="${2:?comma-separated service names}"
IMAGE="${3:?image URI, preferably @sha256:...}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-2}}"
MATCH="${ECS_IMAGE_MATCH:-compliance-on-demand}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 1
fi

log() { printf '[ecs-redeploy] %s\n' "$*"; }

IFS=',' read -r -a SERVICES <<<"$SERVICES_CSV"
updated=()

for raw in "${SERVICES[@]}"; do
  svc="${raw// /}"
  [[ -n "$svc" ]] || continue

  td_arn="$(aws ecs describe-services \
    --region "$REGION" \
    --cluster "$CLUSTER" \
    --services "$svc" \
    --query 'services[0].taskDefinition' \
    --output text)"

  if [[ -z "$td_arn" || "$td_arn" == "None" ]]; then
    echo "service not found: cluster=$CLUSTER service=$svc" >&2
    exit 1
  fi

  td_json="$(aws ecs describe-task-definition \
    --region "$REGION" \
    --task-definition "$td_arn" \
    --query 'taskDefinition' \
    --output json)"

  matches="$(jq --arg m "$MATCH" '[.containerDefinitions[].image | select(test($m))] | length' <<<"$td_json")"
  if [[ "$matches" -eq 0 ]]; then
    echo "no container image matched /$MATCH/ in $td_arn" >&2
    jq -r '.containerDefinitions[] | "  " + .name + " " + .image' <<<"$td_json" >&2
    exit 1
  fi

  new_json="$(jq --arg image "$IMAGE" --arg m "$MATCH" '
    del(
      .taskDefinitionArn,
      .revision,
      .status,
      .requiresAttributes,
      .compatibilities,
      .registeredAt,
      .registeredBy,
      .deregisteredAt
    )
    | .containerDefinitions |= map(
        if (.image | test($m)) then .image = $image else . end
      )
  ' <<<"$td_json")"

  new_arn="$(aws ecs register-task-definition \
    --region "$REGION" \
    --cli-input-json "$new_json" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)"

  aws ecs update-service \
    --region "$REGION" \
    --cluster "$CLUSTER" \
    --service "$svc" \
    --task-definition "$new_arn" \
    --force-new-deployment \
    --query 'service.serviceName' \
    --output text >/dev/null

  log "updated $svc -> $new_arn"
  updated+=("$svc")
done

if [[ ${#updated[@]} -eq 0 ]]; then
  echo "no services given" >&2
  exit 1
fi

log "waiting for stable: ${updated[*]}"
aws ecs wait services-stable \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --services "${updated[@]}"
log "stable"
