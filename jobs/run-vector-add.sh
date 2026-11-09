#!/usr/bin/env bash
# A finite GPU check: raw JSON and its checksum are saved in Job logs.
set -euo pipefail

compiler="$(command -v nvcc || true)"
if [[ -z "$compiler" ]]; then
  compiler="/usr/local/cuda/bin/nvcc"
fi
[[ -x "$compiler" ]] || {
  printf 'CUDA compiler not found; use the documented NVIDIA devel image.\n' >&2
  exit 1
}
source_path="${VECTOR_ADD_SOURCE:-/recipe/vector-add.cu}"
[[ -f "$source_path" ]] || {
  printf 'CUDA source not found: %s\n' "$source_path" >&2
  exit 1
}
work_dir="$(mktemp -d /tmp/nebius-cuda-check.XXXXXX)"
trap 'rm -rf -- "$work_dir"' EXIT
"$compiler" -O2 "$source_path" -o "$work_dir/vector-add"
cd "$work_dir"
./vector-add | tee result.json
sha256sum result.json
