# Testing the setup script in a disposable VM

`vm-test.sh` runs `src/mac-dev-setup.sh` inside a local macOS virtual machine
using [Tart](https://tart.run) (Virtualization.framework, Apple Silicon only,
free for personal use). Instead of resetting your Mac, you reset a VM.

How it stays fast: the macOS image (~40 GB) is downloaded **once** into tart's
OCI cache (`~/.tart/cache`). Every `fresh` run clones a brand-new VM straight
from that cache via APFS copy-on-write — seconds, no re-download. There is only
one VM (`macsetup-test`) and it's fully disposable.

SSH into the VM uses the image's stock credentials (`admin`/`admin`) through
`sshpass`, so there's no key setup. If sshpass isn't installed, ssh simply asks
for the password: `admin`.

## Usage

```sh
./test/vm-test.sh fresh    # pristine VM, run the setup script in it
./test/vm-test.sh rerun    # run the script AGAIN in the same VM — the idempotency test
./test/vm-test.sh ssh      # shell into the VM to inspect the result
./test/vm-test.sh gui      # boot the VM with a screen attached (see below)
./test/vm-test.sh destroy  # delete the test VM
```

The typical loop: `fresh` → inspect → tweak the script → `fresh` again.
To verify re-runnability: `fresh` → `rerun` → check `~/.macsetup/macsetup_profile`
in the VM has no duplicated lines.

## GUI

A screen can only be attached when the VM boots (Virtualization.framework
limitation), so if it's already running headless: `tart stop macsetup-test`
first, then `./test/vm-test.sh gui`.

- The screen opens as a **"tart" app window** — find it in the Dock / Cmd-Tab.
- It's **black for up to a minute** while macOS boots — that's normal.
- The terminal stays attached while the VM runs; `^C` there powers the VM off.
- Login password: `admin`.

Leftover blank "tart" icons in Cmd-Tab are zombie processes from earlier
headless runs — clean up with `pkill -f "tart run"`.

## Interactive parts

The setup script runs over `ssh -t`, so interactive steps happen in your terminal:

- `gh auth login` — pick the device-code flow; it prints a URL + code you open
  in a browser **on your host**.
- `sudo` inside the VM — password is `admin`.

## Gotchas

- **GitHub SSH keys accumulate**: each fresh VM generates a new
  `~/.ssh/id_ed25519` and uploads it to your GitHub account via
  `gh ssh-key add`. Clean up stale ones now and then: `gh ssh-key list` /
  `gh ssh-key delete <id>`.
- Apple's Virtualization.framework allows **max 2 VMs running at once**.
- The default image (`ghcr.io/cirruslabs/macos-tahoe-vanilla`) is a blank Mac:
  no Homebrew, no Command Line Tools — so the script's brew bootstrap is
  exercised exactly like on a brand-new machine. That bootstrap (Xcode CLT
  download) adds a good 10–20 min to every `fresh`. To iterate faster on the
  post-brew parts of the script use the CI image, which has brew preinstalled:
  `IMAGE=ghcr.io/cirruslabs/macos-tahoe-base:latest ./test/vm-test.sh fresh`
  Other images: https://github.com/orgs/cirruslabs/packages
- GUI apps (casks) install fine headless; use `gui` to actually look at them.
- Reclaim disk: `./test/vm-test.sh destroy` removes the VM; `tart prune`
  clears the image cache (next `fresh` re-downloads).
