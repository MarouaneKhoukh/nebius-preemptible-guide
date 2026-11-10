# Get Started with Nebius Preemptible GPUs

Run a CUDA check on one preemptible H100, save its result and delete the test resources. Complete **Common setup**, then choose **one path for this run**. Start with the **Compute VM** for a first run; Serverless Jobs and Kubernetes are alternatives.

[Compute VM](#path-1-gpu-vm) · [Serverless Job](#path-2-serverless-job) · [Kubernetes](#path-3-kubernetes-gpu-worker)

Each path adds **4,096 pairs of numbers on the GPU** and checks every answer:

```json
{"device":"NVIDIA H100 80GB HBM3","elements":4096,"pass":true}
```

## Common setup

- **Project:** select a billing-enabled **eu-north1** project in the [console](https://console.nebius.com), with permission to create resources and pricing policies.
- **Quota:** allowance for one preemptible H100, its disk and network addresses. Ask your administrator if creation reports `QuotaExceeded`.
- **Network:** an existing internet-enabled subnet under **Networking → Virtual Networks**. For the VM, its security group must allow inbound **SSH/TCP 22 from your current public IP**. The private Kubernetes worker needs outbound internet access without a public IP.
- **Your computer:** macOS/Linux or WSL, Git and Bash. The VM path uses OpenSSH; Python 3 is included in its image. Kubernetes needs the Nebius CLI and kubectl 1.36, linked below.

Keep the IDs of resources you create; preserve existing networking. If a step fails, stop and inspect it before continuing. Use your chosen path's cleanup steps if you abandon the run.

**Local terminal:** get the files before creating resources:

```bash
git clone https://github.com/MarouaneKhoukh/nebius-preemptible-guide.git &&
cd nebius-preemptible-guide
```

### Create a pricing policy

1. Check the **H100 price in eu-north1** on the [live pricing page](https://nebius.com/spot-prices).
2. In the console, open **Billing → Pricing → Pricing policy → Create pricing policy**.
3. Choose your project and the **H100 NVLink** platform. Name the policy `gpuguide`, or another unused name containing only letters and numbers.
4. Enter your maximum in USD per GPU-hour. For example, use **$1.50** only if it covers the current spot price and fits your budget. Otherwise wait for a lower price or choose another limit.
5. Create the policy. Select it under **Max price** in your chosen path.

**Cost checks:** the cap applies per GPU-hour, not to total spending, and does not reserve capacity. Disks and other resources cost extra. Compare the full quote with on-demand before creating a resource. Delete the test policy after your chosen path is finished.

## Path 1: GPU VM

![VM console walkthrough](vm/media/console-walkthrough.gif)

### 1. Prepare an SSH key

**Local terminal:** prepare a dedicated SSH key. If the filename already exists, choose another and update the key path in the commands below:

```bash
mkdir -p "$HOME/.ssh" &&
chmod 700 "$HOME/.ssh" &&
ssh-keygen -t ed25519 -f "$HOME/.ssh/nebius-gpu-guide" -C nebius-gpu-guide &&
cat "$HOME/.ssh/nebius-gpu-guide.pub"
```

Set a passphrase. Copy only the `.pub` contents; keep the private key locally.

### 2. Create the VM

**Console:** open **Compute → Virtual machines → Create virtual machine**. If General appears, select **Pay-as-you-go VM**.

- **Compute:** name `preemptible-gpu-guide`; **Preemptible → With GPUs → H100, 16 vCPU, 200 GiB**. Select your shared policy under **Max price**.
- **Storage:** edit the boot disk; select **New VM-managed disk → Public image → Ubuntu 24.04 LTS for NVIDIA GPUs (CUDA 13)**, **SSD**, **50 GiB**.
- **Network:** reuse your subnet; **Public IP → Auto**.
- **Configuration:** under **Username and SSH key**, select **Create**. Enter username `cookbook`, your public key and a unique credentials name, then **Add credentials**. Avoid reserved usernames `root`/`admin`.
- **Review:** check the quote and create the VM. Wait for **Running**.

### 3. Upload the files and connect

Copy **Public IPv4** from your new VM's details. **Running** can appear before SSH initialization finishes; if the first connection fails, wait and retry that VM rather than creating another.

In VM details, open **Serial logs**, keep the default selector and add `|= "SHA256:"`. Compare the ED25519 fingerprint with the first SCP/SSH prompt before accepting.

**Local terminal, in the repository root:** replace the IP below. SCP must succeed before SSH opens:

```bash
export VM_IP="YOUR_VM_PUBLIC_IP"
scp -i "$HOME/.ssh/nebius-gpu-guide" \
  vm/examples/minimal-gpu-check.sh vm/examples/vector-add.cu \
  "cookbook@$VM_IP:./" &&
ssh -i "$HOME/.ssh/nebius-gpu-guide" "cookbook@$VM_IP"
```

### 4. Run the GPU check

**Inside the VM:** run the check. Success prints `"pass": true` and returns you to your local terminal. On failure, you remain in the VM; do not continue to the download step.

```bash
bash minimal-gpu-check.sh gpu-check-results &&
exit
```

### 5. Save the output locally

**Local terminal:** after the check passes and SSH closes, copy the results before stopping the VM:

```bash
scp -i "$HOME/.ssh/nebius-gpu-guide" -r \
  "cookbook@$VM_IP:./gpu-check-results" ./gpu-check-results
```

### 6. Stop/start and verify the saved result

**Console:** use **Stop**, wait for **Stopped**, then **Start** the same VM. Use these [stop/start controls](https://docs.nebius.com/compute/virtual-machines/stop-start), not Linux `shutdown`. If capacity blocks restart, keep your download and continue to cleanup. Its public IP can change.

**Local terminal:** copy the current Public IPv4 from the same VM's details and reconnect:

```bash
export VM_IP="YOUR_CURRENT_VM_PUBLIC_IP"
ssh -i "$HOME/.ssh/nebius-gpu-guide" "cookbook@$VM_IP"
```

**Inside the VM:** verify the original result without rerunning CUDA. A matching checksum returns you to your local terminal; a failure keeps the SSH session open:

```bash
cd gpu-check-results &&
python3 - <<'PYCODE' &&
import hashlib
from pathlib import Path
expected = Path("result.sha256").read_text().strip()
actual = hashlib.sha256(Path("result.json").read_bytes()).hexdigest()
assert actual == expected, "The saved result changed"
print("Saved CUDA result survived stop/start.")
PYCODE
exit
```

The network SSD keeps saved files across stop/start; running processes and memory do not survive.

**If preempted:** start the same VM once capacity and your price limit allow, then check its saved output. To repeat the CUDA check, choose a fresh output directory; the script will not overwrite existing results.

### 7. Delete the VM

**Console:** open **Settings → Danger zone → Delete virtual machine**. Type its name and choose **Delete VM and disks**. Wait for deletion and check that this VM's disks and IP allocations are gone. Closing SSH does not stop charges; a stopped VM can still have billable storage.

Continue to [Final cleanup](#final-cleanup) to finish this run.

## Path 2: Serverless Job

Alternative to the VM path: run the same check in a container. No local Docker installation or SSH setup is needed.

![Serverless Job console walkthrough](jobs/media/console-walkthrough.gif)

### 1. Configure the Job

**Console:** open **Serverless AI → Jobs → Create job** and configure a custom container:

- **Name:** `preemptible-cuda-guide`.
- **Image:** paste this pinned NVIDIA CUDA devel image:

```text
docker.io/nvidia/cuda@sha256:0eee3094c71518ad31d011a594ae6ed6de72959ee07e318cb31cffe71690e90c
```

- **Compute:** one **H100**, **16 vCPU / 200 GiB**, **Preemptible**, and the **pricing policy you created above**.
- **Timeout:** **1 hour**. **Container disk:** **100 GiB**. Reuse your subnet; leave SSH unselected.
- **Files:** upload `jobs/run-vector-add.sh` to **`/recipe/run-vector-add.sh`** and `vm/examples/vector-add.cu` to **`/recipe/vector-add.cu`**.
- **Entrypoint:** use the shell editor with:

```sh
#!sh
bash /recipe/run-vector-add.sh
```

### 2. Run and check the result

Create the Job once and open its logs. Wait for **Completed** and check for `"pass":true` followed by a SHA-256 line. Do not submit another Job while this one is active.

**If the Job is interrupted:** inspect its status and logs. Once it reaches a final state such as **Failed** or **Cancelled**, use **Clone** to review the same settings and submit a new run. This check starts over; it has no checkpoint. Don't create a duplicate while the original is active. If you abandon an active run, cancel it and wait for a terminal state.

### 3. Save the output

Use **Export logs** to save them on your computer before deleting the Job record. The container disk is temporary; the exported logs contain this check's result. Longer workloads need outputs saved externally during execution.

### 4. Delete the Job

A **Completed** Job releases its GPU. If still active, cancel it and wait for a terminal state. Open **Settings → Danger zone → Delete job**, confirm its name, and delete the record. Include setup and image loading in runtime estimates; attached storage has separate charges.

Continue to [Final cleanup](#final-cleanup) to finish this run.

<details>
<summary>Optional: validate the Job request with the CLI</summary>

With your CLI profile configured, export `NEBIUS_PROJECT_ID`, `NEBIUS_SUBNET_ID` and `NEBIUS_PRICING_POLICY_ID`, then run `bash jobs/dry-run.sh`. This only validates the capped request; it does not launch a Job.

</details>

## Path 3: Kubernetes GPU worker

Alternative to the VM path: create a dedicated cluster with one preemptible H100 worker.

![Kubernetes console walkthrough](kubernetes/media/console-walkthrough.gif)

### 1. Prepare the CLI

**Local terminal:** install the [Nebius CLI](https://docs.nebius.com/cli/install) and [kubectl 1.36](https://kubernetes.io/docs/tasks/tools/) if needed. The commands below use a separate kubeconfig.

In the console's project selector, open the menu beside your project and choose **Copy project ID**. Configure the CLI for this project; if needed, choose an unused profile name (here `gpu-guide`) and complete browser sign-in:

```bash
export AI_AGENT="${AI_AGENT:-cookbook}"
export NEBIUS_PROJECT_ID="YOUR_PROJECT_ID"
nebius profile create gpu-guide --parent-id "$NEBIUS_PROJECT_ID" &&
nebius profile activate gpu-guide &&
nebius iam whoami
```

Continue only after CLI sign-in succeeds.

### 2. Create the cluster and worker

**Console:** in **Managed Kubernetes**, create a cluster named `preemptible-gpu-guide` in the same project/subnet with **Kubernetes 1.36**. Keep the default control-plane availability settings, leave Karpenter disabled and enable the public endpoint restricted to **your current IPv4 address /32**. At Review, create **without node groups or applications** and confirm creation without nodes; add the single worker below afterward. Avoid a default three-node group.

**Local terminal:** immediately copy the new cluster's ID from its console page and keep it for connection and cleanup:

```bash
export CLUSTER_ID="YOUR_NEW_CLUSTER_ID"
```

If worker provisioning fails, use step 5 to delete this cluster. Do not substitute an existing cluster's ID.

**Console:** add one node group:

- **General:** choose **Pay-as-you-go VM**, name `preemptible-h100-guide`, reuse your subnet/security group, and leave **Public IPv4 off**. The subnet must provide private internet egress.
- **Compute:** **With GPUs → Preemptible → H100 NVLink**, **Number of nodes: 1**, **1 GPU / 16 CPU / 200 GiB**, and the shared policy.
- **Drivers:** **Install NVIDIA drivers on**, **CUDA 13.0 / Driver 580**, **Ubuntu 24.04**.
- **Storage:** **SSD, 100 GiB**.
- **Additional:** clear any automatically selected SSH credential to **Not selected**; leave the service account unselected.
- **Review:** confirm one GPU and create the node group.

Wait for the node group to run. No separate CPU group is needed.

### 3. Connect to the new cluster

**Local terminal, in the repository root:** use the `CLUSTER_ID` recorded in step 2:

```bash
unset KUBE_CONTEXT
mkdir -p .state &&
kube_dir="$(mktemp -d "$PWD/.state/kubeconfig.XXXXXX")" &&
export KUBECONFIG="$kube_dir/config" &&
nebius mk8s cluster get-credentials \
  --id "${CLUSTER_ID:?Copy the new cluster ID first}" --external --kubeconfig "$KUBECONFIG" &&
KUBE_CONTEXT="$(kubectl config current-context)" &&
export KUBE_CONTEXT &&
kubectl --context "$KUBE_CONTEXT" config view --minify
```

Check that the displayed server belongs to your new cluster before continuing. If credentials failed, stop and fix authentication/connectivity. The endpoint allowlist must match your network egress; a VPN can route cluster traffic differently. Then check the worker:

```bash
kubectl --context "${KUBE_CONTEXT:?Connect to the new cluster first}" get nodes
kubectl --context "$KUBE_CONTEXT" get nodes \
  -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

Continue only when the worker is **Ready** and its GPU column is **1**.

### 4. Run and save the result

**Local terminal, in the repository root:** use a fresh `gpu-guide` namespace. Stop if it already exists:

```bash
kubectl --context "${KUBE_CONTEXT:?Connect to the new cluster first}" create namespace gpu-guide &&
kubectl --context "$KUBE_CONTEXT" --namespace gpu-guide create configmap gpu-check-source \
  --from-file=run-vector-add.sh=jobs/run-vector-add.sh \
  --from-file=vector-add.cu=vm/examples/vector-add.cu &&
kubectl --context "$KUBE_CONTEXT" apply -f kubernetes/gpu-check.yaml &&
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
```

Check for `"elements":4096` and `"pass":true`. The log is saved at `kubernetes/.state/gpu-check.log`.

The manifest requests one GPU, one CPU and 2 GiB RAM, with one retry and a 15-minute deadline. Retries start over; there is no checkpoint.

**If interrupted:** wait for a Ready worker with a free GPU. Inspect the node, Pod and events if the Job does not finish; do not submit duplicates. There is no second GPU in this cluster.

### 5. Delete the cluster

**Local terminal:** if you created the test namespace, save its logs and remove it below. Otherwise skip this command:

```bash
kubectl --context "${KUBE_CONTEXT:?Use the new cluster context}" delete namespace gpu-guide
```

Completing a Kubernetes Job does **not** stop its billable GPU worker. Delete the dedicated cluster using the **same `CLUSTER_ID` recorded in step 2**. If kubectl cannot reach the cluster, still perform this cloud cleanup:

```bash
nebius mk8s cluster delete --id "${CLUSTER_ID:?Use the ID from step 2}" --async &&
nebius mk8s cluster get --id "$CLUSTER_ID"
```

Repeat `get` until **NotFound**. Cluster deletion also removes its managed node group; verify the worker VM, boot disk and IP allocations were removed. Preserve reused networks.

Continue to [Final cleanup](#final-cleanup) to finish this run.

<details>
<summary><strong>If something doesn't start</strong></summary>

- **Policy is Blocked:** compare its cap with the current price for the selected platform and region. Wait or deliberately adjust the cap. A blocked VM creation can still leave a stopped VM and a billable disk; inspect the resource list before retrying.
- **No capacity:** wait and retry the existing resource where possible. Raising the price cap does not guarantee availability.
- **Quota exceeded:** request the missing allowance from your administrator; raising a price cap won't fix it.
- **Image download or connection fails:** check subnet egress and security-group rules. For Kubernetes, also check that its API allowlist matches your current public IP, especially with a VPN.

</details>

## Final cleanup

After your **chosen path**:

1. Wait for its resource deletion to finish. For a VM or Kubernetes worker, confirm its test disks and IP allocations are gone. For Serverless, confirm the Job is no longer active and its record is deleted.
2. Delete your test policy under **Billing → Pricing → Pricing policy**.
3. Remove dedicated local SSH keys/kubeconfigs you will not reuse. Preserve preexisting networks and storage.

Your selected path is complete.

<details>
<summary><strong>Validated configuration and results</strong></summary>

Validated on one H100 in **eu-north1** on **November 9, 2026**:

| Path | Result | Record |
| --- | --- | --- |
| Compute VM | GPU check passed; original result and checksum survived stop/start. | [Verification](vm/results/verification.json) |
| Serverless Job | Completed; GPU check passed and output was saved from logs. | [Verification](jobs/results/verification.json) |
| Kubernetes | Job completed on the private GPU worker with exit code 0. | [Verification](kubernetes/results/verification.json) |

All three produced the same result checksum. Created resources were removed after testing. The VM persistence test used a planned stop/start; natural preemption was not deliberately triggered. Kubernetes cleanup was also confirmed in the console on November 10.

</details>

<details>
<summary><strong>Run with a coding agent</strong></summary>

Install the [Nebius skills](https://github.com/nebius/skills#install) with a configured CLI profile, or connect the operational [Nebius MCP](https://docs.nebius.com/ai-agents/mcp-server).

```text
Follow this tutorial in my selected project. Use the Nebius compute,
Serverless Jobs and Kubernetes tools for the path I choose. Show GPU,
disk and pricing settings before launch. Reuse existing networking.
Run the CUDA check, save its output and delete every resource created
for the test. Delete the test policy after the selected path is finished.
```

</details>

Further reading: [spot pricing](https://docs.nebius.com/signup-billing/pricing-policy), [Serverless Jobs](https://docs.nebius.com/serverless/jobs/manage), [GPU nodes](https://docs.nebius.com/kubernetes/gpu/set-up).
