#!/usr/bin/env bash
# Compile and run a small CUDA calculation, then save its verified output.
set -euo pipefail

output_dir="${1:-gpu-check-results}"
source_path="$(dirname -- "${BASH_SOURCE[0]}")/vector-add.cu"
for program in nvidia-smi python3; do
  command -v "$program" >/dev/null || {
    printf 'Missing %s. Use the documented CUDA image.\n' "$program" >&2
    exit 1
  }
done
compiler="$(command -v nvcc || true)"
if [[ -z "$compiler" ]]; then
  compiler="/usr/local/cuda/bin/nvcc"
fi
[[ -x "$compiler" ]] || {
  printf 'CUDA compiler not found. Use the documented CUDA image.\n' >&2
  exit 1
}
[[ -f "$source_path" ]] || {
  printf 'Keep vector-add.cu beside this script.\n' >&2
  exit 1
}
[[ ! -e "$output_dir" ]] || {
  printf 'Output already exists. Choose a new directory to preserve it.\n' >&2
  exit 1
}
mkdir -- "$output_dir"
# Record model/driver details without device UUIDs or account identifiers.
nvidia-smi --query-gpu=index,name,driver_version,memory.total \
  --format=csv,noheader,nounits > "$output_dir/gpus.csv"
"$compiler" -O2 "$source_path" -o "$output_dir/vector-add"
"$output_dir/vector-add" > "$output_dir/result.partial.json"

python3 - "$output_dir" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

folder = Path(sys.argv[1])
pending = folder / "result.partial.json"
result = json.loads(pending.read_text(encoding="utf-8"))
if (set(result) != {"device", "elements", "pass"}
        or not isinstance(result["device"], str)
        or result["elements"] != 4096 or result["pass"] is not True):
    raise SystemExit("The CUDA result did not pass verification.")
with pending.open("rb") as stream:
    os.fsync(stream.fileno())
destination = folder / "result.json"
pending.rename(destination)
digest = hashlib.sha256(destination.read_bytes()).hexdigest()
with (folder / "result.sha256").open("x", encoding="ascii") as stream:
    stream.write(digest + "\n")
    stream.flush()
    os.fsync(stream.fileno())
print(json.dumps(result, indent=2))
print("Saved GPU result: " + str(destination))
print("Result SHA-256: " + digest)
PY
