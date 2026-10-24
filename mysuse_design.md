# mySuse Design & Architecture

Architectural choices, rationale, and operational notes for running openSUSE Tumbleweed on the ThinkPad X1 Carbon Gen 10.

---

## Core System Architecture

- **Distribution:** openSUSE Tumbleweed (rolling release). Provides up-to-date kernel, Mesa drivers, Wayland compositors, and development toolchains without frozen-distribution staleness.
- **Init System:** systemd. Unlike runit on Void, systemd provides native socket activation, user session targets (`pipewire.service`, `wireplumber.service`), systemd timers for maintenance tasks, and standard session management.
- **Package Management & Codecs:** `zypper` with openSUSE OSS and Non-OSS repositories. The **Packman** repository is configured at priority 90 with `--allow-vendor-change` so complete multimedia codecs (H.264, AAC, full FFmpeg and GStreamer plugins) are enabled without playback degradation.
- **Filesystem & Snapshots:** Btrfs with Snapper. Snapper was created by SUSE and is deeply integrated into Tumbleweed:
  - Every `zypper` transaction triggers automatic pre and post snapshots through `snapper-zypp-plugin`.
  - Bootable snapshots in GRUB via `grub2-snapper-plugin`.
  - Root rollback with `snapper rollback`.
  - Dedicated subvolumes (`@`, `@home`, `@snapshots`, `@var_log`, `@var_cache`, `@var_tmp`, `@swap`) ensure system rollbacks do not revert user data, package caches, or logs.
- **Encryption:** LUKS2 with argon2id key derivation (`LUKS_ITER_MS=2000`). Unencrypted `/boot` (ext4) prevents PBKDF2 decryption delays in GRUB. The initramfs prompts for the passphrase once on boot.
- **Swap & Hibernation:** A plain swapfile `/swap/swapfile` inside the `@swap` subvolume. Hibernation resume offsets are calculated via `btrfs inspect-internal map-swapfile` and passed to the kernel command line (`resume=UUID=... resume_offset=...`).

---

## Desktop Environments

### 1. Niri + Noctalia Shell (Primary)
- **Compositor:** Niri scrollable-tiling Wayland compositor. Runs on native Wayland with `xwayland-satellite` for rootless X11 legacy support.
- **Shell & Theming:** Noctalia shell built from source using release tags. Provides the Kanagawa palette, unified status bar on the left edge, and theme distribution to Foot, GTK 3/4, Qt 5/6, KDE, btop, and Starship.
- **Keybindings:** 140 consistent shortcuts documented in the desktop cheat sheet.

### 2. KDE Plasma 6 (Secondary)
- **Look & Feel:** Configured via look-and-feel package `org.mysuse.desktop` to mirror Niri's design:
  - One 40 px vertical panel on the left edge (launcher, desktop pager, icon tasks, tray, clock).
  - No window decorations or borders on maximized windows.
  - Animations disabled for instantaneous response.
  - Font and palette synchronization with Noctalia.
- **Shortcuts:** Mapped to match Niri equivalents (Super+Return terminal, Super+D KRunner, Super+Q close, Super+F maximize, Super+1..4 desktops).

### 3. Display Manager
- **Greeter:** `greetd` running `tuigreet` on VT 1. Text-based, fast, and light. Pressing **F3** switches between Niri and Plasma.

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

## Changelog

- 2026-10-24: Initial release of `mySuse` configuration suite adapted for openSUSE Tumbleweed.
- Added native systemd services, Zypper package manifests with Packman codecs, and Snapper integration.
