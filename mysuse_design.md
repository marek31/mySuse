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
- **Display Manager:** Native SDDM display manager with automatic Wayland session handling launching directly into Labwc + Noctalia.
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

- 2026-11-09: Scaled mouse cursor down by 1/3 (reduced from 30px to 20px) across Labwc environment, GTK 3/4, XSettings, and KDE defaults. Configured libinput adaptive acceleration profile (`accelProfile: adaptive`, `pointerSpeed: 0.2`) across all pointer devices for precision in small micro-movements and speed across long screen distances.
- 2026-11-09: Removed KDE Plasma 6 secondary desktop environment, configuration scripts, and patterns; streamlined system exclusively around Labwc + Noctalia modern stacking Wayland environment.
- 2026-11-09: Fixed MMAutoKey autostart in Labwc, added mmterm and gitpullpush_mydata wrappers, enabled selection-target=both in Foot terminal configuration, and installed Thunar Open Terminal Here shortcut (F4).
- 2026-11-08: Synchronized fast keyboard repeating (200ms delay, 100 repeats/s rate, NumLock off) from Windows settings across Labwc, Xwayland, GNOME/GTK, and KDE Plasma. Reduced mouse scroll lines jumped by 1/3 (Labwc non-touch scrollFactor 0.67, Plasma wheelScrollLines 2 & mouse ScrollFactor 1.0).
- 2026-11-07: Integrated Noctalia desktop shell (`noctalia-dev/noctalia`) with Labwc: bottom capsule taskbar with launcher, running task buttons, system tray, control center (audio, brightness, Wi-Fi, Bluetooth, night light, power profile), lock screen with fingerprint support, notification daemon, and interactive screenshot & annotation tool.
- 2026-11-07: Upgraded Labwc desktop experience: integrated custom Tokyo-Night-Modern theme with 8px rounded corners and SVG window controls, 30px balanced 4K cursor scaling, thumbnail Alt-Tab OSD, and restored optimal TLP power settings (removed CPU/GPU frequency floors, balance_performance EPP, ASPM powersave, systemd-boot kernel cmdline power tuning, idle CPU power reduced from ~12W to ~2-3W).
- 2026-11-07: Added lightweight windowed Wayland desktop session: Labwc + Sfwbar. Integrated Kanshi display scaling (1.25x laptop + 1.5x 4K), Fuzzel launcher, Mako notifications, and dual SDDM session selector.
- 2026-11-06: Set taskbar hover delay to 1ms (plasmarc PlasmaToolTips Delay in plasma-suse-config v16) for instant grouped window list previews.
- 2026-11-06: Added single-instance btop launcher and KWin window activation (Ctrl+Shift+Esc), Typst double-click compile-and-view workflow (.typ -> typst c -> Okular PDF), and Mission Center (Windows 11-style Task Manager via Flathub).
- 2026-11-06: Boosted UI & burst responsiveness: instant Alt+Tab (0ms delay, no window highlight stall in plasma-suse-config v12), TLP battery profile switched to BAL with 18% min perf (~800 MHz floor), and integrated CachyOS sysctl responsiveness tunables.
- 2026-11-06: Integrated MMAutoKey Linux auto-installation (`setup.sh`, `plasma-suse-session`, and `config.fish` hooks with uinput udev rules and systemd autostart watchdog).
- 2026-11-06: Documented OEM license key extraction and offline / local-account VM activation workflow (`win11-vm key`).
- 2026-11-05: Added Windows 11 virtualization stack (KVM, QEMU, libvirt, swtpm, OVMF Secure Boot, virt-manager, win11-vm helper, Btrfs nodatacow tuning).

- 2026-10-25: Transitioned to pure KDE Plasma 6 desktop environment. Removed Noctalia and Niri build dependencies, configured native SDDM display manager, and refined custom left-panel look-and-feel package.
- 2026-10-24: Initial release of `mySuse` configuration suite adapted for openSUSE Tumbleweed.
- Added native systemd services, Zypper package manifests with Packman codecs, and Snapper integration.
