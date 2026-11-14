# mySuse

Turns a basic openSUSE Tumbleweed install on a ThinkPad X1 Carbon Gen 10 into `x1-suse`: rolling Linux, btrfs with snapper snapshots on root, Labwc + Noctalia on Wayland, Helium, Opera, Firefox, LibreOffice, Wi-Fi printing and scanning, Resilio Sync and pCloud.

The whole thing is one script, [refresh.sh](refresh.sh) (host and user names plus the package list at the top), and [files/](files), the config files it copies.

---

## Install

### 1. ISO and USB

Get openSUSE Tumbleweed from <https://get.opensuse.org/tumbleweed/> (Network Image or offline DVD, x86_64) and write it to a USB stick of 2 GB or more:

- Windows: [Rufus](https://rufus.ie/), pick the ISO, Start, choose **DD Image mode** when asked.
- Linux: `dd bs=4M if=openSUSE-Tumbleweed-*.iso of=/dev/sdX status=progress; sync`

### 2. Prepare Windows (dual boot, or before moving it into a VM)

1. **OEM product key** - note it if Windows goes into a VM later:
   ```powershell
   (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
   # Saved ThinkPad X1 Key: Q4W3R-TNBK9-XD88X-TTXKP-TMQH2
   ```
2. **BitLocker** - save the recovery key (`manage-bde -protectors -get C:` in an admin PowerShell) and suspend protection. Without that, turning Secure Boot off can trigger a recovery prompt.
3. **Fast Startup off** - Control Panel > Power Options > "Choose what the power buttons do". Otherwise Windows leaves its NTFS partitions half-hibernated.
4. **Make room** - `diskmgmt.msc`, right-click C:, "Shrink Volume", leave the space **unallocated** (80-100 GiB is comfortable, 40 GiB minimum).
5. **Clock in UTC** (admin PowerShell):
   ```powershell
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
   ```

### 3. BIOS

F1 at boot: Security > **Secure Boot off**, keep UEFI on. F12 at boot picks the USB stick.

### 4. openSUSE installer

- **Partitioning:** guided setup, Btrfs with snapshots. Next to Windows it uses the unallocated space and shares the EFI partition.
- **Encryption:** tick "Enable disk encryption" (LUKS2) if you want it.
- **Desktop:** Generic Desktop / Minimal X.
- **Keyboard, time zone:** Polish, Europe/Warsaw (the script leaves these as the installer set them).
- **User:** `marek`, with sudo rights.

### 5. Run the script

After the first boot, log in and open a terminal:

```bash
sudo zypper install -y git
git clone https://github.com/marek31/mySuse
cd mySuse
./refresh.sh
```

Reboot and pick **Labwc** on the login screen.

---

## refresh.sh

Run it as yourself. It does `git pull`, then runs the pulled version again with `sudo`.

| Situation | Command | What happens |
|---|---|---|
| First run after the install | `./refresh.sh` | all steps: `files packages system apps user` |
| Something failed half way | `./refresh.sh` again | finished steps are skipped (as long as the repo didn't change) |
| Repo changed, or the system drifted | `./refresh.sh` | every step again - each one is safe to repeat |
| Only one part | `./refresh.sh apps` | just the named steps |
| Check the resume logic | `./refresh.sh selftest` | no root needed |

- **Config files are files, not code.** `files/root` is copied to `/` and `files/home` to `~` (rsync, only files whose content differs). Whatever gets replaced is kept in `/root/.backup/<date>` or `~/.backup/<date>`.
- **Errors** print on screen and stop the run with "fix the error above, then run ./refresh.sh again". `may` in the script marks commands that are allowed to fail (already done, not installed, not logged in). `WARNING:` lines are problems that don't stop the run.
- **Upstream apps are pinned.** Helium, Bibata, Cascadia Code and Git Credential Manager are downloaded from fixed release URLs in `step_apps` / `step_user`. To update one (Helium especially - it's a browser), change the version in its URL and run `./refresh.sh apps`. Releases: [Helium](https://github.com/imputnet/helium-linux/releases), [GCM](https://github.com/git-ecosystem/git-credential-manager/releases).

| Step | What it does |
|---|---|
| `files` | copies `files/root` and `files/home`, removes leftovers of files dropped from the repo |
| `packages` | removes unwanted packages, installs `PACKAGES`, switches codecs to Packman |
| `system` | host name, locale, groups, services, firewall, snapper, printer, GDM, libvirt, swapfile and kernel command line |
| `apps` | Helium, Bibata cursor, Cascadia Code, Resilio Sync, ytfzf, Mission Center (Flathub), Helium extensions |
| `user` | rustup, Claude Code, Antigravity CLI, Deno, oh-my-pi, nanobot, Git Credential Manager, MMAutoKey, wallpapers |

---

## After the first login

| Task | How |
|---|---|
| Fingerprint | `fprintd-enroll` (then it works for sudo, GDM and the lock screen) |
| Firmware | `fwupdmgr refresh && fwupdmgr update` |
| GitHub | `git credential-manager github login` (stored in GNOME Keyring), or GitHub Desktop |
| mydata, MMAutoKey | `git clone https://github.com/marek31/mydata ~/Desktop` (the folder must be empty), then `./refresh.sh user` |
| Resilio Sync | `resilio` starts it and opens the WebUI on 127.0.0.1:8888 |
| pCloud | `cloud setup` (browser login), `cloud open` mounts `~/pCloud`; folder pairs for `cloud sync` go in `~/.config/cloud-sync.conf` |
| Tailscale | `sudo tailscale up`, then `sudo tailscale set --operator=$USER` |
| KDE Connect | pair from the tray icon (ports 1714-1764 are open) |
| Windows 11 VM | `win11-vm create <iso>`, see below |

---

## Desktop: Labwc + Noctalia

- **Labwc** - Openbox-style stacking Wayland compositor, Tokyo-Night-Modern theme, configured in `~/.config/labwc/rc.xml`.
- **Noctalia** - the shell: bar on the left with launcher, taskbar, tray, control center (audio, brightness, Wi-Fi, Bluetooth, night light, power profile), notifications, clipboard history, screenshots, lock screen with fingerprint, polkit agent.
- **kanshi** - monitor layouts on hotplug: laptop panel at 1.25, external 4K (Dell G3223Q) at 1.5 to its right. `display-setup` opens wdisplays and saves what you arrange as a new kanshi profile.
- **GDM** login screen (supports fingerprint and password); Labwc is the only session.
- **idle-manager** - locks after 30 min on battery, 1 h on the charger, screen off 5 min later.
- **Speakers** - the X1's quad speakers get Lenovo's Dolby tuning through EasyEffects. The presets (made with [speaker-tuning-to-easyeffects](https://github.com/antoinecellerier/speaker-tuning-to-easyeffects) from the Windows audio driver) are in `files/home/.local/share/easyeffects` and are just copied, so no Windows partition is needed. The internal speaker loads `Dolby-Dynamic-Balanced` automatically.

Keys (Meta = Super; Meta+Shift+/ shows the cheat sheet):

| Keys | Action |
|---|---|
| Meta+Return | terminal (foot) |
| Meta, Meta+D, Meta+Space | launcher |
| Meta+A / Meta+, | control center / Noctalia settings |
| Meta+1..0, Meta+Shift+1..0 | taskbar app 1..10: focus, minimise, cycle / new instance |
| Meta+B / Meta+Shift+B | Helium / Opera |
| Meta+E | Thunar |
| Shift+Esc | btop |
| Meta+Q, Alt+F4 | close window |
| Meta+F / Meta+Shift+F | maximise / fullscreen |
| Meta+Left/Right/Up/Down | snap left/right, maximise, restore or minimise |
| Meta+F1..F4 / Meta+Shift+F1..F4 | go to / send to workspace |
| Meta+L, Meta+Esc | lock |
| PrtSc / Shift+PrtSc | region screenshot with annotation / full screen |

---

## Daily use

- **Updates:** `zu` (= `sudo zypper dup`). Snapper takes a snapshot before and after every zypper change; a desktop notice appears when updates are waiting.
- **Snapshots:** `snaps` lists them, `snapper rollback <n>` goes back. `/home` is a separate subvolume and is never snapshotted or rolled back.
- **Config changes:** edit the repo, then `~/mySuse/refresh.sh`. Labwc and Noctalia reload without logging out.

---

## Windows 11 VM (local account, offline activation)

KVM/QEMU with libvirt, `swtpm` for TPM 2.0, OVMF UEFI with Secure Boot, q35 with host CPU passthrough, VirtIO disk and network. The VM folders (`~/VMs`, `/var/lib/libvirt/images`) have btrfs copy-on-write turned off, which avoids fragmentation and slow I/O.

1. **Create:** `win11-vm create ~/Downloads/Win11_24H2_English_x64.iso 64` - 64 GiB disk, 4 vCPUs, 8 GB RAM. Later `win11-vm start`, or use `virt-manager`.
2. **Disk driver:** at "Where do you want to install Windows?" click Load driver > Browse > `virtio-win` CD > `vioscsi\w11\amd64`.
3. **No Microsoft account:** at the network screen press Shift+F10, run `oobe\bypassnro`. After the restart choose "I don't have internet" > "Continue with limited setup".
4. **Guest tools:** on the desktop run `virtio-win-gt-x64.exe` from the `virtio-win` CD.
5. **Activate** (admin Command Prompt in the VM): `slmgr /ipk Q4W3R-TNBK9-XD88X-TTXKP-TMQH2`, then `slmgr /ato`. Check with `slmgr /xpr`.

---

## How it's built

### System

| Area | Choice |
|---|---|
| hardware | ThinkPad X1 Carbon Gen 10 (21CC): i5-1250P, Iris Xe, 16 GB, 512 GB NVMe, 14" 1920x1200, AX211 Wi-Fi, SOF audio, Synaptics 06cb:00fc fingerprint, USB4 |
| packages | zypper with OSS, Non-OSS and Packman (priority 90, vendor switched) for full codecs; GitHub Desktop from mwt-packages |
| disk | installer defaults: btrfs subvolumes, `/home` separate, optional LUKS2 |
| snapshots | root only, zypper pre/post pairs (10 kept, 4 important), no timeline snapshots, bootable snapshots in grub |
| hibernation | 32 GB swapfile in `/swap`; `resume=UUID=... resume_offset=...` on the kernel command line; zswap off, no zram; hibernates at 5 % battery |
| power | TLP tuned for Alder Lake (`files/root/etc/tlp.d/10-x1.conf`), thermald; kernel options `pcie_aspm=force i915.enable_psr=1 i915.enable_fbc=1 nvme.noacpi=1` for deep package C-states |
| security | firewalld (only mDNS, Resilio 55555/tcp + 3838/udp, Tailscale 41641/udp, KDE Connect 1714-1764), sysctl hardening, AppArmor, no sshd; sudo asks for your password once a day, fingerprint works too |
| browsers | Helium (default, upstream tarball, extensions installed by `helium-install-extensions`), Opera and Firefox from zypper |
| sync | Resilio Sync (`resilio`) and pCloud through rclone (`cloud`); nothing autostarts. The official pCloud app: `pcloud-install` |
| dev | Go, Rust, SBCL, Deno, Typst, Claude Code, Antigravity CLI, oh-my-pi, nanobot, Git Credential Manager, GitHub Desktop |

### Decisions

- **The installer installs, the script configures.** A scripted live-USB install (partitioning, LUKS, `zypper --root`, chroot) was tried and dropped: around 250 lines of the most fragile code, for one install every few years.
- **Files, not heredocs.** Anything that ends up as a file on the system is a real file under `files/`, laid out like its target. The script copies them with rsync and holds no file contents itself. Values (user name, scales, ports) are written straight into the files - one user, one laptop.
- **Resume.** `/var/lib/mysuse/progress` holds the hash of the repo content, then one finished step per line. A step is skipped only if the hash still matches; the file is deleted after a complete run. Named steps ignore it.
- **Defaults where they are good enough.** Keyboard, console font, time zone and autologin-off come from the installer. Labwc's own session file, imv's and foot's default keys, and libinput's default acceleration are kept. Theme colours for foot, GTK and Qt come from Noctalia.
- **Upstream downloads only for what Tumbleweed doesn't package** (checked 2026-11-11): Helium, Git Credential Manager, Resilio, Bibata, Cascadia Code, ytfzf, Mission Center (Flathub). `noctalia` and `jetbrains-mono-fonts` come from OSS.

### Gotchas

- Don't edit `refresh.sh` while it runs - bash reads scripts as it goes. `git pull` is safe because git replaces the file instead of rewriting it.
- `taskbar-app`, `foot-open`, `idle-manager`, `imv-dir`, `imv-info` live in `/usr/local/bin`, because the SDDM session's PATH has no `~/.local/bin`.
- Files removed from `files/` stay on the system until they're added to the leftovers list in `step_files`.
- The kernel command line is set as a whole in `/etc/default/grub` (GRUB2, the installer's default).
- The `mydata` repo lives in `~/Desktop`: MMAutoKey (`code/MMAutoKey`), the Helium sync extension (`code/MMBrowserSync`) and Noctalia screenshots (`t/_screenshots`) use that path.

### Changelog

- 2026-11-11: Upstream downloads pinned to full release URLs (no GitHub API lookup); with nothing left to auto-update, the daily cron run of `apps`, `power-ok` and the root-owned repo copy in `/usr/local/lib/mysuse` are gone. `mydata` moved from `~/Github/mydata` to `~/Desktop`. Removed the MMAutoKey auto-install from `config.fish`.
- 2026-11-11: `mysuse_design.md` merged into this README. `files/` cut down: dropped `mmterm`, `gitpullpush_mydata.sh`, the Mission Center wrappers, the `btop` wrapper, `snapper-tick`, `labwc-suse-session`, the kanshi and MMAutoKey user units, the mako D-Bus mask, the duplicate Helium extension lists, `fonts-local.conf`, the Dolby XML, and files whose defaults are fine (hostname, locale, console, autologin, SDDM state, Thunar state, foot theme). No more `@PLACEHOLDERS@`; files are copied with rsync. Steps `vm` and `boot` merged into `system`. Fixes: MMAutoKey's installer was looked for in the wrong folder; `update-notify` was never started; the Polish keyboard layout wasn't set in Labwc; the cursor theme didn't match SDDM; `mimeapps.list` pointed archives at the removed file-roller.
- 2026-11-11: `config.sh`, `packages.txt` and the test merged into `refresh.sh`; no log file, errors on screen.
- 2026-11-11: `refresh.sh` became configure-only; config heredocs moved to `files/root`; one `fetch` for upstream downloads; packaged `noctalia` and JetBrains Mono instead of building/downloading them.
- 2026-11-11: `install.sh`, `setup.sh`, `resume.sh` and the old `refresh.sh` merged into one script with resume.
- 2026-11-10: `idle-manager` (30 min on battery, 1 h on AC), fingerprint across SDDM, sudo and the Noctalia lock screen.
- 2026-11-10: Floorp removed for good; SDDM Chili theme.
- 2026-11-10: foot: Ctrl+V paste (MMAutoKey intercepted the old binding), `foot-open` opens files at a line in Kate, clickable URLs and paths.
- 2026-11-10: `taskbar-app` for Meta+1..0 (Windows-style focus, minimise, cycle, new instance).
- 2026-11-10: imv as image viewer: fullscreen, Esc quits, sibling images, EXIF overlay.
- 2026-11-10: Noctalia screenshots go to `~/Github/mydata/t/_screenshots` as `YYYY-MM-DD HH-MM-SS.jpg`.
