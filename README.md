# mySuse

Scripts that configure openSUSE Tumbleweed on a ThinkPad X1 Carbon Gen 10 into `x1-suse`: rolling Linux, btrfs + snapper snapshots every 15 min, KDE Plasma 6 on Wayland, Helium, Floorp, Firefox, LibreOffice, Wi-Fi printers and scanners, Resilio Sync, and pCloud.

All decisions and hardware options are defined in [config.sh](config.sh).

---

## Install

### 1. Download the ISO

Grab openSUSE Tumbleweed from the official download page:
<https://get.opensuse.org/tumbleweed/>

- **Recommended:** Network Image (x86_64) for a fresh net-install, or the KDE/GNOME Live Image if you prefer running `install.sh` directly from a live environment.
- **Write it to USB** (at least 2 GB):
  - Windows: [Rufus](https://rufus.ie/) -> pick the ISO -> Start -> choose **DD Image mode** when prompted.
  - Linux: `dd bs=4M if=openSUSE-Tumbleweed-*.iso of=/dev/sdX status=progress; sync`

### 2. Prepare Windows (Dual Boot or VM Migration)

1. **OEM Product Key:** If wiping Windows to run it in a VM later, record your motherboard license key:
   ```powershell
   (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
   # Saved ThinkPad X1 Key: Q4W3R-TNBK9-XD88X-TTXKP-TMQH2
   ```
2. **BitLocker:** Save your recovery key (`manage-bde -protectors -get C:` in an administrator PowerShell) and suspend protection in Control Panel > BitLocker > Suspend protection. Turning Secure Boot off can trigger a recovery prompt on the next boot if this is skipped.
3. **Fast Startup:** Disable fast startup in Control Panel > Power Options > "Choose what the power buttons do" > uncheck "Turn on fast startup". This prevents Windows from leaving NTFS partitions in an unclean hibernated state.
4. **Make room (if dual-booting):** Open `diskmgmt.msc`, right-click drive C:, and select "Shrink Volume". Leave the freed space **unallocated** (80-100 GiB recommended; 40 GiB minimum). Skip if wiping entire drive.
5. **Hardware Clock:** Set Windows to keep the RTC in UTC by running in an admin PowerShell:
   ```powershell
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
   ```

### 3. BIOS Settings

- Press **F1** on boot to enter ThinkPad BIOS setup.
- Under Security, turn **Secure Boot off** (so custom kernels, out-of-tree modules, and third-party boot components load without signing friction). Keep UEFI enabled.
- Press **F12** on boot to select the USB drive.

---

## Setup Methods

You can set up `mySuse` in two ways:

### Option A: Standard YaST Install (Recommended)

1. Boot the openSUSE Tumbleweed installer USB.
2. Proceed through the installer:
   - **Partitioning:** Use the Guided Setup. Select Btrfs with snapshots. When installing alongside Windows, YaST automatically targets the unallocated space and reuses the existing EFI partition.
   - **Encryption:** Check "Enable disk encryption" (LUKS2) if desired.
   - **Desktop:** Pick Generic Desktop / Minimal X / KDE Plasma.
   - **User:** Set your user name to `marek` and enable sudo privileges.
3. Finish the installation, reboot into openSUSE, and log in.
4. Open a terminal and run:
   ```bash
   sudo zypper install -y git
   git clone https://github.com/marek31/mySuse
   cd mySuse
   sudo ./setup.sh all
   ```

### Option B: Scripted Install from Live USB

If booted into an openSUSE Live desktop/rescue ISO:
1. Ensure network connectivity is up.
2. Open a root terminal:
   ```bash
   zypper in -y git
   git clone https://github.com/marek31/mySuse
   cd mySuse
   ./install.sh
   ```
   `install.sh` handles partitioning, LUKS2 encryption (argon2id), btrfs subvolumes (`@`, `@home`, `@snapshots`, etc.), bootstrapping base packages via `zypper --root /mnt`, configuring fstab, and executing `setup.sh` in chroot.
3. Remove the USB stick and reboot.

If an installation or setup run ever gets interrupted (e.g. Wi-Fi drop), simply boot back into the live session and run `./resume.sh` to remount the filesystems and pick up right where it stopped.

---

## First Login Checklist

| Task | Command / Action |
|---|---|
| Fingerprint reader | `fprintd-enroll` (enables biometric auth for sudo and the lock screen) |
| Firmware updates | `fwupdmgr refresh && fwupdmgr update` |
| Speaker tuning | `sudo ~/mySuse/setup.sh speakers` (converts Lenovo's Dolby Atmos profile from the Windows partition into an EasyEffects preset) |
| Resilio Sync | `resilio` (starts service and opens WebUI on localhost:55555) |
| pCloud storage | `cloud setup` (browser auth), then `cloud open` to mount `~/pCloud` on demand |
| Dev tools | `claude`, `agy` (Antigravity CLI), `omp` (oh-my-pi), `cargo`, `go`, `sbcl` |
| Tailscale mesh | `sudo tailscale up`, then `sudo tailscale set --operator=$USER` |
| Windows 11 VM | `win11-vm create <path/to/win11.iso>` (TPM 2.0, UEFI, VirtIO) or `virt-manager` |
| KDE Connect | Pair from tray icon (firewall opens ports 1714-1764 for LAN) |
| Wallpapers | Default cheat sheet is generated from `files/wallpaper/*.typ`. Great Wave is in `~/Pictures/Wallpapers/great-wave.jpg` |

---

## Windows 11 VM Setup & Offline / Local Account Activation

Running Windows 11 in a KVM virtual machine using the ThinkPad's extracted OEM license key without linking a Microsoft Account:

- **Saved Motherboard Key:** `Q4W3R-TNBK9-XD88X-TTXKP-TMQH2`
- Helper script: `win11-vm` (installed to `/usr/local/bin/win11-vm`)

### 1. Create and Start VM
```bash
win11-vm create ~/Downloads/Win11_24H2_English_x64.iso 64
```
This provisions a 64 GiB VirtIO disk (CoW disabled, Snapper snapshots excluded), 4 vCPUs, 8 GB RAM, `swtpm` TPM 2.0 emulator, and OVMF UEFI Secure Boot firmware.

### 2. Disk Driver (During Setup)
At the *"Where do you want to install Windows?"* prompt:
1. Click **Load driver** -> **Browse**.
2. Select the VirtIO CD drive (`virtio-win`) -> `vioscsi\w11\amd64` (or `amd64\w11`).
3. Select the detected virtual disk to continue installation.

### 3. Bypass Microsoft Account (Local Account Setup)
When the installer asks for network or Microsoft account sign-in:
1. Press `Shift + F10` to open Command Prompt.
2. Run:
   ```cmd
   oobe\bypassnro
   ```
3. The VM restarts. When returning to the network screen, click **I don't have internet** -> **Continue with limited setup**.
4. Enter your desired local username and password.

### 4. Install VirtIO Guest Tools
Once on the desktop:
1. Open File Explorer and navigate to the `virtio-win` CD drive.
2. Run `virtio-win-gt-x64.exe` to install drivers for network, graphics, and memory ballooning.

### 5. Activate Windows
Open Command Prompt as **Administrator** inside the VM:
```cmd
slmgr /ipk Q4W3R-TNBK9-XD88X-TTXKP-TMQH2
slmgr /ato
```
- `/ipk`: registers the OEM product key.
- `/ato`: contacts Microsoft activation servers (activates machine-level license; no Microsoft account required).
- Verify status with `slmgr /xpr` (or run `win11-vm key` from host Linux).

---

## Desktop Environment: KDE Plasma 6

- **KDE Plasma 6 (Wayland):** Powered by the custom look-and-feel package (`org.mysuse.desktop`). Features a sleek 40 px vertical panel on the left edge, borderless maximized windows, animations disabled for zero latency, Inter + JetBrains Mono typography, Papirus icons, and intuitive tiling/desktop shortcuts.
- **Display Manager:** Native SDDM configured with automatic session handling.

---

## Daily Upkeep & Snapshots

- **Updates:** Run `zu` in terminal (an alias for `sudo zypper dup`). Snapper automatically takes pre and post snapshots before and after package changes.
- **Snapshots list:** Run `snaps` to view root and home snapshot history.
- **Dotfile updates:** When updating configuration from this repository, run:
  ```bash
  ~/mySuse/refresh.sh
  ```
  This creates safety snapshots, updates dotfiles, and re-applies Plasma configuration in place.
- **Undo last change:**
  ```bash
  ~/mySuse/refresh.sh undo
  ```
  Reverts the changes made by the last refresh run safely.

---

## Files

| File | Purpose |
|---|---|
| `config.sh` | Central settings: hostname, user, locale, scaling, disk layout, snapshot rules |
| `packages.txt` | Package manifest installed via zypper |
| `install.sh` | Automated partitioner, LUKS formatter, btrfs setup, and bootstrap installer |
| `setup.sh` | Post-install system configuration, hardening, services, desktop, and app build |
| `refresh.sh` | Safe live desktop updates with snapshot rollback safety net |
| `resume.sh` | Rescue chroot runner for live ISO environments |
| `files/` | Configuration templates, dotfiles, wallpapers, and desktop integration scripts |
| `mysuse_design.md` | Architectural rationale, implementation notes, and distribution design log |
