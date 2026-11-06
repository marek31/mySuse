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

## Desktop Environment

### KDE Plasma 6 (Wayland)
- **Look & Feel:** Configured via the custom look-and-feel package `org.mysuse.desktop`:
  - Single 40 px vertical panel on the left edge (application launcher, desktop pager, icon-only tasks, system tray, clock).
  - Borderless maximized windows and no window borders.
  - Zero latency: animations disabled (`AnimationDurationFactor 0`).
  - Dark theme with Papirus-Dark / Breeze-Dark icons and typography set to Inter (UI) and JetBrains Mono (fixed-width).
  - Clean desktop containment without desktop icons.
- **Shortcuts:** Clean, ergonomic shortcuts (Super+Return terminal, Super+D KRunner, Super+Q close, Super+F maximize, Super+1..4 desktops, Meta+Shift+/ key cheat sheet).
- **Display Manager:** Native SDDM display manager with automatic Wayland session handling.

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

- 2026-11-06: Added single-instance btop launcher and KWin window activation (Ctrl+Shift+Esc), Typst double-click compile-and-view workflow (.typ -> typst c -> Okular PDF), and Mission Center (Windows 11-style Task Manager via Flathub).
- 2026-11-06: Boosted UI & burst responsiveness: instant Alt+Tab (0ms delay, no window highlight stall in plasma-suse-config v12), TLP battery profile switched to BAL with 18% min perf (~800 MHz floor), and integrated CachyOS sysctl responsiveness tunables.
- 2026-11-06: Integrated MMAutoKey Linux auto-installation (`setup.sh`, `plasma-suse-session`, and `config.fish` hooks with uinput udev rules and systemd autostart watchdog).
- 2026-11-06: Documented OEM license key extraction and offline / local-account VM activation workflow (`win11-vm key`).
- 2026-11-05: Added Windows 11 virtualization stack (KVM, QEMU, libvirt, swtpm, OVMF Secure Boot, virt-manager, win11-vm helper, Btrfs nodatacow tuning).

- 2026-10-25: Transitioned to pure KDE Plasma 6 desktop environment. Removed Noctalia and Niri build dependencies, configured native SDDM display manager, and refined custom left-panel look-and-feel package.
- 2026-10-24: Initial release of `mySuse` configuration suite adapted for openSUSE Tumbleweed.
- Added native systemd services, Zypper package manifests with Packman codecs, and Snapper integration.
