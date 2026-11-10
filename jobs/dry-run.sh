#!/usr/bin/env bash
# Validate only. This script never creates a cloud resource.
set -euo pipefail
export AI_AGENT="${AI_AGENT:-cookbook}"
: "${NEBIUS_PROJECT_ID:?Set NEBIUS_PROJECT_ID to your selected project}"
: "${NEBIUS_SUBNET_ID:?Set NEBIUS_SUBNET_ID to an existing subnet}"
: "${NEBIUS_PRICING_POLICY_ID:?Set NEBIUS_PRICING_POLICY_ID to an H100 pricing policy}"
root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"
nebius ai job create \
  --parent-id "$NEBIUS_PROJECT_ID" \
  --name preemptible-cuda-guide \
  --image docker.io/nvidia/cuda@sha256:0eee3094c71518ad31d011a594ae6ed6de72959ee07e318cb31cffe71690e90c \
  --platform gpu-h100-sxm \
  --preset 1gpu-16vcpu-200gb \
  --preemptible \
  --spot-pricing-policy-id "$NEBIUS_PRICING_POLICY_ID" \
  --subnet-id "$NEBIUS_SUBNET_ID" \
  --disk-size 100Gi \
  --timeout 1h \
  --restart-policy never \
  --container-command /bin/bash \
  --args /recipe/run-vector-add.sh \
  --working-dir /tmp \
  --inject-file jobs/run-vector-add.sh:/recipe/run-vector-add.sh \
  --inject-file vm/examples/vector-add.cu:/recipe/vector-add.cu \
  --dry-run
