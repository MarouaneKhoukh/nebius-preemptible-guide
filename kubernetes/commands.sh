#!/usr/bin/env bash
# Reference commands: run individually after selecting your new cluster context.
# Do not execute this file as a script.

# After installing the Nebius CLI, authenticate a profile for your project.
# Choose an unused profile name; stop if creation fails.
export AI_AGENT="${AI_AGENT:-cookbook}"
export NEBIUS_PROJECT_ID="YOUR_PROJECT_ID"
nebius profile create gpu-guide --parent-id "$NEBIUS_PROJECT_ID" &&
nebius profile activate gpu-guide &&
nebius iam whoami

# Use a new private directory, rather than an existing kubeconfig/context.
mkdir -p .state
kube_dir="$(mktemp -d "$PWD/.state/kubeconfig.XXXXXX")"
export KUBECONFIG="$kube_dir/config"
unset KUBE_CONTEXT
nebius mk8s cluster get-credentials \
  --id "YOUR_CLUSTER_ID" --external --kubeconfig "$KUBECONFIG" &&
KUBE_CONTEXT="$(kubectl config current-context)" &&
export KUBE_CONTEXT &&
kubectl --context "$KUBE_CONTEXT" config view --minify

# STOP if authentication/credentials failed. Check that the displayed API server
# belongs to the cluster you just created before submitting anything.
kubectl --context "${KUBE_CONTEXT:?Connect to the new cluster first}" get nodes
kubectl --context "$KUBE_CONTEXT" get nodes \
  -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'

# Use a fresh namespace. If this name already exists, stop rather than reusing it.
kubectl --context "${KUBE_CONTEXT:?Connect to the new cluster first}" create namespace gpu-guide &&
kubectl --context "$KUBE_CONTEXT" --namespace gpu-guide create configmap gpu-check-source \
  --from-file=run-vector-add.sh=jobs/run-vector-add.sh \
  --from-file=vector-add.cu=vm/examples/vector-add.cu &&
kubectl --context "$KUBE_CONTEXT" apply -f kubernetes/gpu-check.yaml &&

# Save logs before deleting the Job or namespace.
kubectl --context "$KUBE_CONTEXT" --namespace gpu-guide wait \
  --for=condition=complete job/gpu-check --timeout=900s &&
mkdir -p kubernetes/.state &&
SUCCESS_POD="$(kubectl --context "$KUBE_CONTEXT" --namespace gpu-guide get pods \
  -l job-name=gpu-check --field-selector=status.phase=Succeeded \
  -o jsonpath='{.items[0].metadata.name}')" &&
test -n "$SUCCESS_POD" &&
kubectl --context "$KUBE_CONTEXT" --namespace gpu-guide logs \
  "$SUCCESS_POD" --container cuda-check > kubernetes/.state/gpu-check.log &&
cat kubernetes/.state/gpu-check.log

# If waiting fails, inspect this namespace before deciding whether to retry.
kubectl --context "$KUBE_CONTEXT" --namespace gpu-guide get pods
kubectl --context "$KUBE_CONTEXT" --namespace gpu-guide describe job gpu-check

# After saving outputs, remove this test's Kubernetes resources.
kubectl --context "$KUBE_CONTEXT" delete namespace gpu-guide
# Completing the Job does not release its GPU worker. Delete only the dedicated
# NEW cluster created for this walkthrough, which also removes its node group.
export CLUSTER_ID="YOUR_NEW_TEST_CLUSTER_ID"
nebius mk8s cluster delete --id "$CLUSTER_ID" --async
nebius mk8s cluster get --id "$CLUSTER_ID"
# Repeat get until NotFound, then verify worker/disks/IPs are gone. Remove the
# shared policy only after the final path finishes; preserve reused networking.
