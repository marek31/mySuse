#!/usr/bin/env bash
# mySuse: turn a basic openSUSE Tumbleweed install into x1-suse, and bring it back to this state later.
#
#   ./refresh.sh             git pull, then run every step. After a failure run it again: finished steps are
#                            skipped (unless the repo changed since, then all run again). Every step is repeatable.
#   ./refresh.sh apps        run only the named steps:  files  packages  system  apps  user
#   ./refresh.sh selftest    check the resume logic (no root needed)
#
# files/root is copied to /, files/home to ~ (a replaced file is kept in /root/.backup or ~/.backup).
set -Eeuo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE_DIR=/var/lib/mysuse
LOG_DIR=/var/log/mysuse
LOG_FILE=""
WARNINGS=()
ALL_STEPS=(files packages system user apps)
HOSTNAME=x1-suse
USERNAME=marek                # login created in the openSUSE installer
UHOME=/home/$USERNAME

PACKAGES=(
    # base, boot, filesystem
    kernel-default kernel-firmware-intel kernel-firmware-bluetooth kernel-firmware-network sof-firmware alsa-firmware
    grub2-x86_64-efi efibootmgr cryptsetup btrfs-progs compsize dracut
    snapper snapper-zypp-plugin grub2-snapper-plugin inotify-tools os-prober
    chrony cronie rsync
    # desktop: Labwc + Noctalia
    labwc noctalia kanshi swaylock swayidle wlr-randr grim slurp fontawesome-fonts
    sddm sddm-greeter-qt5 libqt5-qtquickcontrols libqt5-qtgraphicaleffects
    polkit polkit-default-privs dbus-1 xwayland
    gnome-keyring seahorse dconf xdg-user-dirs xdg-utils wl-clipboard libnotify-tools earlyoom
    adwaita-icon-theme papirus-icon-theme kf6-breeze-icons breeze5-icons
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk wdisplays
    # hardware: Iris Xe, AX211 wifi, SOF audio, Synaptics fingerprint, USB4
    Mesa-dri vulkan-intel intel-media-driver vulkan-tools libva-utils
    thermald fwupd fprintd fprintd-pam libfprint-2-2 bolt brightnessctl playerctl
    tlp tlp-rdw tlp-pd powertop
    # audio, network, bluetooth
    pipewire wireplumber pipewire-pulseaudio pipewire-alsa alsa-ucm-conf pavucontrol qpwgraph
    easyeffects lsp-plugins python3-numpy python3-scipy python3-rich
    NetworkManager bluez wireguard-tools firewalld nftables apparmor-utils
    tailscale
    # printing (IPP Everywhere) and scanning (eSCL/AirScan)
    cups cups-filters system-config-printer gutenprint
    sane-backends sane-airscan simple-scan avahi nss-mdns
    # office
    libreoffice libreoffice-l10n-pl myspell-pl_PL myspell-en_US hyphen-pl mythes-pl
    # browsers & media runtime
    MozillaFirefox opera
    libXfixes3 libva2 fuse fuse3
    # fonts
    noto-sans-fonts noto-serif-fonts noto-coloremoji-fonts noto-sans-cjk-fonts
    dejavu-fonts liberation-fonts croscore-fonts
    google-roboto-fonts symbols-only-nerd-fonts jetbrains-mono-fonts saja-cascadia-code-fonts
    # files, media, desktop apps
    foot wlrctl lswt thunar thunar-volman thunar-plugin-archive gvfs
    udisks2 ntfs-3g dosfstools
    okular zathura zathura-plugin-pdf-poppler sioyek xournalpp pdfarranger poppler-tools qpdf ghostwriter glow
    geeqie qimgv imv exiv2 mpv vlc strawberry gimp kolourpaint krita audacity ffmpeg yt-dlp chafa
    remmina kdeconnect-kde qbittorrent calibre kate qalculate-qt fsearch qdirstat gparted
    meld kdiff3 krename ncmpcpp keepassxc restic rclone flatpak
    # virtualization: KVM, QEMU, libvirt, TPM 2.0, UEFI for Windows 11
    qemu-kvm qemu-ovmf-x86_64 libvirt libvirt-daemon-qemu libvirt-daemon-config-network virt-manager virt-install virt-viewer swtpm iptables dnsmasq
    # shell and CLI tools
    fish bash-completion starship eza bat ripgrep fd fzf zoxide tmux vim neovim mc nnn
    htop btop nmon iftop nmap speedtest-cli duf plocate lsof strace usbutils pciutils smartmontools
    curl wget jq unzip zip 7zip xz zstd man-pages tealdeer trash-cli acl bind-utils fastfetch
    # development
    patterns-devel-base-devel_basis git git-lfs gh cmake python3 python3-pip go typst sbcl github-desktop libsecret-1-0 git-credential-libsecret
)

UNWANTED=(power-profiles-daemon hplip hplip-hp-plugin hplip-sane kweather p7zip udiskie blueman
    NetworkManager-applet file-roller icewm icewm-default icewm-config-upstream icewm-lang
    mako cliphist waybar sfwbar fuzzel gdm)

# =============================================================== helpers

ts()   { date '+%F %T'; }
say()  { echo "[$(ts)] ==> $*"; }
warn() {
    echo "[$(ts)] WARNING: $*" >&2
    WARNINGS+=("$*")
}
err()  { echo "[$(ts)] ERROR: $*" >&2; }
may()  { "$@" >/dev/null 2>&1 || true; }   # allowed to fail: already done, not installed, not logged in

# run a command as $USERNAME in a clean login-like environment
as_user() {
    (cd "$UHOME" && runuser -u "$USERNAME" -- env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND \
        HOME="$UHOME" USER="$USERNAME" LOGNAME="$USERNAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USERNAME")" \
        PATH="$UHOME/.local/bin:$UHOME/.cargo/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin" "$@")
}

# fetch URL DEST [STRIP]: unpack a .tar.* or .zip into DEST; skipped when DEST already came from URL
fetch() {
    local url=$1 dest=$2 strip=${3:-0} tmp
    [[ $(cat "$dest/.version" 2>/dev/null) != "$url" ]] || return 0
    if pgrep -f "^$dest/" >/dev/null; then warn "$dest is running - update postponed"; return 0; fi
    say "  $url -> $dest"
    mkdir -p "$(dirname "$dest")"
    tmp=$(mktemp -d "$dest.new.XXXXXX")
    if curl -fsSL --retry 3 --max-time 900 -o "$tmp.pkg" "$url" &&
        case $url in
            *.zip) command -v unzip >/dev/null && unzip -q "$tmp.pkg" -d "$tmp" ;;
            *)     tar -xf "$tmp.pkg" -C "$tmp" --strip-components="$strip" --no-same-owner ;;
        esac
    then
        echo "$url" > "$tmp/.version"
        chmod 755 "$tmp"                    # mktemp -d makes it 700
        rm -rf "$dest"
        mv "$tmp" "$dest"
    else
        warn "download or unpack failed: $url"
        rm -rf "$tmp"
    fi
    rm -f "$tmp.pkg"
}

# =============================================================== step: files

step_files() {
    say "files: files/root -> /  and  files/home -> ~"
    command -v rsync >/dev/null || zypper -n in --no-recommends rsync >/dev/null
    # -c: compare contents, -E: keep the executable bit; replaced files go to a dated backup folder
    local stamp sync=(rsync -rlcE --out-format='  %n')
    stamp=$(date '+%F %H-%M-%S')
    "${sync[@]}" --backup --backup-dir="/root/.backup/$stamp" "$HERE/files/root/" /
    as_user "${sync[@]}" --backup --backup-dir="$UHOME/.backup/$stamp" "$HERE/files/home/" "$UHOME/"
    chmod 440 /etc/sudoers.d/10-mysuse
    find /usr/local/bin /etc/NetworkManager/dispatcher.d -maxdepth 1 -type f -exec chmod +x {} +
    rm -rf /usr/local/bin/__pycache__

    # leftovers of files that were removed from this repo
    rm -f "$UHOME"/.local/bin/{btop,mmterm,gitpullpush_mydata.sh,mission-center,missioncenter} \
        "$UHOME"/.local/bin/{taskbar-app,foot-open,idle-manager,imv-dir,imv-info} \
        "$UHOME"/.config/systemd/user/{kanshi.service,mmautokey.service,graphical-session.target.wants/kanshi.service} \
        /usr/local/bin/{snapper-tick,labwc-suse-session,power-ok}
    rm -rf /usr/local/lib/mysuse

    may sysctl --system
    may udevadm control --reload-rules
    may chgrp input /dev/uinput
    may chmod 0660 /dev/uinput
}

# =============================================================== step: packages

step_packages() {
    say "packages: drop unwanted ones, install PACKAGES, switch codecs to Packman"
    zypper --gpg-auto-import-keys refresh || warn "some repositories failed to refresh"

    local installed
    mapfile -t installed < <(rpm -q --qf '%{NAME}\n' "${UNWANTED[@]}" | grep -v ' ' || true)
    [[ ${#installed[@]} -eq 0 ]] || zypper -n rm -u "${installed[@]}" || warn "could not remove: ${installed[*]}"
    rm -rf /opt/floorp /usr/local/bin/floorp /usr/local/share/applications/floorp.desktop \
        "$UHOME/.local/share/applications/floorp.desktop" "$UHOME/.config/floorp" "$UHOME/.cache/floorp"

    zypper -n --ignore-unknown in --no-recommends --auto-agree-with-licenses --force-resolution "${PACKAGES[@]}" ||
        warn "some packages could not be installed"
    zypper -n dup --from packman --allow-vendor-change || warn "switch to Packman codecs failed"
}

# =============================================================== step: system

step_system() {
    say "system: login, groups, security, services, firewall, name, snapshots, printer, VMs, hibernation"

    # login screen: SDDM + Chili theme (files/root), Labwc as the only session, no autologin
    find /usr/share/wayland-sessions /usr/share/xsessions -name '*.desktop' ! -name labwc.desktop -delete 2>/dev/null || true
    may systemctl disable gdm
    systemctl enable sddm || warn "SDDM could not be enabled"     # takes over at the next boot
    may update-alternatives --set default-displaymanager /usr/lib/X11/displaymanagers/sddm
    may sed -i 's/^DISPLAYMANAGER_AUTOLOGIN=.*/DISPLAYMANAGER_AUTOLOGIN=""/' /etc/sysconfig/displaymanager

    # groups: sudo, audio/video, uinput (MMAutoKey), VMs; groups that do not exist are left out
    local groups
    groups=$( { getent group wheel audio video input disk storage network libvirt kvm || true; } | cut -d: -f1 | paste -sd,)
    [[ -z $groups ]] || usermod -aG "$groups" "$USERNAME" || warn "usermod failed for $USERNAME"

    # security: fingerprint for sudo/SDDM/polkit/lock screen; firewall: mDNS, Resilio, Tailscale, KDE Connect
    may pam-config -a --fprintd
    firewall-cmd -q --permanent --add-service=mdns --add-port=55555/tcp --add-port=3838/udp \
        --add-port=41641/udp --add-port=1714-1764/tcp --add-port=1714-1764/udp || warn "firewall ports not set"
    may firewall-cmd -q --permanent --zone=trusted --add-interface=tailscale0
    may firewall-cmd -q --reload

    # services
    local s
    for s in apparmor firewalld tlp tlp-pd thermald earlyoom udisks2 bluetooth cronie libvirtd snapper-cleanup.timer; do
        systemctl enable --now "$s" || warn "service $s could not be enabled"
    done
    for s in smartd cups-browsed ipp-usb snapper-timeline.timer; do may systemctl disable --now "$s"; done

    # name and language (time zone, keyboard and console come from the installer)
    may hostnamectl set-hostname "$HOSTNAME"
    may localectl set-locale LANG=en_US.UTF-8 LC_{TIME,PAPER,MEASUREMENT,MONETARY}=pl_PL.UTF-8

    # snapshots: root only, keep 10 zypper pre/post pairs (4 important), no timeline
    snapper -c root set-config TIMELINE_CREATE=no NUMBER_CLEANUP=yes NUMBER_MIN_AGE=1800 \
        NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=4 || warn "snapper root config not set"

    # printer: Brother DCP-L2530DW over IPP Everywhere, simplex, normal quality
    local p=Brother_DCP-L2530DW_series opts=(-o Duplex=None -o sides=one-sided -o cupsPrintQuality=Normal -o Collate=True)
    may lpadmin -p "$p" -E -v "ipp://Brother%20DCP-L2530DW%20series._ipp._tcp.local/" -m everywhere "${opts[@]}"
    may lpadmin -d "$p"
    may as_user lpoptions -d "$p" "${opts[@]}" -o copies=1

    # virtual machines: libvirt default network, VM folders without btrfs copy-on-write
    may virsh net-autostart default
    may virsh net-start default
    mkdir -p /var/lib/libvirt/images
    may as_user mkdir -p "$UHOME/VMs"
    may chattr +C /var/lib/libvirt/images "$UHOME/VMs"

    # hibernation: 32 GB swapfile, resume offset on the kernel command line, Windows in the grub menu
    if [[ ! -f /swap/swapfile ]]; then
        if bash /usr/local/bin/set-swap 32; then
            dracut --force || warn "dracut failed"   # the initramfs learns where to resume from
        else
            warn "swapfile setup failed"
        fi
    fi
    may swapon /swap/swapfile
    local cmdline="quiet splash loglevel=3 zswap.enabled=0 apparmor=1 security=apparmor pcie_aspm=force"
    cmdline+=" i915.enable_psr=1 i915.enable_fbc=1 nvme.noacpi=1 workqueue.power_efficient=1"
    if [[ -f /swap/swapfile ]]; then
        local swap_uuid swap_offset
        swap_uuid=$(findmnt -no UUID -T /swap/swapfile 2>/dev/null || true)
        swap_offset=$(btrfs inspect-internal map-swapfile -r /swap/swapfile 2>/dev/null || true)
        if [[ -n $swap_uuid && -n $swap_offset ]]; then
            cmdline+=" resume=UUID=$swap_uuid resume_offset=$swap_offset"
        fi
    fi
    sed -i -e "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" \
        -e '/^#\?\s*GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub || warn "grub config update failed"
    echo 'GRUB_DISABLE_OS_PROBER="false"' >> /etc/default/grub || true
    update-bootloader --refresh || grub2-mkconfig -o /boot/grub2/grub.cfg || warn "bootloader refresh failed"
}

# =============================================================== step: apps

# Upstream downloads, pinned: to update one, change its version in the URL and run ./refresh.sh apps
step_apps() {
    say "upstream apps: Helium, Bibata cursor, Resilio Sync, ytfzf, Mission Center"
    fetch https://github.com/imputnet/helium-linux/releases/download/0.21.2.1/helium-0.21.2.1-x86_64_linux.tar.xz /opt/helium 1
    fetch https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Classic.tar.xz /usr/local/share/icons/Bibata-Modern-Classic 1
    fetch https://download-cdn.resilio.com/stable/linux/x64/0/resilio-sync_x64.tar.gz /opt/resilio-sync
    fetch https://github.com/pystardust/ytfzf/archive/refs/tags/v2.6.2.tar.gz /opt/ytfzf 1

    [[ ! -x /opt/resilio-sync/rslsync ]] || ln -sf /opt/resilio-sync/rslsync /usr/local/bin/rslsync
    if [[ ! -x /usr/local/bin/ytfzf && -d /opt/ytfzf ]]; then
        make -C /opt/ytfzf install doc addons >/dev/null || warn "ytfzf build/install failed"
    fi
    may flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y --noninteractive flathub io.missioncenter.MissionCenter >/dev/null || warn "Mission Center not installed"
    as_user python3 /usr/local/bin/helium-install-extensions || warn "Helium extensions not installed"
}

# =============================================================== step: user

step_user() {
    say "user tools: Git Credential Manager, git config, dev CLIs, MMAutoKey, wallpapers"

    # Git Credential Manager with the Secret Service store, like on Windows
    fetch https://github.com/git-ecosystem/git-credential-manager/releases/download/v3.0.2/gcm-linux-x64-3.0.2.tar.gz /opt/git-credential-manager
    if [[ -x /opt/git-credential-manager/git-credential-manager ]]; then
        ln -sf /opt/git-credential-manager/git-credential-manager /usr/local/bin/git-credential-manager
    else
        warn "Git Credential Manager binary not found"
    fi
    may as_user git config --global core.longpaths true
    may as_user git config --global --unset-all credential.helper
    may as_user git config --global --add credential.helper ""        # "" drops helpers set in /etc/gitconfig
    may as_user git config --global --add credential.helper manager
    may as_user git config --global credential.credentialStore secretservice

    # installer scripts, skipped when the tool is already there (path relative to ~)
    local -A tools=(
        [.cargo/bin/rustc]='curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path'
        [.local/bin/claude]='curl -fsSL https://claude.ai/install.sh | bash'
        [.local/bin/agy]='curl -fsSL https://antigravity.google/cli/install.sh | bash'
        [.deno/bin/deno]='curl -fsSL https://deno.land/install.sh | sh -s -- -y'
        [.local/bin/omp]='curl -fsSL https://omp.sh/install | sh -s -- --binary'
        [.local/bin/nanobot]='curl -fsSL https://raw.githubusercontent.com/HKUDS/nanobot/main/scripts/install.sh | NANOBOT_SKIP_WIZARD=1 sh'
    )
    local bin
    for bin in "${!tools[@]}"; do
        [[ -x $UHOME/$bin ]] || as_user bash -o pipefail -c "${tools[$bin]}" || warn "install failed: ~/$bin"
    done

    # MMAutoKey, once mydata is cloned into ~/Desktop (its install.sh adds the autostart and menu entries)
    local mm=$UHOME/Desktop/code/MMAutoKey/install.sh
    if [[ -f $mm ]]; then as_user bash "$mm" || warn "MMAutoKey install failed"; fi

    # wallpapers: Great Wave (public domain) and the key cheat sheet rendered from files/wallpaper
    local wp=$UHOME/Pictures/Wallpapers
    as_user mkdir -p "$wp" "$UHOME/Desktop/t/_screenshots"
    if [[ ! -s $wp/great-wave.jpg ]]; then
        as_user curl -fsSL --max-time 120 -o "$wp/great-wave.jpg.part" \
            https://upload.wikimedia.org/wikipedia/commons/a/a5/Tsunami_by_hokusai_19th_century.jpg &&
            as_user mv "$wp/great-wave.jpg.part" "$wp/great-wave.jpg" || warn "wallpaper download failed"
    fi
    as_user typst compile --root "$HERE/files/wallpaper" "$HERE/files/wallpaper/keys-labwc.typ" "$wp/keys-labwc.png" ||
        warn "cheat-sheet wallpaper not rendered"
}

# =============================================================== step runner

repo_hash() {
    (cd "$HERE" && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}

# Named steps run as asked. Without names: all steps, skipping those an interrupted run of the
# same repo content already finished. Progress file: line 1 = repo hash, then one finished step per line.
run_steps() {
    local s state=$STATE_DIR/progress
    if [[ $# -gt 0 ]]; then
        for s; do
            declare -F "step_$s" >/dev/null || { echo "ERROR: unknown step '$s' (steps: ${ALL_STEPS[*]})" >&2; exit 1; }
        done
        for s; do
            say "starting step: $s"
            "step_$s"
            say "finished step: $s"
        done
        return 0
    fi
    mkdir -p "$STATE_DIR"
    [[ $(head -n1 "$state" 2>/dev/null) == "$(repo_hash)" ]] || repo_hash > "$state"
    for s in "${ALL_STEPS[@]}"; do
        if grep -qx "$s" "$state"; then say "$s: already done in the interrupted run"; continue; fi
        say "starting step: $s"
        "step_$s"
        echo "$s" >> "$state"
        say "finished step: $s"
    done
    rm -f "$state"
}

# =============================================================== self-check: ./refresh.sh selftest

selftest() (
    T=$(mktemp -d)
    trap 'rm -rf "$T"' EXIT
    fail() { echo "selftest FAILED: $*" >&2; exit 1; }
    STATE_DIR=$T/state
    RAN=$T/ran
    HASH=v1
    ALL_STEPS=(a b c)
    step_a() { echo a >> "$RAN"; }
    step_b() { [[ -z ${FAIL_B:-} ]] || exit 1; echo b >> "$RAN"; }   # exit = how a failing step ends a run
    step_c() { echo c >> "$RAN"; }
    repo_hash() { echo "$HASH"; }
    ran() { [[ $(tr -d '\n' < "$RAN") == "$1" ]] || fail "$2 (ran '$(tr -d '\n' < "$RAN")')"; : > "$RAN"; }
    : > "$RAN"

    (FAIL_B=1 run_steps) && fail "an interrupted run reported success"
    ran a   "interrupted run"
    run_steps >/dev/null;           ran bc  "resume skips finished steps"
    [[ ! -e $STATE_DIR/progress ]] || fail "progress kept after a complete run"
    run_steps;                      ran abc "a complete run is followed by a full run"
    (FAIL_B=1 run_steps) || true;   ran a   "second interruption"
    HASH=v2; run_steps;             ran abc "a repo change restarts all steps"
    run_steps c;                    ran c   "a named step runs alone"
    echo "selftest ok"
)

# =============================================================== main

if [[ ${1:-} == selftest ]]; then selftest; exit; fi

# as yourself: update the repo, then run the freshly pulled script as root
if [[ $EUID -ne 0 ]]; then
    git -C "$HERE" pull --ff-only || warn "git pull failed - using the local copy"
    exec sudo bash "$HERE/refresh.sh" "$@"
fi
id "$USERNAME" >/dev/null 2>&1 || { err "user '$USERNAME' does not exist - create it in the openSUSE installer"; exit 1; }

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/refresh-$(date '+%F_%H-%M-%S').log"
ln -sfn "$LOG_FILE" "$LOG_DIR/latest.log"
exec > >(tee -a "$LOG_FILE") 2>&1

on_err() {
    local rc=$? line=${BASH_LINENO[0]:-?} func=${FUNCNAME[1]:-main} cmd=${BASH_COMMAND:-?}
    err "in '$func' at line $line (exit $rc): $cmd"
}
on_exit() {
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        err "stopped (exit $rc) - see log: $LOG_FILE"
        err "fix the error above, then run ./refresh.sh again"
    fi
}
trap on_err ERR
trap on_exit EXIT

say "refresh.sh started (args: ${*:-all}; log: $LOG_FILE)"
run_steps "$@"
may pkill -HUP -x labwc                      # = labwc --reconfigure
may as_user noctalia msg config-reload

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "[$(ts)] WARNING: completed with ${#WARNINGS[@]} warning(s):" >&2
    for w in "${WARNINGS[@]}"; do
        echo "  - $w" >&2
    done
fi
say "done (log: $LOG_FILE)"
