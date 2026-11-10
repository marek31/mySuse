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

- **Firewall:** `firewalld` (or `nftables`) configured with default-drop inbound policy. Ports opened selectively for Resilio Sync (55555/tcp, 3838/udp), Tailscale (41641/udp), KDE Connect (1714-1764 LAN), and mDNS.
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
  - `~/VMs` is excluded from automatic 15-minute Snapper snapshots via `HOME_NOSNAP`.
- **Management:** GUI via `virt-manager` or CLI via `win11-vm` helper tool (`win11-vm create`, `win11-vm start`, `win11-vm key`, `win11-vm drivers`).
- **License & Offline Activation:** Preserves motherboard OEM product key (`win11-vm key`), enabling activation inside the VM via `slmgr` or ACPI table pass-through without linking a Microsoft Account.

---

## Changelog

- 2026-11-10: Configured SDDM Chili theme with clean blur and typography defaults; updated `packages.txt` for Qt5 greeter and QtQuick dependencies.
- 2026-11-10: Enhanced Foot terminal: mapped `Control+v`, `Control+Shift+v`, and `XF86Paste` to clipboard-paste (resolving paste blocking from MMAutoKey interception), added `foot-open` smart launcher with Kate line fragment support, and enabled clickable URL/file path detection with mouse bindings (`Control+Left/Right-Click`) and keyboard jump labels (`Control+Shift+o`).
- 2026-11-10: Upgraded taskbar application launching (Meta+1..0 and Meta+Shift+1..0): created dynamic `taskbar-app` script to automatically detect apps at taskbar positions 1..10 (ordered by Noctalia pinned items followed by running unpinned windows). Added Windows-style focus, minimize-toggle, window cycling, and new instance spawning (`--new`). Updated Labwc keybindings, Noctalia pinned defaults, and wallpaper cheat sheet.
