# Get Started with Nebius Preemptible GPUs

Create an H100 VM, run CUDA, save its result, verify it after stop/start, then delete the resources. All setup steps, commands and console recordings are in this cookbook.

**Preemptible VMs** let you use GPUs at the current spot price, which can be much lower than on demand. Nebius can stop them when it needs capacity or the price exceeds your limit. Save completed work to persistent storage. In this walkthrough, the H100 quote was **$0.80/hour versus $4.50/hour on-demand**, before disk and tax. Prices change.

**Console walkthrough — 1 minute 47 seconds**

![Console walkthrough](vm/media/console-walkthrough.gif)

0:00 Open VM creation · 0:08 GPU and price limit · 0:28 Disk and network · 0:49 Access and create · 1:08 Stop/start · 1:25 Cleanup.

[Download the recording](vm/media/console-walkthrough-share.mp4).

Verified CUDA result after adding **4,096 pairs of numbers**:

```json
{"device":"NVIDIA H100 80GB HBM3","elements":4096,"pass":true}
```

## Before you start

- A billing-enabled Nebius account, an existing **eu-north1** project and permission to create/delete resources.
- Quota for one preemptible **H100**, plus an existing internet-enabled subnet.
- A local terminal with Git, OpenSSH and Python 3. On Windows, use WSL2 Ubuntu.

## 1. Get the files and prepare SSH

On your computer:

```bash
git clone https://github.com/MarouaneKhoukh/nebius-preemptible-guide.git
cd nebius-preemptible-guide
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 -f "$HOME/.ssh/nebius-gpu-guide" -C nebius-gpu-guide
cat "$HOME/.ssh/nebius-gpu-guide.pub"
```

Choose another filename if this key exists. Set a passphrase and copy only the `.pub` contents. Keep the private key locally.

## 2. Create the VM

Sign in to the [console](https://console.nebius.com), select your project, then open **Compute → Virtual machines → Create virtual machine**. If a General step appears, choose **Pay-as-you-go VM**.

- **Compute:** name it `preemptible-gpu-guide`. Choose **Preemptible → With GPUs → H100, 16 vCPU, 200 GiB**.
- **Max price:** create a dedicated policy, such as `gpuguide20261109`. The dialog asks for **Name** and **Max price**; enter **$1.50 per GPU-hour** for this USD example.
- **Storage:** edit the boot disk with its pencil button. Choose **New VM-managed disk → Public image → Ubuntu 24.04 LTS for NVIDIA GPUs (CUDA 13)**, **SSD**, **50 GiB**.
- **Network:** reuse an internet-enabled subnet; choose **Public IP → Auto**.
- **Configuration:** under **Username and SSH key**, choose **Create**. Enter username `cookbook`, your public key and a unique **Credentials name**, then **Add credentials**. Avoid reserved usernames `root` and `admin`.
- **Review:** check the settings and current quote, then create the VM. Wait until it is running.

You pay the current spot price, not automatically your maximum. The cap is not a spending budget or capacity guarantee. Disks are charged separately. Note the new VM, disk and policy for cleanup.

## 3. Connect, run CUDA and save the output

In VM details, open **Serial logs**. Keep the default selector and add `|= "SHA256:"`. Note the ED25519 fingerprint and compare it with the first SCP/SSH prompt before accepting.

Copy the VM's public IP. On your computer:

```bash
export VM_IP="YOUR_VM_PUBLIC_IP"
scp -i "$HOME/.ssh/nebius-gpu-guide" \
  vm/examples/minimal-gpu-check.sh vm/examples/vector-add.cu \
  "cookbook@$VM_IP:./"
ssh -i "$HOME/.ssh/nebius-gpu-guide" "cookbook@$VM_IP"
```

Allow first-boot setup to finish if SSH isn't ready. Inside the VM:

```bash
bash minimal-gpu-check.sh gpu-check-results
exit
```

The script compiles CUDA, checks every result and saves the JSON and checksum. Look for **`pass: true`**. Back on your computer, download before stopping:

```bash
scp -i "$HOME/.ssh/nebius-gpu-guide" -r \
  "cookbook@$VM_IP:./gpu-check-results" ./gpu-check-results
```

## 4. Stop, start and verify

Stop this VM in the console and wait for **Stopped**. Start the same VM and wait for **Running**. Capacity and pricing determine whether it can restart; if blocked, keep your download and proceed to cleanup.

Check the current public IP and reconnect locally:

```bash
export VM_IP="YOUR_CURRENT_VM_PUBLIC_IP"
ssh -i "$HOME/.ssh/nebius-gpu-guide" "cookbook@$VM_IP"
```

Inside the VM, verify the original file **without rerunning CUDA**:

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
```

The network SSD survives stop/start; memory and local SSD do not. Longer workloads need their own checkpoint/resume logic.

## 5. Delete the resources

After saving your download:

1. Open **Settings → Danger zone → Delete virtual machine**. Type the VM name and choose **Delete VM and disks**. This permanently deletes its managed disks too.
2. Check **Compute → Disks** for remaining disks created for this run.
3. Wait until VM deletion finishes, then remove its policy under **Billing → Pricing → Pricing policy**.
4. Verify all new resources are gone. Preserve reused networks and unrelated resources.

There is no automatic timeout. Stopping alone leaves disk charges. Remove a dedicated local SSH key after VM deletion if you won't reuse it.

## Prefer an agent?

Install the [Nebius skills](https://github.com/nebius/skills#install) with a configured CLI profile, or connect the operational [Nebius MCP](https://docs.nebius.com/ai-agents/mcp-server).

```text
Follow this cookbook with nebius-cloud-basics,
nebius-compute-provision and nebius-billing in my selected project.
Show the GPU/disk/maximum price before launch. Track new resources.
Run CUDA, verify the saved result after stop/start, download it,
and delete everything created for this run. Preserve existing resources.
```

## Validation

**Console provisioning, SSH CUDA check and CLI cleanup tested.** Stop/start changed the boot ID and preserved the result checksum. Every created cloud resource was deleted. [Recorded verification](vm/results/verification.json).

The recordings show the console. CUDA ran over SSH; deletion used the CLI and is labelled in the cleanup recording.

Sources: [preemptible VMs](https://docs.nebius.com/compute/virtual-machines/preemptible), [VM creation](https://docs.nebius.com/compute/virtual-machines/create), [SSH access](https://docs.nebius.com/compute/virtual-machines/connect), [pricing policies](https://docs.nebius.com/signup-billing/manage-pricing-policy).
