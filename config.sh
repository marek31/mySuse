# shellcheck shell=bash
# Every install decision lives here. install.sh and setup.sh source this file.
#
# Decisions (openSUSE Tumbleweed):
#   distro      openSUSE Tumbleweed x86_64, systemd, btrfs + snapper, Packman multimedia
#   target      ThinkPad X1 Carbon Gen 10 (21CC): i5-1250P, Iris Xe, 16 GB, 512 GB NVMe, 14" 1920x1200,
#               AX211 wifi, SOF audio, Synaptics 06cb:00fc fingerprint reader, USB4/Thunderbolt
#   disk        X1: dual boot - openSUSE goes into unallocated space between C: and Windows Recovery,
#               sharing Windows' 260 MB EFI partition (grub next to Windows Boot Manager, os-prober menu).
#               VM/blank disk: GPT, 1 GiB EFI + 1 GiB /boot + rest. Either way /boot is plain ext4 and the
#               rest btrfs inside LUKS2 (argon2id, ENCRYPT=yes): the initramfs asks
#               for the passphrase once, ~2 s, no grub wait. ENCRYPT=no = plain btrfs, no passphrase
#   swap        plain swapfile on disk (@swap subvolume); no zram, zswap disabled
#   btrfs       @ / @home / @snapshots / @var_log / @var_cache / @var_tmp / @swap, /tmp is tmpfs
#   snapshots   snapper, root + home every 15 min; caches, logs, temp, swap, snapshots are separate
#               subvolumes so they are never snapshotted; grub2-snapper-plugin lists snapshots in the boot menu
#   desktop     Wayland only: KDE Plasma 6 with mySuse look-and-feel (left panel, dark theme), SDDM login
#   look        minimal: dark palette, thin vertical panel on the left edge, Inter + JetBrains Mono,
#               Bibata cursor, Hokusai "Great Wave" wallpaper (public domain)
#   dev         Go, Rust (rustup), Common Lisp (SBCL), Deno, Claude Code, Antigravity CLI (agy), oh-my-pi (omp)
#   remote      RustDesk (upstream package), Remmina; KDE Connect for the phone (LAN-only firewall rule)
#   upkeep      browsers auto-update once a day, update notifications, monthly btrfs scrub,
#               smartd, earlyoom, hibernate at 5 % battery, USB automount (udisks2)
#   browsers    Helium (default) + Floorp: upstream tarballs in /opt, updated by `setup.sh apps`;
#               Firefox from zypper
#   office      LibreOffice (Polish UI pack + spelling)
#   printing    CUPS + cups-browsed + avahi (wifi/IPP Everywhere), sane-airscan for network scanners
#   sync        Resilio Sync (run `resilio`) and pCloud via rclone (`cloud`), nothing autostarted;
#               the official pCloud app stays available through pcloud-install
#   kernel      openSUSE Tumbleweed rolling stock kernel (kernel-default)
#   init        systemd
#   power       TLP, thermald
#   security    firewalld / nftables default-deny inbound, sysctl hardening, AppArmor enforce, root locked,
#               no sshd, wifi MAC randomisation, Resilio WebUI on localhost only, UPnP off
#   sudo        password once per day, shared across terminals; fingerprint accepted for sudo
#   fonts       open-licence families that also install on Windows (Noto, Inter, JetBrains Mono,
#               Cascadia Code, IBM Plex, Fira, Source, Liberation, Carlito/Caladea, ...)

HOSTNAME=x1-suse
USERNAME=marek          # login name: shadow's useradd rejects capitals, so "Marek" becomes the full name
FULLNAME=Marek
TIMEZONE=Europe/Warsaw
LANG_UI=en_US.UTF-8     # program language
LANG_FORMATS=pl_PL.UTF-8 # dates, money, paper (A4), units
CONSOLE_KEYMAP=pl2
CONSOLE_FONT=eurlatgr   # readable console font
XKB_LAYOUT=pl           # "pl" basic variant == Polish (programmer's)
DISPLAY_SCALE=1.25      # laptop panel (eDP-1, 1920x1200 14") in Plasma; 1.0-1.5 are sane
DISPLAY_SCALE_4K=1.5    # external 4K monitors (Dell G3223Q 32"); Windows uses 150 % on it

INSTALL_MODE=""         # free = new partition in the largest unallocated area, keep Windows (dual boot)
                        # wipe = erase a whole disk; empty = install.sh asks (default free if there is space)
MIN_FREE_GIB=40         # smallest unallocated area offered for "free"
DISK=""                 # wipe mode only, e.g. /dev/nvme0n1; empty = install.sh asks
ENCRYPT=yes             # no = plain btrfs, boots without a passphrase; yes = LUKS2 on everything except /boot
LUKS_ITER_MS=2000       # argon2id unlock time: ~2 s at boot, cryptsetup default
BOOT_MIB=1024           # unencrypted /boot (kernels + initramfs)
ESP_MIB=1024
SWAP_GIB=16             # = RAM
BTRFS_OPTS="noatime,compress=zstd:1"
REPO_OSS=https://download.opensuse.org/tumbleweed/repo/oss
REPO_NON_OSS=https://download.opensuse.org/tumbleweed/repo/non-oss
REPO_PACKMAN=https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed

SNAPSHOT_EVERY_MIN=15
SNAP_KEEP_HOURLY=24     # older 15-min snapshots collapse into hourly/daily/... after 1 h
SNAP_KEEP_DAILY=7
SNAP_KEEP_WEEKLY=4
SNAP_KEEP_MONTHLY=3
# Paths under /home/$USERNAME turned into nested subvolumes = excluded from home snapshots.
HOME_NOSNAP=(.cache .local/share/Trash .local/share/resilio-sync .pcloud)

GREETER=sddm            # login screen: sddm (graphical display manager)

SUDO_TIMEOUT_MIN=1440   # ask for the sudo password once per day
RESILIO_PORT=55555      # fixed listening port, opened in the firewall
