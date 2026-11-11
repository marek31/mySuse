# mySuse Design & Architecture

Architectural choices, rationale, and operational notes for running openSUSE Tumbleweed on the ThinkPad X1 Carbon Gen 10.

---

## Core System Architecture

- **Distribution:** openSUSE Tumbleweed (rolling release). Provides up-to-date kernel, Mesa drivers, Wayland compositors, and development toolchains without frozen-distribution staleness.
- **Init System:** systemd. Unlike runit on Void, systemd provides native socket activation, user session targets (`pipewire.service`, `wireplumber.service`), systemd timers for maintenance tasks, and standard session management.
- **Package Management & Codecs:** `zypper` with openSUSE OSS and Non-OSS repositories. The **Packman** repository is configured at priority 90 with `--allow-vendor-change` so complete multimedia codecs (H.264, AAC, full FFmpeg and GStreamer plugins) are enabled without playback degradation.
- **Filesystem & Snapshots:** Btrfs with Snapper configured strictly on root (`/`) for system safety:
  - Every `zypper` package transaction triggers automatic pre and post snapshots through `snapper-zypp-plugin`.
  - Periodic timeline snapshots are disabled (`TIMELINE_CREATE="no"`) to eliminate background CoW disk churn and battery drain.
  - User directory `/home` lives on a dedicated `@home` subvolume and is **never snapshotted**, ensuring user files, git repos, and application databases are completely immune to root rollbacks.
  - Bootable snapshots in GRUB via `grub2-snapper-plugin`.
  - Root rollback with `snapper rollback`.
  - Dedicated subvolumes (`@`, `@home`, `@snapshots`, `@var_log`, `@var_cache`, `@var_tmp`, `@swap`) ensure system rollbacks do not touch user data, package caches, or logs.
- **Encryption:** LUKS2 with argon2id key derivation (`LUKS_ITER_MS=2000`). Unencrypted `/boot` (ext4) prevents PBKDF2 decryption delays in GRUB. The initramfs prompts for the passphrase once on boot.
- **Swap & Hibernation:** A plain swapfile `/swap/swapfile` inside the `@swap` subvolume. Hibernation resume offsets are calculated via `btrfs inspect-internal map-swapfile` and passed to the kernel command line (`resume=UUID=... resume_offset=...`).

---

## Desktop Environment

### Labwc + Noctalia (Lightweight Windowed Stacking + Modern Shell)
- **Compositor:** `labwc` stacking Wayland compositor inspired by Openbox. Built in C on top of `wlroots`. Delivers instantaneous application launch, zero background churn, pure static declarative configuration in `~/.config/labwc/rc.xml`, and Tokyo-Night-Modern theme with 8px rounded corners and SVG window controls.
- **Desktop Shell:** `noctalia` (Modern Wayland Desktop Shell). Delivers a modern bottom taskbar with app launcher, running window taskbar buttons (`widget.taskbar`) with focus/minimize, native DBus StatusNotifierItem (SNI) system tray, control center (audio, brightness, Wi-Fi, Bluetooth, night light, power profile), lock screen with fingerprint support, notification daemon, clipboard manager, and interactive screenshot & annotation tool.
- **Display & Scaling:** `kanshi` handles dynamic multi-monitor profiles and fractional scaling (1.25x laptop, 1.5x Dell 4K) automatically upon hotplug.
- **Display Manager:** Native SDDM display manager with Breeze theme and automatic Wayland session handling into a single clean `Labwc` entry. System-wide fingerprint authentication enabled via `pam-config --fprintd` for SDDM, sudo, polkit, and Noctalia lockscreen.
- **Session Glue:** `easyeffects` (Dolby Atmos quad-speaker tuning), `swaylock` (fallback lock).

---

## Hardware Optimization (ThinkPad X1 Carbon Gen 10)

- **Power Management:**
  - TLP configured for Alder Lake P-cores and E-cores (`files/tlp.conf`).
  - Active ASPM powersupersave on battery.
  - Kernel command line tuning: `pcie_aspm=force`, `i915.enable_psr=1`, `i915.enable_fbc=1`, `nvme.noacpi=1` for deep Package C-states (C8/C10).
  - Thermald enabled for Intel thermal zone management.
- **Speakers:** Lenovo's proprietary Dolby Atmos tuning from the Windows driver partition is converted on-demand into an EasyEffects preset via `speaker-tuning-to-easyeffects`. Internal quad-speakers achieve full acoustic depth and clarity under PipeWire.
- **Biometrics:** Synaptics 06cb:00fc fingerprint reader configured through `fprintd` and openSUSE's `pam-config -a --fprintd`.

---

## Security

- **Firewall:** `firewalld` configured with default-drop inbound policy. Ports opened selectively for Resilio Sync (55555/tcp, 3838/udp), Tailscale (41641/udp), KDE Connect (1714-1764 LAN), and mDNS.
- **Hardening:** Sysctl parameters (`files/sysctl-hardening.conf`) restricting dmesg, kptr, unprivileged BPF, and ptrace scope.
- **AppArmor:** Enabled in enforce mode across all active profiles.
- **Root Security:** Root account locked; administrative privileges mediated exclusively through `sudo` with daily timestamp caching.

---

## Virtualization & Windows 11 VM

- **Hypervisor:** Kernel-based Virtual Machine (KVM) with QEMU and `libvirt`. Native to openSUSE Tumbleweed, avoiding out-of-tree kernel module breakage during rolling kernel updates.
- **Windows 11 Compatibility:**
  - **TPM 2.0:** Emulated via `swtpm` (backend emulator, model `tpm-tis`).
  - **Firmware:** UEFI with Secure Boot support provided by `qemu-ovmf-x86_64` (Microsoft-enrolled keys).
  - **Chipset & CPU:** Modern `q35` machine type with `host-passthrough` CPU configuration.
  - **Drivers & Performance:** Paravirtualized VirtIO SCSI storage, VirtIO network (`NetKVM`), and SPICE integration via `virtio-win.iso`.
- **Filesystem & Snapshot Isolation:**
  - VM storage paths (`/var/lib/libvirt/images` and `~/VMs`) have Btrfs Copy-on-Write disabled (`chattr +C`) to prevent I/O latency, severe disk fragmentation, and write multiplication.
- **Management:** GUI via `virt-manager` or CLI via `win11-vm` helper tool (`win11-vm create`, `win11-vm start`, `win11-vm key`, `win11-vm drivers`).
- **License & Offline Activation:** Preserves motherboard OEM product key (`win11-vm key`), enabling activation inside the VM via `slmgr` or ACPI table pass-through without linking a Microsoft Account.

---

## Single Entry Point: `refresh.sh` (ADR)

- **Context:** four scripts (`install.sh`, `setup.sh`, `refresh.sh`, `resume.sh`) duplicated logging and root checks, and about 300 lines of config files were embedded as heredocs.
- **Decision:** the system is installed with the standard openSUSE installer (user `marek`, btrfs + snapshots). `refresh.sh` only configures it. There is no live-USB, partitioning or chroot code (dead end, see below).
- **Files, not code (frozen layout):** `files/root/<path>` is deployed to `/<path>` and `files/home/<path>` to `~/<path>` by one `deploy` loop. It replaces `@NAME@` with the setting `NAME` from the top of `refresh.sh` (text files only), skips unchanged files, backs up changed ones (`/root/.backup`, `~/.backup`) and replaces them atomically. The file mode comes from git (644/755). Exception: sudoers is chmod 440 afterwards.
- **Steps:** `files packages system apps user vm boot`. `files` runs first because `packages` needs the repo files it deploys.
- **Resume invariant (frozen):** `/var/lib/mysuse/progress` = line 1 is the sha256 of the repo content (excluding `.git`), followed by one finished step per line. A step is skipped only when the hash matches. The file is deleted after a complete run, so the next run is a full one. Named steps (`refresh.sh apps`) bypass this file. `./refresh.sh selftest` checks it (and `deploy`).
- **One file:** settings, the package list and the self-check live in `refresh.sh`. Everything that is a file on the target system lives in `files/`. No log files: errors print on screen, and a stop ends with "fix the error above, then run ./refresh.sh again". `may` marks commands that are allowed to fail harmlessly (already done, not installed, not logged in); everything else either stops the run or prints a `WARNING`.
- **Pull, then sudo:** run as the user, the script does `git pull`, then `exec sudo bash refresh.sh`, so the pulled version runs as root. `sudo ./refresh.sh` and cron skip the pull. The root-owned copy in `/usr/local/lib/mysuse` (cron runs `apps` from it daily) has no `.git`.
- **`boot` is gated:** dracut + grub.cfg are regenerated only when the hash of `/etc/default/grub`, `/etc/sysconfig/bootloader`, `/etc/crypttab`, `/etc/vconsole.conf` and `/etc/dracut.conf.d/*` changes (`/var/lib/mysuse/boot.sha`).
- **Upstream downloads:** one `fetch URL DEST` (tar or zip, `DEST/.version` = URL, skipped when unchanged or the app is running). Packaged in Tumbleweed OSS instead (checked 2026-11-11): `noctalia`, `jetbrains-mono-fonts`. Not packaged: Cascadia Code, Bibata, ytfzf, Mission Center (Flathub), Helium, GCM, Resilio.

## Dead Ends

- **Scripted install from a live USB** (partitioning, LUKS, `zypper --root`, chroot, resume by partition label): about 250 lines of the most fragile code, used for one install every few years. The standard installer does the same job better.
- **Speaker tuning at every refresh:** the EasyEffects presets made from the Lenovo Dolby XML are committed under `files/home/.local/share/easyeffects`, so regenerating them was redundant. To regenerate: `python3 dolby_to_easyeffects.py files/audio/DEV_0287_*.xml --all-profiles --enable autogain --autoload` from <https://github.com/antoinecellerier/speaker-tuning-to-easyeffects>.

## Known Gotchas

- A new `@NAME@` placeholder in `files/` also needs its line in `render()`. An unlisted placeholder is copied literally, which is how `@DEFAULT_AUDIO_SINK@` (wpctl syntax in `rc.xml`) survives.
- Do not edit `refresh.sh` while it runs: bash reads scripts incrementally. `git pull` is safe because git replaces files instead of rewriting them in place.
- Kernel options are written to `/etc/default/grub`. On a system without GRUB2 (e.g. systemd-boot) the `system` step warns and skips them.
- `taskbar-app`, `foot-open`, `idle-manager`, `imv-dir` and `imv-info` live in `/usr/local/bin` (the SDDM session's PATH has no `~/.local/bin`). The `files` step deletes old copies from `~/.local/bin` so they cannot shadow updates.

---

## Decisions (openSUSE Tumbleweed on x1-suse)

| Area | Decision |
|---|---|
| target | ThinkPad X1 Carbon Gen 10 (21CC): i5-1250P, Iris Xe, 16 GB, 512 GB NVMe, 14" 1920x1200, AX211 wifi, SOF audio, Synaptics 06cb:00fc fingerprint reader, USB4 |
| disk | standard installer: btrfs + snapshots, dual boot next to Windows (shared EFI partition, os-prober menu), LUKS2 optional |
| swap | plain swapfile in the `/swap` subvolume for hibernation; no zram, zswap disabled |
| snapshots | snapper on root only (zypper pre/post pairs), no timeline, `/home` never snapshotted, bootable snapshots in grub |
| desktop | Labwc + Noctalia on Wayland; dark palette, Inter + JetBrains Mono, Bibata cursor, Hokusai "Great Wave" wallpaper |
| dev | Go, Rust (rustup), SBCL, Deno, Claude Code, Antigravity CLI, oh-my-pi, nanobot, Git Credential Manager, GitHub Desktop |
| remote | Remmina, KDE Connect (LAN-only firewall rule), Tailscale |
| vm | KVM/QEMU, libvirt, virt-manager, swtpm (TPM 2.0), OVMF UEFI for Windows 11 |
| upkeep | `refresh.sh apps` daily from cron, update notifications, monthly btrfs scrub, earlyoom, hibernate at 5 % battery |
| browsers | Helium (default, upstream tarball), Opera and Firefox from zypper |
| office / printing | LibreOffice with Polish UI and spelling; CUPS + avahi (IPP Everywhere), sane-airscan |
| sync | Resilio Sync (`resilio`) and pCloud via rclone (`cloud`), nothing autostarted |
| power / security | TLP, thermald; firewalld default-deny inbound, sysctl hardening, AppArmor, no sshd; sudo once a day, fingerprint accepted |

---

## Changelog

- 2026-11-11: Merged `config.sh`, `packages.txt` and `test_refresh.sh` into `refresh.sh` (settings and `PACKAGES` at the top, `./refresh.sh selftest`). Removed the log file and colored helpers: errors print on screen and stop the run. Placeholder `@HOME@` renamed `@UHOME@`; the unused `XKB_LAYOUT` is gone; the decisions list moved here.

- 2026-11-11: Shrank `refresh.sh` to configure-only (no live USB). Config heredocs moved to `files/root` and deployed by the same loop as dotfiles. Packman is a repo file; snapper uses `set-config`; one `fetch` covers all upstream downloads; dev tools use one install table. Dropped: `speakers` step (presets already committed), noctalia source build and JetBrains zip (both in OSS), nftables fallback (firewalld only), legacy plasma/niri/greetd/home-snapper cleanups, `/usr/local/lib/mysuse` `.git`. Removed install-only settings from `config.sh`.

- 2026-11-11: Merged `install.sh`, `setup.sh`, `resume.sh` and the old `refresh.sh` into one `refresh.sh` (install / resume / refresh, step progress file, `test_refresh.sh`). Simplifications: removed the `swap` step (duplicated `base`), the python fallback in `gh_asset` (jq is always installed first), the second Floorp purge in `apps`, duplicate session/xsession cleanups and `mkdir`s, the extra jq/curl install, the swaybg fallback (autostart always starts Noctalia), the GitHub-auth note (README checklist) and the unused `GREETER` setting. `finish` now skips dracut when boot inputs are unchanged. Scripted installs now prompt for the user's login password.
- 2026-11-10: Configured dynamic screen lock and idle timeout management (`idle-manager`): 30 minutes on battery, 1 hour on charger (AC), automatic display off shortly after, and verified fingerprint authentication support across SDDM, PAM (`pam_fprintd`), and Noctalia lockscreen.
- 2026-11-10: Reinforced complete removal of Floorp browser: added unconditional purge of `/opt/floorp`, desktop launchers, and configuration caches across both `step_packages` and `step_apps` in `setup.sh`, and masked existing user desktop entries.
- 2026-11-10: Configured SDDM Chili theme with clean blur and typography defaults; updated `packages.txt` for Qt5 greeter and QtQuick dependencies.
- 2026-11-10: Enhanced Foot terminal: mapped `Control+v`, `Control+Shift+v`, and `XF86Paste` to clipboard-paste (resolving paste blocking from MMAutoKey interception), added `foot-open` smart launcher with Kate line fragment support, and enabled clickable URL/file path detection with mouse bindings (`Control+Left/Right-Click`) and keyboard jump labels (`Control+Shift+o`).
- 2026-11-10: Upgraded taskbar application launching (Meta+1..0 and Meta+Shift+1..0): created dynamic `taskbar-app` script to automatically detect apps at taskbar positions 1..10 (ordered by Noctalia pinned items followed by running unpinned windows). Added Windows-style focus, minimize-toggle, window cycling, and new instance spawning (`--new`). Updated Labwc keybindings, Noctalia pinned defaults, and wallpaper cheat sheet.
- 2026-11-10: Configured imv as default system image viewer: set full screen by default, instant Escape key exit, directory navigation for sibling images via `imv-dir`, Tokyo Night status overlay with live EXIF metadata parsing via `imv-info` and `exiv2`, and updated default MIME associations.
- 2026-11-10: Configured Noctalia screenshot destination and naming pattern: target directory `/home/marek/Github/mydata/t/_screenshots/` and filename template `%Y-%m-%d %H-%M-%S` (`YYYY-MM-DD HH-MM-SS.jpg`).
