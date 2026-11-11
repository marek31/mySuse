# mySuse

Scripts that configure openSUSE Tumbleweed on a ThinkPad X1 Carbon Gen 10 into `x1-suse`: rolling Linux, btrfs + snapper snapshots on root, Labwc + Noctalia (modern desktop shell on stacking Wayland), Helium, Opera, Firefox, ytfzf, LibreOffice, Wi-Fi printers and scanners, Resilio Sync, and pCloud.

Everything is in [refresh.sh](refresh.sh) (settings and package list at the top) and [files/](files).

---

## Install

### 1. Download the ISO

Grab openSUSE Tumbleweed from the official download page:
<https://get.opensuse.org/tumbleweed/>

- **Recommended:** Network Image (x86_64) or the offline DVD image.
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

## Setup

1. Boot the openSUSE Tumbleweed installer USB.
2. Proceed through the installer:
   - **Partitioning:** Use the Guided Setup. Select Btrfs with snapshots. When installing alongside Windows, YaST automatically targets the unallocated space and reuses the existing EFI partition.
   - **Encryption:** Check "Enable disk encryption" (LUKS2) if desired.
   - **Desktop:** Pick Generic Desktop / Minimal X.
   - **User:** Set your user name to `marek` and enable sudo privileges.
3. Finish the installation, reboot into openSUSE, and log in.
4. Open a terminal and run:
   ```bash
   sudo zypper install -y git
   git clone https://github.com/marek31/mySuse
   cd mySuse
   ./refresh.sh
   ```
5. Reboot and pick **Labwc** on the login screen.

`refresh.sh` is the only script. Run it as yourself: it does `git pull`, then re-runs itself with `sudo`.

| Situation | Command | What happens |
|---|---|---|
| First run after the install | `./refresh.sh` | All steps: files, packages, system, apps, user, vm, boot |
| Something failed in the middle | `./refresh.sh` again | Steps that already finished are skipped (if the repo is unchanged) |
| Repo changed, or the system drifted | `./refresh.sh` | All steps again; every step is safe to repeat |
| Only one part | `./refresh.sh apps vm` | Just those steps |

Config files are not written by the script but copied from `files/root` (to `/`) and `files/home` (to `~`), with `@NAME@` replaced by the setting `NAME` from the top of `refresh.sh`. A file that differs is backed up first (`/root/.backup`, `~/.backup`) and then replaced. Errors are printed on screen and stop the run; fix them and run `./refresh.sh` again. `./refresh.sh selftest` checks the resume and file-copy logic without root.

---

## First Login Checklist

| Task | Command / Action |
|---|---|
| Fingerprint reader | `fprintd-enroll` (enables biometric auth for sudo and the lock screen) |
| Firmware updates | `fwupdmgr refresh && fwupdmgr update` |
| Resilio Sync | `resilio` (starts service and opens WebUI on localhost:55555) |
| pCloud storage | `cloud setup` (browser auth), then `cloud open` to mount `~/pCloud` on demand |
| Dev tools | `claude`, `agy` (Antigravity CLI), `omp` (oh-my-pi), `cargo`, `go`, `sbcl`, `git-credential-manager` |
| GitHub auth | `git credential-manager github login` (OAuth login stored in GNOME Keyring) or launch `github-desktop` |
| Tailscale mesh | `sudo tailscale up`, then `sudo tailscale set --operator=$USER` |
| Windows 11 VM | `win11-vm create <path/to/win11.iso>` (TPM 2.0, UEFI, VirtIO) or `virt-manager` |
| KDE Connect | Pair from tray icon (firewall opens ports 1714-1764 for LAN) |
| MMAutoKey | Clone `mydata` (`git clone https://github.com/marek31/mydata ~/Github/mydata`) — MMAutoKey installs and autostarts automatically |
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

## Desktop Environment: Labwc + Noctalia

Configured as the primary stacking Wayland desktop:

### Labwc + Noctalia (Lightweight Windowed Stacking + Modern Shell)
- **Compositor:** `labwc` (Openbox-style stacking Wayland compositor). Instantaneous launch, zero-latency window movement, and pure static XML configuration (`~/.config/labwc/rc.xml`).
- **Desktop Shell:** `noctalia` (Modern Wayland Desktop Shell). Provides a bottom taskbar with integrated launcher, running taskbar buttons with focus/minimize, native DBus system tray, control center (audio, brightness, Wi-Fi, Bluetooth, night light, power profile), lock screen with fingerprint support, notification daemon, and interactive screenshot & annotation tool.
- **Display & Scaling:** `kanshi` handles ThinkPad X1 1.25x laptop scaling and external Dell 4K 1.5x scaling automatically on hotplug.
- **Display Manager:** Native SDDM with Chili theme configured with automatic session handling into Labwc.
- **Keybindings:** Super+Return (terminal), Super+D / Super+Space (Noctalia launcher), Super+A (control center), Super+Comma (settings), Super+Q (close), Super+F (maximise), Super+Left/Right/Up (edge snapping), Super+1..0 (taskbar apps by position), Super+Shift+1..0 (new instance), Super+F1..F4 (workspaces), Super+L / Super+Esc (Noctalia lock), PrtSc (interactive region screenshot & annotate), Shift+PrtSc (full screen screenshot), Super+Shift+/ (cheat sheet), Right-click desktop (app menu).

---

## Daily Upkeep & Snapshots

- **Updates:** Run `zu` in terminal (an alias for `sudo zypper dup`). Snapper automatically takes pre and post snapshots of root before and after package changes.
- **Snapshots list:** Run `snaps` to view root snapshot history (`snapper -c root list`). User data in `/home` lives on a dedicated subvolume and is never snapshotted or rolled back.
- **Configuration updates:** After changing this repository, or to undo drift on the system, run:
  ```bash
  ~/mySuse/refresh.sh
  ```
  It pulls the repo, re-applies every step (previous dotfiles are saved to `~/.backup`, system files to `/root/.backup`) and reloads Labwc and Noctalia without logging out. The initramfs and grub.cfg are rebuilt only when their inputs changed.

---

## Files

| File | Purpose |
|---|---|
| `refresh.sh` | The only script: settings, package list, steps. Configures a fresh install, resumes a failed run, brings the system back to this repo |
| `files/root/` | System files, same paths as under `/` (sudoers, repos, SDDM, cron, policies, `/usr/local/bin` helpers) |
| `files/home/` | Dotfiles, same paths as under `~` |
| `files/wallpaper/`, `files/audio/` | Cheat-sheet wallpaper source; Lenovo Dolby XML the EasyEffects presets were made from |
| `mysuse_design.md` | Architectural rationale, implementation notes, and distribution design log |
