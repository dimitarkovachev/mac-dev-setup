#!/bin/bash
# Test src/mac-dev-setup.sh inside a disposable macOS VM using Tart
# (https://tart.run, Apple Silicon only).
#
#   ./test/vm-test.sh fresh    # pristine VM from the (cached) image, run the setup script in it
#   ./test/vm-test.sh rerun    # run the setup script again in the SAME VM (idempotency check)
#   ./test/vm-test.sh ssh      # shell into the test VM
#   ./test/vm-test.sh gui      # boot the VM with a screen attached
#   ./test/vm-test.sh destroy  # delete the test VM
#
# The image download (~40 GB) happens once and is kept in tart's OCI cache
# (~/.tart/cache); every "fresh" clones straight from that cache in seconds.
# SSH uses the image's stock credentials (admin/admin) via sshpass, so there is
# nothing to set up and no VM to keep around besides the test VM itself.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/cirruslabs/macos-tahoe-vanilla:latest}"
VM="${VM:-macsetup-test}"
VM_USER="admin"
VM_PASS="admin"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# - don't record/verify host keys: VM IPs are recycled across clones
# - password auth only: otherwise the host's ssh-agent offers all its keys first
#   (the VM knows none of them) and the server disconnects before the password
#   is ever tried ("Too many authentication failures")
SSH_OPTS=(
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
  -o PubkeyAuthentication=no -o PreferredAuthentications=password -o IdentitiesOnly=yes
)

ensure_tools() {
  command -v tart >/dev/null 2>&1 || brew install cirruslabs/cli/tart
  # sshpass lives in the same tap; without it ssh just asks for the password (admin)
  command -v sshpass >/dev/null 2>&1 || brew install cirruslabs/cli/sshpass || true
}

vssh() {
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$VM_PASS" ssh "${SSH_OPTS[@]}" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$@"
  fi
}

have_vm() { tart list 2>/dev/null | awk '{print $2}' | grep -qx "$VM"; }

vm_running() { tart list 2>/dev/null | awk -v vm="$VM" '$2 == vm {print $NF}' | grep -qx "running"; }

wait_for_ip() {
  local ip=""
  for _ in $(seq 1 90); do
    ip="$(tart ip "$VM" 2>/dev/null || true)"
    if [ -n "$ip" ]; then
      echo "$ip"
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for $VM to get an IP" >&2
  return 1
}

# the IP appears (DHCP) well before sshd accepts connections - poll until ready
wait_for_ssh() {
  local ip="$1"
  for _ in $(seq 1 90); do
    if vssh -o ConnectTimeout=5 "$VM_USER@$ip" true 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for ssh on $VM ($ip)" >&2
  return 1
}

boot() {
  if ! vm_running; then
    echo "==> Booting $VM (headless)"
    tart run "$VM" --no-graphics >/dev/null 2>&1 &
    disown
  fi
  wait_for_ssh "$(wait_for_ip)"
}

fresh_vm() {
  if have_vm; then
    echo "==> Deleting old test VM"
    tart stop "$VM" 2>/dev/null || true
    tart delete "$VM"
  fi
  echo "==> Cloning $IMAGE -> $VM (first time: ~40 GB download, cached afterwards)"
  tart clone "$IMAGE" "$VM"
}

run_setup() {
  boot
  local ip
  ip="$(wait_for_ip)"
  echo "==> Copying repo into VM ($ip)"
  # No-op on the vanilla image (no brew yet). The cirruslabs -base CI image
  # ships a buildkite tap that Homebrew 6 flags as untrusted on every command -
  # drop it so the logs stay readable when IMAGE is overridden to -base
  vssh "$VM_USER@$ip" "command -v brew >/dev/null && brew untap buildkite/buildkite 2>/dev/null; true"
  vssh "$VM_USER@$ip" "rm -rf ~/mac-dev-setup && mkdir -p ~/mac-dev-setup"
  tar -C "$REPO_ROOT" --exclude .git -cf - . | vssh "$VM_USER@$ip" "tar -C ~/mac-dev-setup -xf -"
  echo "==> Running setup script (interactive: gh auth login / sudo will prompt here)"
  vssh -t "$VM_USER@$ip" "cd ~/mac-dev-setup && bash src/mac-dev-setup.sh"
  echo "==> Setup script finished. Inspect with: $0 ssh   or   $0 gui"
}

cmd="${1:-fresh}"
ensure_tools
case "$cmd" in
  fresh)
    fresh_vm
    run_setup
    ;;
  rerun)
    have_vm || { echo "No test VM yet - run '$0 fresh' first" >&2; exit 1; }
    run_setup
    ;;
  ssh)
    boot
    vssh -t "$VM_USER@$(wait_for_ip)"
    ;;
  gui)
    if vm_running; then
      echo "VM is running headless - a screen can only be attached at boot." >&2
      echo "Stop it first: tart stop $VM" >&2
      exit 1
    fi
    echo "==> Booting $VM with a screen. The window is a 'tart' app (check Cmd-Tab);"
    echo "    it stays black for ~a minute while macOS boots. Login password: $VM_PASS."
    echo "    This terminal stays attached; ^C here powers the VM off."
    tart run "$VM"
    ;;
  destroy)
    tart stop "$VM" 2>/dev/null || true
    tart delete "$VM" 2>/dev/null || true
    echo "Deleted $VM. (The image stays in tart's cache; remove with: tart prune)"
    ;;
  *)
    echo "Usage: $0 [fresh|rerun|ssh|gui|destroy]" >&2
    exit 1
    ;;
esac
