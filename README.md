# Get Started with Nebius Preemptible GPUs

Run your first preemptible GPU, set a price limit, save the result and remove the resources when you're done. Start with a **GPU VM**, then try the same code as a **Serverless Job** or on a **Kubernetes GPU worker**.

Each path adds **4,096 pairs of numbers on the GPU** and checks every answer:

```json
{"device":"NVIDIA H100 80GB HBM3","elements":4096,"pass":true}
```

CUDA is NVIDIA's toolkit for running code on a GPU. This small check confirms that your GPU, drivers and execution environment work before you bring a model or dataset. You don't need to write CUDA or install it on your laptop.

## What is a preemptible GPU?

A **preemptible VM** is a cloud computer that uses spare capacity at a variable **spot price**. That price can be much lower than the regular on-demand rate. In return, Nebius can stop the VM when it needs the capacity back. This interruption is called **preemption**. A price increase above your chosen limit can also stop it. [How preemption works](https://docs.nebius.com/compute/virtual-machines/preemptible).

For example, during this experiment the H100 quote was **$0.80/hour versus $4.50/hour on demand**—about **82% lower** for compute, before disk and tax. Both options use the same GPU. These are [recorded rates](vm/results/verification.json); check today's prices before launching.

Preemptibles are useful when work can wait or resume:

- **Batch inference or embeddings:** save each completed batch and process the remaining inputs later.
- **Image or video generation:** save each finished file independently.
- **Evaluations:** keep completed predictions so a retry doesn't repeat them.
- **Fine-tuning:** save checkpoints and resume training from the latest one.

For a single live API that must respond immediately, use regular capacity or design a fallback. For batch work, compare the cost of completed results, including loading and retries, with the cost on regular GPUs.

## What does a pricing policy do?

A **pricing policy** is a reusable maximum price per GPU-hour. It belongs to a project and one GPU platform, such as H100. Your VM, Serverless Job and Kubernetes worker can use the same policy.

With a **$1.50/GPU-hour** limit, for example:

- At a spot price of **$0.80**, you pay **$0.80/GPU-hour**.
- If it rises to **$1.20**, you pay **$1.20/GPU-hour**.
- Above **$1.50**, resources using the policy stop; new ones cannot start under that policy.

The limit applies to each GPU. It is **not a total spending budget or a capacity reservation**. Storage and other billable resources are additional. **Follows spot price** removes this ceiling; spot prices can even exceed on-demand rates. This cookbook uses a capped policy. [Pricing rules](https://docs.nebius.com/signup-billing/pricing-policy).

**GPU-hour is the rate unit; compute is metered per second.** If the price stays at $0.80, one GPU running for 30 minutes costs $0.40 for compute, before storage and tax. A running VM or Kubernetes worker keeps accruing charges even when your script is idle. [Compute billing](https://docs.nebius.com/compute/resources/pricing).

**Choosing your limit:** check the current price and recent history for your GPU and region, then choose the highest rate you're comfortable paying. Headroom above today's price can avoid interruptions caused by small price increases. It cannot prevent capacity reclamation. [View live prices and history](https://nebius.com/spot-prices).

## Choose how to run

- **[GPU VM](#path-1-gpu-vm):** start here for a first run. You connect with SSH and run a script on a cloud machine you control.
- **[Serverless Job](#path-2-serverless-job):** give Nebius a container and a command; it manages the machine and releases the compute after the task finishes.
- **[Kubernetes worker](#path-3-kubernetes-gpu-worker):** use your Kubernetes workflow to schedule GPU containers. You manage the worker capacity after the task finishes.

These are three ways to use preemptible compute. You only need to complete the path that fits your workflow.

## Common setup

- **Account and project:** sign in to the [console](https://console.nebius.com) and select a billing-enabled **eu-north1** project. A project groups your resources and permissions. You need permission to create resources and pricing policies, normally the `editor` role.
- **Quota:** your account's resource allowance must cover one preemptible VM, its disk and network addresses. Quota is separate from whether a GPU is currently available. Ask your project administrator if creation reports `QuotaExceeded`.
- **Network:** use an existing subnet, the private network segment your resources join. It must allow internet downloads; the private Kubernetes worker needs outbound internet access without a public IP. Find it under **Networking → Virtual Networks**. If this hasn't been set up, ask your administrator to check routing and security groups—the network's traffic rules.
- **Your computer:** use a macOS/Linux terminal, or WSL on Windows, with Git and Bash. The VM path also uses OpenSSH; Python 3 runs inside the supplied VM image. Kubernetes needs the Nebius CLI and kubectl 1.36, covered below.

The settings below were tested in **eu-north1** with one H100. Other regions can have different platforms, quotas and prices. Run one path at a time and keep the IDs of the resources you create for cleanup.

Get the files:

```bash
git clone https://github.com/MarouaneKhoukh/nebius-preemptible-guide.git
cd nebius-preemptible-guide
```

### Create your price limit once

1. Check the **H100 price in eu-north1** on the [live pricing page](https://nebius.com/spot-prices).
2. In the console, open **Billing → Pricing → Pricing policy → Create pricing policy**.
3. Choose your project and the **H100 NVLink** platform. Name the policy `gpuguide`, or another unused name containing only letters and numbers.
4. Enter your maximum in USD per GPU-hour. We used **$1.50**. Use that value only if it covers the current spot price and fits your budget; otherwise wait for a lower price or choose a different limit you're comfortable with.
5. Create the policy. Select it under **Max price** in each path and keep it until your final cleanup.

You can also create the policy directly from a resource's **Max price** field. A **Blocked** policy means the current price exceeds its limit; it doesn't mean your account is broken. Raising the limit or waiting for a lower price resolves that price constraint, but availability still matters. [Policy setup](https://docs.nebius.com/signup-billing/manage-pricing-policy).

## Path 1: GPU VM

Use a VM when you want SSH access and control of the operating system. **SSH** opens a terminal on the VM; **SCP** copies files between it and your computer. Closing the terminal leaves the VM running and billable.

![VM console walkthrough](vm/media/console-walkthrough.gif)

[Download the VM console recording](vm/media/console-walkthrough-share.mp4).

### Create and connect

Prepare a dedicated SSH key locally. Choose another filename if it exists:

```bash
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 -f "$HOME/.ssh/nebius-gpu-guide" -C nebius-gpu-guide
cat "$HOME/.ssh/nebius-gpu-guide.pub"
```

Set a passphrase. Copy only the `.pub` contents; keep the private key locally.

Open **Compute → Virtual machines → Create virtual machine**. If General appears, select **Pay-as-you-go VM**.

A **preset** bundles a GPU count with CPU and memory. Choose the one-GPU preset below; it is enough for this check.

- **Compute:** name `preemptible-gpu-guide`; **Preemptible → With GPUs → H100, 16 vCPU, 200 GiB**. Select your shared policy under **Max price**.
- **Storage:** edit the boot disk; select **New VM-managed disk → Public image → Ubuntu 24.04 LTS for NVIDIA GPUs (CUDA 13)**, **SSD**, **50 GiB**.
- **Network:** reuse your subnet; **Public IP → Auto**.
- **Configuration:** under **Username and SSH key**, select **Create**. Enter username `cookbook`, your public key and a unique credentials name, then **Add credentials**. Avoid reserved usernames `root`/`admin`.
- **Review:** check the quote and create the VM. Wait for **Running**.

In VM details, open **Serial logs**, keep the default selector and add `|= "SHA256:"`. Compare the ED25519 fingerprint with the first SCP/SSH prompt before accepting.

Replace the IP and run locally:

```bash
export VM_IP="YOUR_VM_PUBLIC_IP"
scp -i "$HOME/.ssh/nebius-gpu-guide" \
  vm/examples/minimal-gpu-check.sh vm/examples/vector-add.cu \
  "cookbook@$VM_IP:./"
ssh -i "$HOME/.ssh/nebius-gpu-guide" "cookbook@$VM_IP"
```

Inside the VM:

```bash
bash minimal-gpu-check.sh gpu-check-results
exit
```

Look for **`pass: true`**. Download before stopping:

```bash
scp -i "$HOME/.ssh/nebius-gpu-guide" -r \
  "cookbook@$VM_IP:./gpu-check-results" ./gpu-check-results
```

### Verify persistence and remove the VM

In the console, use **Stop**, wait for **Stopped**, then **Start** the same VM. Use these [stop/start controls](https://docs.nebius.com/compute/virtual-machines/stop-start), not Linux `shutdown`. If capacity blocks restart, keep your download and continue to cleanup. Its public IP can change:

```bash
export VM_IP="YOUR_CURRENT_VM_PUBLIC_IP"
ssh -i "$HOME/.ssh/nebius-gpu-guide" "cookbook@$VM_IP"
```

Inside the VM, check the original result without rerunning CUDA:

```bash
cd gpu-check-results
python3 - <<'PYCODE'
import hashlib
from pathlib import Path
expected = Path("result.sha256").read_text().strip()
actual = hashlib.sha256(Path("result.json").read_bytes()).hexdigest()
assert actual == expected, "The saved result changed"
print("Saved CUDA result survived stop/start.")
PYCODE
exit
```

The checksum is a fingerprint of the saved file: a match confirms the original result survived. The **network SSD** chosen here keeps files across stop/start. Running processes and memory don't survive; [local SSD storage](https://docs.nebius.com/compute/storage/local-disks), on platforms that offer it, is also temporary.

**If the VM is preempted:** it stops without automatically restarting. Once capacity and your price limit allow, start it again and rerun this short check. Longer work needs a checkpoint to resume from. Compute documents a 60-second shutdown warning; save progress regularly instead of depending on those final seconds. [VM interruption behavior](https://docs.nebius.com/compute/virtual-machines/preemptible).

After downloading, open **Settings → Danger zone → Delete virtual machine**. Type its name and choose **Delete VM and disks**. Check for remaining disks/IP allocations created for this VM. Keep the shared pricing policy if continuing.

## Path 2: Serverless Job

Use a Job for a container that runs and finishes, without configuring SSH or maintaining its VM. A **container image** packages the runtime and tools; the **entrypoint** is the command it runs. Here, the NVIDIA image supplies CUDA and the uploaded script supplies the work. You don't need Docker installed locally.

![Serverless Job console walkthrough](jobs/media/console-walkthrough.gif)

[Download the Serverless Job console recording](jobs/media/console-walkthrough-share.mp4).

Open **Serverless AI → Jobs → Create job** and configure a custom container:

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

Create the Job once and open its logs. The worker compiles CUDA and prints the JSON followed by its SHA-256. Wait for **Completed**, then use **Export logs** to save them locally before deleting the Job record. Container files disappear when the Job finishes; this tiny check uses saved logs as its output.

A completed Job releases its GPU. For longer work, write outputs to an attached bucket or shared filesystem while it runs; the container disk is temporary. Serverless compute and storage are billed during the deployment's running lifetime, so include setup and image loading when estimating cost. Attached storage has its own charges. [Serverless billing](https://docs.nebius.com/serverless/pricing-quotas).

**If the Job is interrupted:** inspect its status and logs. Once it reaches a final state such as **Failed** or **Cancelled**, use **Clone** to review the same settings and submit a new run. This check starts over; it has no checkpoint. Don't create a duplicate while the original is active. If you abandon an active run, cancel it. Keep the policy for the next path.

After saving your output, open the completed Job's **Settings → Danger zone → Delete job**, confirm its name, and delete the record.

Optional CLI validation: with your CLI profile configured, export `NEBIUS_PROJECT_ID`, `NEBIUS_SUBNET_ID` and `NEBIUS_PRICING_POLICY_ID`, then run `bash jobs/dry-run.sh`. It validates the same capped request and never creates a resource.

## Path 3: Kubernetes GPU worker

Use this path when you want Kubernetes to schedule your GPU containers. The **control plane** manages the cluster; **worker nodes** are VMs that run your code. A **node group** defines workers with the same settings. This guide adds one preemptible H100 worker. [Cluster components](https://docs.nebius.com/kubernetes/components).

A **Kubernetes Job** asks the cluster to run a task to completion. It is separate from the **Nebius Serverless Job** above: finishing a Kubernetes Job leaves your worker running.

![Kubernetes console walkthrough](kubernetes/media/console-walkthrough.gif)

[Download the Kubernetes console recording](kubernetes/media/console-walkthrough-share.mp4).

### Create the cluster and worker

In **Managed Kubernetes**, create a cluster named `preemptible-gpu-guide` in the same project/subnet with **Kubernetes 1.36**. Keep the default control-plane availability settings, leave Karpenter disabled and enable the public endpoint restricted to **your current IPv4 address /32**. At Review, create **without node groups or applications** and confirm creation without nodes; add the single worker below afterward. Avoid a default three-node group.

Add one node group:

- **General:** choose **Pay-as-you-go VM**, name `preemptible-h100-guide`, reuse your subnet/security group, and leave **Public IPv4 off**. This run used existing private internet egress.
- **Compute:** **With GPUs → Preemptible → H100 NVLink**, **Number of nodes: 1**, **1 GPU / 16 CPU / 200 GiB**, and the shared policy.
- **Drivers:** **Install NVIDIA drivers on**, **CUDA 13.0 / Driver 580**, **Ubuntu 24.04**.
- **Storage:** **SSD, 100 GiB**.
- **Additional:** clear any automatically selected SSH credential to **Not selected**; leave the service account unselected.
- **Review:** confirm one GPU and create the node group.

The console should show the node group running. After connecting below, check that Kubernetes reports the worker as **Ready** and lists **`nvidia.com/gpu: 1`**—one GPU available to schedule. No separate CPU group is needed.

### Connect and run

Use the [Nebius CLI](https://docs.nebius.com/cli/install) and [kubectl 1.36](https://kubernetes.io/docs/tasks/tools/). The Nebius CLI manages cloud resources; `kubectl` sends instructions to Kubernetes. A **kubeconfig** stores connection settings, and a **context** selects a cluster. We use a separate file here to avoid changing your usual cluster configuration.

In the console's project selector, open the menu beside your project and choose **Copy project ID**. Configure the CLI for this project; if needed, choose an unused profile name (here `gpu-guide`) and complete browser sign-in:

```bash
export AI_AGENT="${AI_AGENT:-cookbook}"
export NEBIUS_PROJECT_ID="YOUR_PROJECT_ID"
nebius profile create gpu-guide --parent-id "$NEBIUS_PROJECT_ID" &&
nebius profile activate gpu-guide &&
nebius iam whoami
```

Copy the cluster ID from its console page. Create a fresh private kubeconfig:

```bash
mkdir -p .state
kube_dir="$(mktemp -d "$PWD/.state/kubeconfig.XXXXXX")"
export KUBECONFIG="$kube_dir/config"
unset KUBE_CONTEXT
nebius mk8s cluster get-credentials \
  --id "YOUR_CLUSTER_ID" --external --kubeconfig "$KUBECONFIG" &&
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

A **namespace** groups this test's Kubernetes resources. A **ConfigMap** makes the two source files available to its container. Use a fresh `gpu-guide` namespace; stop if it already exists. Run these commands from the repository root:

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

The manifest requests one GPU, one CPU and 2 GiB RAM, allows one retry and sets a 15-minute deadline. A **Pod** holds the running container. A retry starts this small calculation again; it does not restore a checkpoint.

**If the worker is interrupted:** a retry needs a Ready worker with a free GPU. With only one worker, there is no second GPU to take over immediately. Inspect the node, Pod and events if the Job doesn't finish; don't submit duplicates. Longer workloads need saved checkpoints or completed batches on storage outside the Pod.

### Remove the Kubernetes resources

After saving logs:

```bash
kubectl --context "$KUBE_CONTEXT" delete namespace gpu-guide
```

Completing a Kubernetes Job does **not** stop its GPU worker. Copy only the ID of the **new, dedicated cluster** created for this walkthrough:

```bash
export CLUSTER_ID="YOUR_NEW_TEST_CLUSTER_ID"
nebius mk8s cluster delete --id "$CLUSTER_ID" --async
nebius mk8s cluster get --id "$CLUSTER_ID"
```

Repeat `get` until **NotFound**. Cluster deletion also removes its managed node group; verify the worker VM, boot disk and IP allocations were removed. Preserve reused networks.

## Use this with your own workload

Replace the CUDA check with your script or container once the first run succeeds. To make interruptions manageable:

1. **Save completed work as you go.** Write each batch or generated file to durable storage, such as Object Storage. Avoid keeping the only copy in memory or a temporary container directory.
2. **Save enough to resume.** A training checkpoint includes the state needed to continue training; a batch pipeline can keep a list of finished input IDs.
3. **Make retries safe.** Check whether an output already exists before processing it again. Retry unfinished work without duplicating finished results.
4. **Limit the experiment.** Set a price cap and a time limit, monitor status, and stop or delete the compute when you're done. Track total spend separately from the hourly cap.

This cookbook verifies GPU execution and, on the VM, saved-file persistence. It doesn't implement checkpointed training or guarantee uninterrupted runs.

<details>
<summary><strong>If something doesn't start</strong></summary>

- **Policy is Blocked:** compare its cap with the current price for the selected platform and region. Wait or deliberately adjust the cap. A blocked VM creation can still leave a stopped VM and a billable disk; inspect the resource list before retrying.
- **No capacity:** an acceptable price doesn't guarantee a free GPU. Wait and retry the existing resource where possible. Changing platform or region requires checking the image, policy and hardware settings again.
- **Quota exceeded:** request the missing allowance from your administrator; raising a price cap won't fix it.
- **Image download or connection fails:** check subnet egress and security-group rules. For Kubernetes, also check that its API allowlist matches your current public IP, especially with a VPN.

</details>

## Final cleanup

After your last path, wait for resources to finish deleting, then delete your test policy under **Billing → Pricing → Pricing policy**. Remove dedicated local SSH keys/kubeconfigs you won't reuse. A stopped VM can still have billable disks; use the deletion steps in your chosen path to finish cleanup.

Before leaving the console, confirm your test VM or worker, its disks and its IP allocations are gone. For Serverless, confirm the Job is no longer active. Keep any network or storage that existed before this test.

<details>
<summary><strong>What was tested</strong></summary>

- **VM:** console provisioning, SSH CUDA check and CLI cleanup tested. Stop/start changed the boot ID and preserved the original checksum. [Verification](vm/results/verification.json).
- **Serverless Job:** **Completed**, 4,096 results passed, same checksum as the VM; logs saved and Job deleted. [Verification](jobs/results/verification.json).
- **Kubernetes:** the private H100 worker exposed one GPU; the Job completed with exit code 0, 4,096 results passed and the same checksum. Namespace and cluster resources removed; CLI cleanup verified. [Verification](kubernetes/results/verification.json).

All cloud resources created for these tests were removed; existing resources were preserved. Natural preemption was not deliberately triggered.

The recordings show actual console operations. CUDA ran over SSH for the VM. The Kubernetes film includes console confirmation after CLI cleanup. Its workload was verified with kubectl; the final console check shows no cluster or Kubernetes worker nodes. The VM cleanup recording labels its CLI deletion accurately.

</details>

## Prefer an agent?

Install the [Nebius skills](https://github.com/nebius/skills#install) with a configured CLI profile, or connect the operational [Nebius MCP](https://docs.nebius.com/ai-agents/mcp-server).

```text
Follow this cookbook in my selected project. Use the Nebius compute,
Serverless Jobs and Kubernetes tools for the path I choose. Show GPU,
disk and pricing settings before launch. Reuse existing networking.
Run the CUDA check, save its output and delete every resource created
for the test. Keep the shared policy until the last path is finished.
```

Further reading: [spot pricing](https://docs.nebius.com/signup-billing/pricing-policy), [Serverless Jobs](https://docs.nebius.com/serverless/jobs/manage), [GPU nodes](https://docs.nebius.com/kubernetes/gpu/set-up).
