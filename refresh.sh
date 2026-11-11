#!/usr/bin/env bash
# mySuse - the only script. Run it whenever you like; it calls sudo itself.
#   live USB, no mySuse on disk -> install: partition, LUKS2 + btrfs, bootstrap, configure in a chroot
#   live USB, mySuse on disk    -> resume: reopen + remount it, finish the bootstrap, configure in a chroot
#   installed system            -> git pull, then bring the system back to what this repo defines
# An interrupted run continues at the step that did not finish (same repo content); any repo change
# restarts all steps. Every step is idempotent.
# Usage: ./refresh.sh [step...]
# Steps: base packages user security snapper desktop dotfiles vm apps login devtools speakers finish
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SELF=$HERE/$(basename "${BASH_SOURCE[0]}")
# shellcheck source=config.sh
source "$HERE/config.sh"
FILES=$HERE/files
UHOME=/home/$USERNAME
ALL_STEPS=(base packages user security snapper desktop vm apps login devtools speakers finish)

log() { printf '\e[1;34m==> %s\e[0m\n' "$*"; }
warn() { printf '\e[1;33m!! %s\e[0m\n' "$*" >&2; }
die() { printf '\e[1;31m!! %s\e[0m\n' "$*" >&2; exit 1; }

in_chroot() { [[ $(stat -c %d:%i /) != "$(stat -c %d:%i /proc/1/root/. 2>/dev/null)" ]]; }
is_live() { grep -qE '(^| )(root=live:|rd\.live\.image)' /proc/cmdline || [[ $(findmnt -no FSTYPE /) == overlay ]]; }

put() {
    local tmp
    mkdir -p "$(dirname "$2")"
    tmp=$(mktemp "$2.tmp.XXXXXX")
    cat > "$tmp"
    if [[ -f $2 ]] && cmp -s "$tmp" "$2"; then rm -f "$tmp"; return 0; fi
    if [[ -f $2 ]]; then
        mkdir -p /root/.backup
        cp -a "$2" "/root/.backup/$(basename "$2") $(date '+%F %H-%M-%S')"
    fi
    chmod "$1" "$tmp"
    mv -f "$tmp" "$2"
}

setkv() {
    local file=$1 key=$2 val=$3
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if grep -q "^#*\s*${key}=" "$file"; then
        sed -i "s|^#*\s*${key}=.*|${key}=\"${val}\"|" "$file"
    else
        printf '%s="%s"\n' "$key" "$val" >> "$file"
    fi
}

as_user() {
    local vars=(HOME="$UHOME" USER="$USERNAME" LOGNAME="$USERNAME"
        PATH="$UHOME/.local/bin:$UHOME/.cargo/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin")
    local rt
    rt=/run/user/$(id -u "$USERNAME" 2>/dev/null || true)
    [[ -d $rt ]] && vars+=(XDG_RUNTIME_DIR="$rt")
    (cd "$UHOME" && runuser -u "$USERNAME" -- env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND \
        "${vars[@]}" "$@")
}

cmdline_set() {
    local key=$1 val=${2:-} opt
    [[ -n $val ]] && opt="$key=$val" || opt="$key"
    if command -v update-bootloader >/dev/null 2>&1; then
        update-bootloader --add-option "$opt" 2>/dev/null || true
    fi
    if [[ -f /etc/default/grub ]]; then
        local line out=() word found=0
        line=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/\1/p' /etc/default/grub)
        for word in $line; do
            if [[ $word == "$key" || $word == "$key="* ]]; then
                out+=("$opt")
                found=1
            else
                out+=("$word")
            fi
        done
        [[ $found -eq 0 ]] && out+=("$opt")
        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${out[*]}\"|" /etc/default/grub
        else
            echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${out[*]}\"" >> /etc/default/grub
        fi
    fi
}

tpl() {
    sed -e "s|@USERNAME@|$USERNAME|g" \
        -e "s|@HOME@|$UHOME|g" \
        -e "s|@SCALE@|$DISPLAY_SCALE|g" \
        -e "s|@SCALE_4K@|$DISPLAY_SCALE_4K|g" \
        -e "s|@XKB@|$XKB_LAYOUT|g" \
        -e "s|@HOSTNAME@|$HOSTNAME|g" \
        -e "s|@RESILIO_PORT@|$RESILIO_PORT|g" \
        "$1"
}

# ---------------------------------------------------------------- live USB: install / resume

ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
SUBVOLS=("@:/" "@home:/home" "@snapshots:/.snapshots" "@var_log:/var/log"
         "@var_cache:/var/cache" "@var_tmp:/var/tmp" "@swap:/swap")

part() { [[ $DISK =~ [0-9]$ ]] && echo "${DISK}p$1" || echo "${DISK}$1"; }
esp_of() { lsblk -lnpo NAME,PARTTYPE "$1" | awk -v t="$ESP_TYPE" 'tolower($2) == t {print $1; exit}'; }
partlabel() { lsblk -lnpo NAME,PARTLABEL ${2:+"$2"} | awk -v l="$1" '$2 == l {print $1}'; }

free_areas() {
    local d ss
    for d in "${DISKS[@]}"; do
        ss=$(blockdev --getss "$d")
        sfdisk -F "$d" 2>/dev/null | awk -v d="$d" -v ss="$ss" -v min="$MIN_FREE_GIB" \
            '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $3 * ss >= min * 2^30 {printf "%.0f %s %s %s\n", $3 * ss, d, $1, $2}'
    done | sort -rn
}

# root partition of an earlier mySuse install (sfdisk name=root, LUKS or btrfs), empty if none
find_existing() {
    local p
    for p in $(partlabel root); do
        [[ $(blkid -s TYPE -o value "$p") =~ ^(crypto_LUKS|btrfs)$ ]] && { echo "$p"; return 0; }
    done
    return 0
}

new_part() {
    local before
    before=$(lsblk -lnpo NAME "$DISK" | sort)
    echo "start=$1, size=$2, type=linux, name=$3" | sfdisk -q --append "$DISK"
    udevadm settle
    comm -13 <(echo "$before") <(lsblk -lnpo NAME "$DISK" | sort)
}

# interactive and destructive: choose free space or a whole disk, partition, format
new_target() {
    local FREE fbytes fdisk default START END SS BOOT_SECT SIZE confirm PASS PASS2
    mapfile -t DISKS < <(lsblk -dnpo NAME,TYPE,RO | awk '$2 == "disk" && $3 == 0 {print $1}' |
        while read -r d; do lsblk -nrpo MOUNTPOINT "$d" | grep -q . || echo "$d"; done)
    [[ ${#DISKS[@]} -gt 0 ]] || die "no usable unmounted disk found (disks with active mountpoints are skipped; umount -R /mnt?)"
    lsblk -po NAME,SIZE,FSTYPE,LABEL,PARTLABEL "${DISKS[@]}"
    FREE=$(free_areas | head -n1)
    if [[ -z $INSTALL_MODE ]]; then
        echo
        default=wipe
        if [[ -n $FREE ]]; then
            default=free
            read -r fbytes fdisk _ _ <<< "$FREE"
            echo "  free  new partition in the $((fbytes >> 30)) GiB of unallocated space on $fdisk - other partitions untouched (dual boot)"
        fi
        echo "  wipe  erase one whole disk"
        read -rp "Install mode [$default]: " INSTALL_MODE
        INSTALL_MODE=${INSTALL_MODE:-$default}
    fi

    case $INSTALL_MODE in
    free)
        [[ -n $FREE ]] || die "no unallocated area of at least $MIN_FREE_GIB GiB"
        read -r fbytes DISK START END <<< "$FREE"
        ESP=$(esp_of "$DISK")
        [[ -n $ESP ]] || die "no EFI system partition on $DISK to share"
        echo "openSUSE gets two new partitions in the $((fbytes >> 30)) GiB of free space on $DISK: /boot ($BOOT_MIB MiB) and the rest$([[ $ENCRYPT == yes ]] && echo ", encrypted")."
        echo "The EFI partition $ESP is shared."
        read -rp "Type yes to continue: " confirm
        [[ $confirm == yes ]] || die "aborted"
        ;;
    wipe)
        until printf '%s\n' "${DISKS[@]}" | grep -qxF -- "$DISK"; do
            [[ -n $DISK ]] && warn "$DISK is not one of the disks listed above"
            read -rp "Target disk [${DISKS[0]}]: " DISK
            DISK=${DISK:-${DISKS[0]}}
        done
        read -rp "EVERYTHING on $DISK will be destroyed. Type the disk path again to confirm: " confirm
        [[ $confirm == "$DISK" ]] || die "aborted"
        ;;
    *) die "INSTALL_MODE must be free or wipe, not '$INSTALL_MODE'" ;;
    esac

    if [[ $ENCRYPT == yes ]]; then
        read -rsp "Disk encryption passphrase: " PASS; echo
        read -rsp "Repeat passphrase: " PASS2; echo
        [[ -n $PASS && $PASS == "$PASS2" ]] || die "passphrases empty or different"
    fi

    if [[ $INSTALL_MODE == wipe ]]; then
        log "partitioning $DISK"
        ESP=$(part 1); BOOT=$(part 2); ROOT=$(part 3)
        wipefs -af "$DISK"
        sfdisk -q "$DISK" <<EOF
label: gpt
size=${ESP_MIB}MiB, type=uefi, name=EFI
size=${BOOT_MIB}MiB, type=linux, name=boot
type=linux, name=root
EOF
        udevadm settle
        mkfs.vfat -F32 -n EFI "$ESP"
    else
        log "adding /boot and root partitions in the free space on $DISK"
        SS=$(blockdev --getss "$DISK")
        START=$(( (START + 2047) / 2048 * 2048 ))
        BOOT_SECT=$(( BOOT_MIB * 1048576 / SS ))
        SIZE=$(( (END - START - BOOT_SECT + 1) / 2048 * 2048 ))
        BOOT=$(new_part "$START" "$BOOT_SECT" boot)
        ROOT=$(new_part "$((START + BOOT_SECT))" "$SIZE" root)
        [[ -b $BOOT && -b $ROOT ]] || die "could not find the new partitions on $DISK"
    fi
    mkfs.ext4 -q -F -L boot "$BOOT"

    if [[ $ENCRYPT == yes ]]; then
        log "encrypting $ROOT (LUKS2, argon2id)"
        cryptsetup close cryptroot 2>/dev/null || true
        printf '%s' "$PASS" | cryptsetup luksFormat --type luks2 --pbkdf argon2id --iter-time "$LUKS_ITER_MS" -q --key-file=- "$ROOT"
        printf '%s' "$PASS" | cryptsetup open --allow-discards --key-file=- "$ROOT" cryptroot
        DEV=/dev/mapper/cryptroot
    else
        DEV=$ROOT
    fi
    mkfs.btrfs -q -f -L opensuse "$DEV"
}

open_existing() {
    ROOT=$1
    DISK=/dev/$(lsblk -no PKNAME "$ROOT")
    BOOT=$(partlabel boot "$DISK" | head -n1)
    ESP=$(esp_of "$DISK")
    [[ -b $BOOT && -n $ESP ]] || die "found $ROOT but not its /boot or EFI partition on $DISK"
    if [[ $(blkid -s TYPE -o value "$ROOT") == crypto_LUKS ]]; then
        cryptsetup status cryptroot >/dev/null 2>&1 || cryptsetup open --allow-discards "$ROOT" cryptroot
        DEV=/dev/mapper/cryptroot
    else
        DEV=$ROOT
    fi
    [[ $(blkid -s TYPE -o value "$DEV") == btrfs ]] ||
        die "$DEV holds no btrfs - the install stopped while formatting; run again and answer n to start over"
}

mount_target() {
    local sv
    if ! mountpoint -q /mnt; then
        mount -o subvolid=5 "$DEV" /mnt
        for sv in "${SUBVOLS[@]}"; do
            [[ -d /mnt/${sv%%:*} ]] || btrfs subvolume create "/mnt/${sv%%:*}" >/dev/null
        done
        umount /mnt
        mount -o "$BTRFS_OPTS,subvol=@" "$DEV" /mnt
    fi
    for sv in "${SUBVOLS[@]:1}"; do
        mkdir -p "/mnt${sv#*:}"
        mountpoint -q "/mnt${sv#*:}" || mount -o "$BTRFS_OPTS,subvol=${sv%%:*}" "$DEV" "/mnt${sv#*:}"
    done
    mkdir -p /mnt/boot
    mountpoint -q /mnt/boot || mount "$BOOT" /mnt/boot
    mkdir -p /mnt/boot/efi
    mountpoint -q /mnt/boot/efi || mount "$ESP" /mnt/boot/efi
    chmod 1777 /mnt/var/tmp
}

bootstrap() {
    local sv fs_uuid
    log "bootstrapping openSUSE Tumbleweed"
    mkdir -p /mnt/etc/zypp/repos.d /mnt/etc/dracut.conf.d
    zypper --root /mnt lr repo-oss >/dev/null 2>&1 || zypper --root /mnt addrepo --refresh "$REPO_OSS" repo-oss
    zypper --root /mnt lr repo-non-oss >/dev/null 2>&1 || zypper --root /mnt addrepo --refresh "$REPO_NON_OSS" repo-non-oss
    zypper --root /mnt --gpg-auto-import-keys refresh
    zypper --root /mnt install -y --no-recommends patterns-base-enhanced_base patterns-base-base \
        kernel-default grub2-x86_64-efi btrfs-progs dracut cryptsetup zypper

    log "writing fstab"
    fs_uuid=$(blkid -s UUID -o value "$DEV")
    {
        for sv in "${SUBVOLS[@]}"; do
            echo "UUID=$fs_uuid ${sv#*:} btrfs $BTRFS_OPTS,subvol=${sv%%:*} 0 0"
        done
        echo "UUID=$(blkid -s UUID -o value "$BOOT") /boot ext4 defaults,noatime 0 2"
        echo "UUID=$(blkid -s UUID -o value "$ESP") /boot/efi vfat defaults,umask=0077 0 2"
        echo "tmpfs /tmp tmpfs defaults,nosuid,nodev,mode=1777 0 0"
        echo "/swap/swapfile none swap defaults 0 0"
    } > /mnt/etc/fstab
    if [[ $DEV != "$ROOT" ]]; then
        echo "cryptroot UUID=$(blkid -s UUID -o value "$ROOT") none luks,discard" > /mnt/etc/crypttab
    fi
}

live_install() {
    local existing ans=""
    echo "mySuse installer - openSUSE Tumbleweed - $HOSTNAME - log: $LOG"
    [[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode - enable EFI in the BIOS settings and boot the live ISO again"
    ping -c1 -W5 download.opensuse.org >/dev/null || die "no network connection available"

    existing=$(find_existing)
    [[ -n $existing ]] && read -rp "mySuse install found on $existing - resume it? [Y/n] " ans
    if [[ -n $existing && ${ans,,} != n* ]]; then open_existing "$existing"; else new_target; fi
    mount_target
    bootstrap

    log "entering chroot to configure the system"
    local d
    for d in sys dev proc; do
        mountpoint -q "/mnt/$d" || { mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; }
    done
    cp -L /etc/resolv.conf /mnt/etc/
    rm -rf /mnt/root/mySuse
    cp -r "$HERE" /mnt/root/mySuse
    chroot /mnt /bin/bash -c 'grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=openSUSE &&
        exec bash /root/mySuse/refresh.sh "$@"' _ "$@"

    mkdir -p /mnt/var/log/mysuse
    cp "$LOG" /mnt/var/log/mysuse/
    swapoff /mnt/swap/swapfile 2>/dev/null || true
    umount -R /mnt || die "unmount failed - run 'umount -lR /mnt' and reboot"
    [[ $DEV == "$ROOT" ]] || cryptsetup close cryptroot
    log "done - remove the USB stick, reboot, log in and run ~/mySuse/refresh.sh once more (speakers, user services)"
}

# ---------------------------------------------------------------- system configuration steps

ensure_swap() {
    if [[ ! -f /swap/swapfile ]]; then
        log "creating ${SWAP_GIB}GB on-disk swapfile on /swap/swapfile..."
        bash "$FILES/set-swap" "$SWAP_GIB"
    elif ! grep -q /swap/swapfile /proc/swaps 2>/dev/null; then
        swapon /swap/swapfile 2>/dev/null || true
    fi

    local uuid dev off
    dev=$(findmnt -no SOURCE /swap 2>/dev/null || true)
    if [[ -n $dev ]]; then
        uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
        off=$(btrfs inspect-internal map-swapfile -r /swap/swapfile 2>/dev/null || true)
        if [[ -n $uuid && -n $off ]]; then
            cmdline_set resume "UUID=$uuid"
            cmdline_set resume_offset "$off"
        fi
    fi
}

step_base() {
    log "base configuration: hostname, locale, console, grub command line, swap"
    echo "$HOSTNAME" > /etc/hostname
    hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || true

    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

    setkv /etc/locale.conf LANG "$LANG_UI"
    setkv /etc/locale.conf LC_TIME "$LANG_FORMATS"
    setkv /etc/locale.conf LC_PAPER "$LANG_FORMATS"
    setkv /etc/locale.conf LC_MEASUREMENT "$LANG_FORMATS"
    setkv /etc/locale.conf LC_MONETARY "$LANG_FORMATS"
    setkv /etc/locale.conf LC_NUMERIC "en_US.UTF-8"

    put 644 /etc/vconsole.conf <<EOF
KEYMAP=$CONSOLE_KEYMAP
FONT=$CONSOLE_FONT
EOF

    cmdline_set quiet
    cmdline_set splash
    cmdline_set loglevel 3
    cmdline_set zswap.enabled 0
    cmdline_set apparmor 1
    cmdline_set security apparmor
    cmdline_set pcie_aspm force
    cmdline_set i915.enable_psr 1
    cmdline_set i915.enable_fbc 1
    cmdline_set nvme.noacpi 1
    cmdline_set workqueue.power_efficient 1

    ensure_swap
    setkv /etc/default/grub GRUB_DISABLE_OS_PROBER false
}

step_packages() {
    log "package installation via zypper"
    if ! zypper lr packman >/dev/null 2>&1; then
        log "adding Packman repository for full multimedia codecs"
        zypper ar -cfp 90 "$REPO_PACKMAN" packman
    fi
    if ! zypper lr mwt-packages >/dev/null 2>&1; then
        log "adding GitHub Desktop repository (mwt-packages)"
        rpm --import https://mirror.mwt.me/shiftkey-desktop/gpgkey 2>/dev/null || true
        put 644 /etc/zypp/repos.d/mwt-packages.repo <<'REPO_EOF'
[mwt-packages]
name=GitHub Desktop
baseurl=https://mirror.mwt.me/shiftkey-desktop/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirror.mwt.me/shiftkey-desktop/gpgkey
REPO_EOF
    fi
    zypper --gpg-auto-import-keys refresh

    # Remove conflicting power-profiles-daemon if present so TLP installs without prompts
    if rpm -q power-profiles-daemon >/dev/null 2>&1; then
        log "removing power-profiles-daemon (conflicts with TLP)"
        zypper --non-interactive rm -y power-profiles-daemon 2>/dev/null || true
    fi

    # Kick out unwanted vendor, bloat, or obsolete packages
    local bloat=(hplip hplip-hp-plugin hplip-sane kweather p7zip udiskie blueman NetworkManager-applet file-roller niri xwayland-satellite greetd tuigreet icewm icewm-default icewm-config-upstream icewm-lang mako cliphist waybar sfwbar fuzzel)
    local to_rm=() p
    for p in "${bloat[@]}"; do
        rpm -q "$p" >/dev/null 2>&1 && to_rm+=("$p")
    done
    if [[ ${#to_rm[@]} -gt 0 ]]; then
        log "purging unwanted packages: ${to_rm[*]}..."
        zypper --non-interactive rm -u -y "${to_rm[@]}" 2>/dev/null || true
    fi

    # Unconditionally remove bloat autostart entries and the Floorp browser
    rm -f /etc/xdg/autostart/hp-systray.desktop \
          /etc/xdg/autostart/nm-applet.desktop \
          /etc/xdg/autostart/blueman.desktop \
          /usr/share/applications/hp-toolbox.desktop \
          /usr/share/applications/hp-*.desktop \
          /usr/share/applications/*kweather*.desktop \
          /usr/share/applications/floorp.desktop \
          /usr/local/share/applications/floorp.desktop \
          /home/*/.local/share/applications/floorp.desktop \
          /usr/local/bin/floorp 2>/dev/null || true
    rm -rf /opt/floorp /home/*/.config/floorp /home/*/.cache/floorp /home/*/.mozilla/floorp 2>/dev/null || true
    pkill -f hp-systray 2>/dev/null || true
    pkill -f hp-toolbox 2>/dev/null || true
    pkill -f nm-applet 2>/dev/null || true
    pkill -f blueman-applet 2>/dev/null || true
    pkill -f blueman-tray 2>/dev/null || true
    pkill -f udiskie 2>/dev/null || true
    pkill -f floorp 2>/dev/null || true
    pkill -f "cliphist store" 2>/dev/null || true
    killall mako 2>/dev/null || true
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /usr/share/applications 2>/dev/null || true
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 2>/dev/null || true

    local pkgs
    mapfile -t pkgs < <(sed 's/#.*//' "$HERE/packages.txt" | grep -o '[^[:space:]]\+')
    log "installing ${#pkgs[@]} packages..."
    zypper --non-interactive --ignore-unknown in -y --no-recommends --auto-agree-with-licenses --force-resolution "${pkgs[@]}" || warn "some packages could not be installed"
    zypper dup -y --from packman --allow-vendor-change || true
}

step_user() {
    log "user account, groups, sudo timeout, privileges"
    if ! id "$USERNAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -c "$FULLNAME" "$USERNAME"
    fi
    # scripted install: the new account has no password yet, so SDDM could never log in
    if [[ -t 0 ]] && passwd -S "$USERNAME" 2>/dev/null | awk '{exit !($2 == "L" || $2 == "NP")}'; then
        log "set the login password for $USERNAME"
        passwd "$USERNAME"
    fi
    local g
    for g in wheel audio video input disk storage network libvirt kvm; do
        getent group "$g" >/dev/null && usermod -aG "$g" "$USERNAME" || true
    done

    mkdir -p /etc/sudoers.d
    chmod 750 /etc/sudoers.d

    # Guarantee sudo always uses the user's password, never rootpw or targetpw
    put 440 /etc/sudoers.d/10-mysuse <<EOF
Defaults timestamp_timeout=$SUDO_TIMEOUT_MIN, timestamp_type=global
Defaults !targetpw
Defaults:ALL !targetpw
Defaults !rootpw
Defaults:ALL !rootpw
%wheel ALL=(ALL:ALL) ALL
$USERNAME ALL=(ALL:ALL) ALL
EOF

    # MMAutoKey: uinput permissions for group input
    put 644 /etc/udev/rules.d/80-mmautokey-uinput.rules <<'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
EOF
    put 644 /etc/modules-load.d/mmautokey-uinput.conf <<'EOF'
uinput
EOF
    modprobe uinput 2>/dev/null || true
    udevadm control --reload-rules 2>/dev/null || true
    chgrp input /dev/uinput 2>/dev/null && chmod 0660 /dev/uinput 2>/dev/null || true
}

step_security() {
    log "security hardening: sysctl, apparmor, firewall, fingerprint"

    # Enable fingerprint authentication system-wide (sudo, login, polkit, SDDM, lockscreen)
    local pam_cfg; pam_cfg=$(command -v pam-config || echo "/usr/sbin/pam-config")
    if [[ -x $pam_cfg ]]; then
        log "enabling fingerprint authentication via pam-config..."
        "$pam_cfg" -a --fprintd 2>/dev/null || true
    fi

    put 644 /etc/sysctl.d/99-mysuse-hardening.conf < "$FILES/sysctl-hardening.conf"
    sysctl --system >/dev/null 2>&1 || true

    systemctl enable --now apparmor 2>/dev/null || true

    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        log "configuring firewalld"
        firewall-cmd --permanent --add-service=mdns >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="$RESILIO_PORT/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=3838/udp >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=41641/udp >/dev/null 2>&1 || true
        firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=1714-1764/tcp >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=1714-1764/udp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    elif [[ -f $FILES/nftables.conf ]]; then
        tpl "$FILES/nftables.conf" | put 644 /etc/nftables.conf
        systemctl enable --now nftables 2>/dev/null || true
    fi

    # disable aggressive background polling services on laptops
    local s
    for s in smartd cups-browsed ipp-usb; do
        systemctl disable --now "$s" 2>/dev/null || true
    done

    # printer defaults (Brother DCP-L2530DW series: 600 dpi, simplex, 1 copy, collate)
    if command -v lpadmin >/dev/null 2>&1; then
        lpadmin -p "Brother_DCP-L2530DW_series" -E -v "ipp://Brother%20DCP-L2530DW%20series._ipp._tcp.local/" -m everywhere 2>/dev/null || true
        lpadmin -d "Brother_DCP-L2530DW_series" 2>/dev/null || true
        lpadmin -p "Brother_DCP-L2530DW_series" -o Duplex=None -o sides=one-sided -o cupsPrintQuality=Normal -o Collate=True 2>/dev/null || true
        as_user lpoptions -d "Brother_DCP-L2530DW_series" -o Duplex=None -o sides=one-sided -o cupsPrintQuality=Normal -o Collate=True -o copies=1 2>/dev/null || true
    fi
}

step_snapper() {
    log "snapper snapshot configuration (root only; home and timeline disabled)"
    [[ -f /etc/snapper/configs/root ]] || snapper create-config / 2>/dev/null || true

    # Configure root: only zypper package pre/post pairs are kept; periodic timeline disabled
    if [[ -f /etc/snapper/configs/root ]]; then
        sed -i 's|^TIMELINE_CREATE=.*|TIMELINE_CREATE="no"|' /etc/snapper/configs/root
        sed -i 's|^TIMELINE_CLEANUP=.*|TIMELINE_CLEANUP="yes"|' /etc/snapper/configs/root
        sed -i 's|^NUMBER_CLEANUP=.*|NUMBER_CLEANUP="yes"|' /etc/snapper/configs/root
        sed -i 's|^NUMBER_MIN_AGE=.*|NUMBER_MIN_AGE="1800"|' /etc/snapper/configs/root
        sed -i "s|^NUMBER_LIMIT=.*|NUMBER_LIMIT=\"${SNAP_ROOT_LIMIT:-10}\"|" /etc/snapper/configs/root
        sed -i "s|^NUMBER_LIMIT_IMPORTANT=.*|NUMBER_LIMIT_IMPORTANT=\"${SNAP_ROOT_LIMIT_IMPORTANT:-4}\"|" /etc/snapper/configs/root
        local limit
        for limit in HOURLY DAILY WEEKLY MONTHLY YEARLY; do
            sed -i "s|^TIMELINE_LIMIT_${limit}=.*|TIMELINE_LIMIT_${limit}=\"0\"|" /etc/snapper/configs/root
        done
    fi

    # Decommission legacy home snapper config and snapshot subvolumes if present
    if [[ -f /etc/snapper/configs/home ]] || snapper list-configs 2>/dev/null | grep -qw home; then
        log "decommissioning legacy home snapper configuration and snapshots..."
        snapper -c home delete-config 2>/dev/null || rm -f /etc/snapper/configs/home 2>/dev/null || true
        if mountpoint -q /home/.snapshots 2>/dev/null; then
            umount /home/.snapshots 2>/dev/null || true
        fi
        btrfs subvolume delete /home/.snapshots 2>/dev/null || rm -rf /home/.snapshots 2>/dev/null || true
    fi

    # Stop timeline timer, ensure cleanup timer is active for pruning old package snapshots
    systemctl disable --now snapper-timeline.timer 2>/dev/null || true
    systemctl enable --now snapper-cleanup.timer 2>/dev/null || true
}

step_desktop() {
    log "desktop environment: TLP, thermald, PipeWire, helper scripts, dotfiles"
    systemctl enable --now tlp tlp-pd thermald 2>/dev/null || true
    systemctl enable --now earlyoom 2>/dev/null || true
    systemctl enable --now udisks2 2>/dev/null || true
    systemctl enable --now bluetooth 2>/dev/null || true
    systemctl enable --now cronie 2>/dev/null || true

    put 644 /etc/tlp.d/10-x1.conf < "$FILES/tlp.conf"

    # install helper tools
    mkdir -p /var/lib/mysuse /usr/local/bin /usr/local/lib/mysuse
    put 755 /usr/local/bin/battery-guard < "$FILES/battery-guard"
    put 755 /usr/local/bin/power-ok < "$FILES/power-ok"
    put 755 /usr/local/bin/update-notify < "$FILES/update-notify"
    put 755 /usr/local/bin/snapper-tick < "$FILES/snapper-tick"
    put 755 /usr/local/bin/cloud < "$FILES/cloud"
    put 755 /usr/local/bin/resilio < "$FILES/resilio"
    put 755 /usr/local/bin/pcloud-install < "$FILES/pcloud-install"
    put 755 /usr/local/bin/set-swap < "$FILES/set-swap"
    put 755 /usr/local/bin/labwc-suse-session < "$FILES/labwc-suse-session"
    put 755 /usr/local/bin/helium-install-extensions < "$FILES/helium-install-extensions"
    put 755 /usr/local/bin/taskbar-app < "$FILES/home/.local/bin/taskbar-app"
    put 755 /usr/local/bin/foot-open < "$FILES/home/.local/bin/foot-open"
    put 755 /usr/local/bin/idle-manager < "$FILES/home/.local/bin/idle-manager"
    put 755 /usr/local/bin/imv-dir < "$FILES/home/.local/bin/imv-dir"
    put 755 /usr/local/bin/imv-info < "$FILES/home/.local/bin/imv-info"

    # NetworkManager auto-save Wi-Fi passwords system-wide
    put 755 /etc/NetworkManager/dispatcher.d/99-save-wifi-psk.sh < "$FILES/nm-save-wifi-psk.sh"

    # root-owned copy for cron (root never runs the user-writable ~/mySuse); no .git, so it never pulls
    if [[ $HERE != /usr/local/lib/mysuse ]]; then
        rm -rf /usr/local/lib/mysuse.new
        cp -r "$HERE" /usr/local/lib/mysuse.new
        rm -rf /usr/local/lib/mysuse.new/.git
        chown -R root:root /usr/local/lib/mysuse.new
        rm -rf /usr/local/lib/mysuse
        mv /usr/local/lib/mysuse.new /usr/local/lib/mysuse
    fi

    put 644 /etc/cron.d/mysuse <<'EOF'
PATH=/usr/local/bin:/usr/bin:/usr/sbin:/bin
# package index refresh so update-notify can count updates
17 */6 * * * root zypper refresh >/dev/null 2>&1
# Helium, Resilio, fonts, cursor: daily upkeep
47 * * * * root power-ok 80 && ! find /var/lib/mysuse/apps.stamp -mmin -1440 2>/dev/null | grep -q . && bash /usr/local/lib/mysuse/refresh.sh apps >/dev/null 2>&1 && touch /var/lib/mysuse/apps.stamp
# monthly btrfs scrub
0 11 1 * * root btrfs scrub start -Bd / >/dev/null 2>&1 || logger -t mysuse "btrfs scrub reported errors"
# plocate index
30 12 * * * root updatedb
# hibernate at 5 % battery
*/2 * * * * root battery-guard
EOF

    # User services (PipeWire audio, Kanshi display hotplug, mask duplicate mako)
    systemctl --user --global enable pipewire wireplumber pipewire-pulse kanshi.service 2>/dev/null || true
    systemctl --user --global mask mako.service 2>/dev/null || true
    as_user systemctl --user enable --now kanshi.service 2>/dev/null || true
    as_user systemctl --user mask mako.service 2>/dev/null || true

    step_dotfiles
}

step_dotfiles() {
    log "deploying dotfiles to $UHOME"
    local src dst stamp
    stamp=$(date '+%F %H-%M-%S')
    while IFS= read -r -d '' src; do
        dst=$UHOME/${src#"$FILES/home/"}
        if [[ -f $dst ]] && cmp -s <(tpl "$src") "$dst"; then continue; fi
        if [[ -f $dst ]]; then
            as_user mkdir -p "$UHOME/.backup"
            as_user cp -a "$dst" "$UHOME/.backup/$(basename "$dst") $stamp"
        fi
        as_user mkdir -p "$(dirname "$dst")"
        tpl "$src" | as_user tee "$dst" >/dev/null
    done < <(find "$FILES/home" -type f -print0)
    as_user chmod +x "$UHOME/.local/bin/"* 2>/dev/null || true
    chmod 755 "$UHOME/.config/labwc/autostart" 2>/dev/null || true
    as_user mkdir -p "$UHOME/Github/mydata/t/_screenshots"

    # Wallpapers
    as_user mkdir -p "$UHOME/Pictures/Wallpapers"
    local wp=$UHOME/Pictures/Wallpapers/great-wave.jpg
    if [[ ! -s $wp ]] && ! as_user curl -fsSL --max-time 120 -o "$wp" \
        https://upload.wikimedia.org/wikipedia/commons/a/a5/Tsunami_by_hokusai_19th_century.jpg; then
        rm -f "$wp"
        warn "wallpaper download failed; put any image into ~/Pictures/Wallpapers"
    fi

    if command -v typst >/dev/null 2>&1; then
        (cd "$FILES/wallpaper" && typst compile keys-labwc.typ "$UHOME/Pictures/Wallpapers/keys-labwc.png" 2>/dev/null) || true
        chown "$USERNAME:$USERNAME" "$UHOME/Pictures/Wallpapers"/keys-*.png 2>/dev/null || true
    fi

    if [[ $HERE != "$UHOME/mySuse" && ! -d "$UHOME/mySuse" ]]; then
        cp -r "$HERE" "$UHOME/mySuse"
        chown -R "$USERNAME:$USERNAME" "$UHOME/mySuse" 2>/dev/null || true
    fi

    # Clean up obsolete plasma and niri configs
    rm -rf "$UHOME/.config/plasma"* \
           "$UHOME/.config/kwinrc" \
           "$UHOME/.config/plasmarc" \
           "$UHOME/.local/share/plasma" \
           "$UHOME/.local/share/applications/plasma-keys.desktop" \
           "$UHOME/Pictures/Wallpapers/keys-plasma.png" \
           "$UHOME/.local/state/plasma" \
           "$UHOME/.local/state/mysuse/plasma-"* \
           "$UHOME/.local/share/mysuse/activate-btop.js" \
           "$UHOME/.config/niri" \
           "$UHOME/.config/qt5ct" "$UHOME/.config/qt6ct" \
           "$UHOME/Pictures/Wallpapers/keys-niri.png" 2>/dev/null || true
    rm -f /usr/local/bin/plasma-* 2>/dev/null || true
    rm -rf /usr/share/plasma/look-and-feel/org.mysuse.desktop 2>/dev/null || true

    # MMAutoKey: install if mydata repo has been downloaded
    local d
    for d in "$UHOME/Github/mydata/code/MMAutoKey_linux" "$UHOME/GitHub/mydata/code/MMAutoKey_linux"; do
        if [[ -f "$d/install.sh" ]]; then
            log "installing MMAutoKey from $d"
            chmod +x "$d/MMAutoKey_linux" "$d/build/build.sh" "$d/install.sh" 2>/dev/null || true
            as_user bash "$d/install.sh" || warn "MMAutoKey install failed"
            break
        fi
    done

    # Re-apply the running session: labwc --reconfigure is a SIGHUP to labwc
    if ! in_chroot; then
        pkill -HUP -x labwc 2>/dev/null || true
        as_user noctalia msg config-reload 2>/dev/null || true
    fi
}

gh_asset() {
    local repo=$1 re=$2 json url
    json=$(curl -fsSL --max-time 30 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null) || {
        warn "GitHub API request failed for $repo"
        return 1
    }
    url=$(echo "$json" | jq -r --arg re "$re" '[.assets[]? | select(.name | test($re))][0].browser_download_url // empty' 2>/dev/null)
    if [[ -z $url ]]; then
        warn "no asset matching '$re' found for $repo"
        return 1
    fi
    echo "$url"
}

opt_install() {
    local dest=$1 url=$2 strip=$3 ver=$4 tmp
    [[ -n $url ]] || { warn "no download URL for $dest"; return 1; }
    if [[ $(cat "$dest/.version" 2>/dev/null) == "$ver" ]]; then log "$dest is current"; return 0; fi
    if pgrep -f "^$dest/" >/dev/null; then warn "$dest is in use - update postponed"; return 0; fi
    log "installing $dest from $url"
    mkdir -p "$(dirname "$dest")"
    tmp=$(mktemp -d "$(dirname "$dest")/.install.XXXXXX")
    if ! curl -fL --retry 3 --max-time 900 -o "$tmp/pkg" "$url"; then
        rm -rf "$tmp"
        warn "download failed for $dest"
        return 1
    fi
    mkdir "$tmp/root"
    if ! tar -xf "$tmp/pkg" -C "$tmp/root" --strip-components="$strip" --no-same-owner; then
        rm -rf "$tmp"
        warn "extraction failed for $dest"
        return 1
    fi
    echo "$ver" > "$tmp/root/.version"
    rm -rf "$dest.old"
    [[ -d $dest ]] && mv "$dest" "$dest.old"
    mv "$tmp/root" "$dest"
    rm -rf "$dest.old" "$tmp"
}

desktop_entry() {
    local f
    for f in "/usr/local/share/applications/$1.desktop" "/usr/share/applications/$1.desktop"; do
        put 644 "$f" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$4
Categories=$5
${6:+MimeType=$6}
Terminal=false
EOF
    done
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /usr/share/applications /usr/local/share/applications 2>/dev/null || true
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 2>/dev/null || true
}

font_zip() {
    local url dest=/usr/local/share/fonts/$1 tmp
    url=$(gh_asset "$2" '\.zip$') || true
    [[ -n $url ]] || { warn "no font zip URL for $2"; return 0; }
    if [[ $(cat "$dest/.version" 2>/dev/null) == "$url" ]]; then return 0; fi
    log "font: $1 from $url"
    tmp=$(mktemp -d /tmp/font.XXXXXX)
    if curl -fsSL --max-time 180 -o "$tmp/font.zip" "$url"; then
        mkdir -p "$dest"
        unzip -q -o "$tmp/font.zip" -d "$tmp/unpacked"
        find "$tmp/unpacked" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec cp -f {} "$dest/" \;
        echo "$url" > "$dest/.version"
        fc-cache -f "$dest" 2>/dev/null || true
    else
        warn "failed to download font zip for $1"
    fi
    rm -rf "$tmp"
}

step_apps() {
    log "upstream applications: Helium, Resilio, ytfzf, fonts"
    local h_url
    h_url=$(gh_asset "imputnet/helium-linux" '.*-x86_64_linux\.tar\.xz$') || true
    if [[ -n $h_url ]]; then
        opt_install /opt/helium "$h_url" 1 "$h_url"
        put 755 /usr/local/bin/helium <<'EOF'
#!/bin/bash
# Launch Helium with hardware acceleration, secret store, and unpacked extensions
EXT_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/helium/extensions/unpacked"
LOAD_EXTS=()

if [[ -d "$EXT_BASE" ]]; then
    for ext_dir in "$EXT_BASE"/*; do
        if [[ -d "$ext_dir" && -f "$ext_dir/manifest.json" ]]; then
            LOAD_EXTS+=("$ext_dir")
        fi
    done
fi

if [[ -d "$HOME/Github/mydata/code/MMBrowserSync/extension" ]]; then
    LOAD_EXTS+=("$HOME/Github/mydata/code/MMBrowserSync/extension")
fi

EXT_FLAG=""
if [[ ${#LOAD_EXTS[@]} -gt 0 ]]; then
    EXT_FLAG="--load-extension=$(IFS=,; echo "${LOAD_EXTS[*]}")"
fi

exec /opt/helium/helium --password-store=gnome-libsecret --enable-features=VaapiVideoDecodeLinuxGL $EXT_FLAG "$@"
EOF
        desktop_entry helium "Helium" /usr/local/bin/helium /opt/helium/product_logo_128.png \
            "Network;WebBrowser;" "text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;"

        # Helium default search provider (Google) and system default browser
        mkdir -p /etc/chromium/policies/managed /etc/opt/chrome/policies/managed
        put 644 /etc/chromium/policies/managed/default_search.json <<'SRCH_EOF'
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderKeyword": "google.com",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}",
  "DefaultSearchProviderSuggestURL": "https://www.google.com/complete/search?output=chrome&q={searchTerms}",
  "DefaultSearchProviderIconURL": "https://www.google.com/favicon.ico",
  "DefaultSearchProviderNewTabURL": "https://www.google.com",
  "HomepageLocation": "https://www.google.com",
  "HomepageIsNewTabPage": false,
  "NewTabPageLocation": "https://www.google.com"
}
SRCH_EOF
        cp /etc/chromium/policies/managed/default_search.json /etc/opt/chrome/policies/managed/default_search.json 2>/dev/null || true
        as_user xdg-settings set default-web-browser helium.desktop 2>/dev/null || true

        # Helium extension policies (Bitwarden, Consent-O-Matic, Ghostery, Raindrop, uBlock, Unhook, Video Downloader, Volume Scroll)
        put 644 /etc/chromium/policies/managed/extensions.json <<'EXT_EOF'
{
  "ExtensionInstallForcelist": [
    "nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx",
    "mdjildafknihdffpkfmmpnpoiajfjnjd;https://clients2.google.com/service/update2/crx",
    "mlomiejdfkolichcflejclcbmpeaniij;https://clients2.google.com/service/update2/crx",
    "ldgfbffkinooeloadekpmfoklnobpien;https://clients2.google.com/service/update2/crx",
    "cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx",
    "blockjmkbacgjkknlgpkjjiijinjdanf;https://clients2.google.com/service/update2/crx",
    "khncfooichmfjbepaaaebmommgaepoid;https://clients2.google.com/service/update2/crx",
    "penndbmahnpapepljikkjmakcobdahne;https://clients2.google.com/service/update2/crx",
    "agadcopafaojndinhloilcanpfpbonbk;https://clients2.google.com/service/update2/crx"
  ]
}
EXT_EOF
        cp /etc/chromium/policies/managed/extensions.json /etc/opt/chrome/policies/managed/extensions.json 2>/dev/null || true

        if [[ -f $FILES/helium-install-extensions ]]; then
            log "installing Helium browser extensions..."
            as_user python3 "$FILES/helium-install-extensions" 2>/dev/null || true
        fi
    else
        warn "Helium installation skipped (could not fetch release asset)"
    fi

    # ytfzf (YouTube CLI search and player)
    if [[ ! -x /usr/local/bin/ytfzf ]]; then
        log "installing ytfzf"
        local ytmp
        ytmp=$(mktemp -d /tmp/ytfzf.XXXXXX)
        if curl -fsSL https://github.com/pystardust/ytfzf/archive/refs/tags/v2.6.2.tar.gz -o "$ytmp/ytfzf.tar.gz"; then
            tar -xzf "$ytmp/ytfzf.tar.gz" -C "$ytmp"
            (cd "$ytmp/ytfzf-2.6.2" && make install doc addons)
            log "ytfzf installed successfully"
        else
            warn "ytfzf download failed"
        fi
        rm -rf "$ytmp"
    fi

    # Resilio Sync
    if [[ ! -x /usr/local/bin/rslsync ]]; then
        local rtmp
        rtmp=$(mktemp -d /tmp/resilio.XXXXXX)
        if curl -fsSL --max-time 300 -o "$rtmp/sync.tar.gz" "https://download-cdn.resilio.com/stable/linux/x64/0/resilio-sync_x64.tar.gz"; then
            tar -xf "$rtmp/sync.tar.gz" -C "$rtmp" rslsync
            put 755 /usr/local/bin/rslsync < "$rtmp/rslsync"
        else
            warn "Resilio download failed"
        fi
        rm -rf "$rtmp"
    fi

    # Bibata cursor
    local bibata_url
    bibata_url=$(gh_asset "ful1e5/Bibata_Cursor" 'Bibata-Modern-Classic\.tar\.xz$') || true
    if [[ -n $bibata_url ]] && [[ ! -d /usr/local/share/icons/Bibata-Modern-Classic ]]; then
        mkdir -p /usr/local/share/icons
        curl -fsSL "$bibata_url" | tar -xJ -C /usr/local/share/icons/ 2>/dev/null || warn "Bibata cursor installation failed"
    fi

    font_zip "jetbrains-mono" "JetBrains/JetBrainsMono"
    font_zip "cascadia-code" "microsoft/cascadia-code"

    # Mission Center (Windows 11-style Task Manager via Flathub)
    if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
        flatpak install -y --noninteractive flathub io.missioncenter.MissionCenter 2>/dev/null || true
    fi

    # Noctalia modern desktop shell (if not already installed via zypper)
    if ! command -v noctalia >/dev/null 2>&1; then
        log "building and installing Noctalia from source..."
        local nsrc=/var/cache/noctalia
        mkdir -p "$nsrc"
        if [[ -d $nsrc/.git ]]; then
            git -C "$nsrc" pull -q --ff-only 2>/dev/null || true
        else
            git clone -q --depth 1 https://github.com/noctalia-dev/noctalia.git "$nsrc" 2>/dev/null || warn "Noctalia clone failed"
        fi
        if [[ -f $nsrc/meson.build ]]; then
            (
                cd "$nsrc"
                rm -rf build
                meson setup build -Dprefix=/usr/local --buildtype=release >/dev/null 2>&1
                ninja -C build -j "$(nproc)" >/dev/null 2>&1
                ninja -C build install >/dev/null 2>&1
            ) && {
                mkdir -p /usr/local/share/noctalia
                date +%F > /usr/local/share/noctalia/.version
                log "Noctalia installed to /usr/local/bin/noctalia"
            } || warn "Noctalia compilation failed; check build dependencies"
        fi
    fi
}

step_login() {
    log "login screen: SDDM with Chili theme (single Labwc session)"
    put 644 /usr/share/wayland-sessions/labwc.desktop <<EOF
[Desktop Entry]
Name=Labwc
Comment=Modern Stacking Wayland Compositor with Noctalia Shell
Exec=/usr/local/bin/labwc-suse-session
Icon=labwc
Type=Application
DesktopNames=labwc;wlroots
EOF

    # Clean up duplicate / obsolete session entries so Labwc is the ONLY entry on the login screen
    rm -f /usr/share/wayland-sessions/labwc-suse.desktop \
          /usr/share/wayland-sessions/plasma*.desktop 2>/dev/null || true
    rm -rf /usr/share/xsessions/* 2>/dev/null || true

    # Install Chili SDDM theme
    if [[ -d "$FILES/sddm-theme-chili" ]]; then
        mkdir -p /usr/share/sddm/themes/chili
        cp -a "$FILES/sddm-theme-chili/." /usr/share/sddm/themes/chili/
    fi

    # Configure SDDM to use Chili theme and pre-select Labwc
    put 644 /etc/sddm.conf.d/10-mysuse.conf <<EOF
[Theme]
Current=chili
CursorTheme=Bibata-Modern-Classic

[Users]
RememberLastSession=true
RememberLastUser=true
EOF

    put 644 /var/lib/sddm/state.conf <<EOF
[Last]
Session=/usr/share/wayland-sessions/${DEFAULT_SESSION:-labwc}.desktop
User=$USERNAME
EOF

    # Clean up obsolete greetd session if previously enabled
    systemctl disable greetd 2>/dev/null || true
    rm -f /etc/greetd/config.toml 2>/dev/null || true

    # Enable SDDM display manager and require password on login
    systemctl enable sddm 2>/dev/null || true
    if command -v update-alternatives >/dev/null 2>&1; then
        update-alternatives --set default-displaymanager /usr/lib/X11/displaymanagers/sddm 2>/dev/null || true
    fi

    # Require password authentication on login (disable autologin)
    if [ -f /etc/sysconfig/displaymanager ]; then
        sed -i 's/^DISPLAYMANAGER_AUTOLOGIN=.*/DISPLAYMANAGER_AUTOLOGIN=""/' /etc/sysconfig/displaymanager
        sed -i 's/^DISPLAYMANAGER_PASSWORD_LESS_LOGIN=.*/DISPLAYMANAGER_PASSWORD_LESS_LOGIN="no"/' /etc/sysconfig/displaymanager
    fi
    put 644 /etc/sddm.conf.d/autologin.conf <<'EOF'
[Autologin]
User=
Session=
Relogin=false
EOF
}

step_devtools() {
    log "developer tools: rustup, Claude Code, Antigravity CLI, Deno, oh-my-pi, nanobot, Git Credential Manager"
    if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
        zypper --ignore-unknown in -y --no-recommends gcc gcc-c++ 2>/dev/null || true
    fi
    as_user mkdir -p "$UHOME/.local/bin"
    if [[ ! -x $UHOME/.cargo/bin/rustc ]]; then
        as_user bash -o pipefail -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path' || warn "rustup failed"
    fi
    if [[ ! -x $UHOME/.local/bin/claude ]]; then
        as_user bash -o pipefail -c 'curl -fsSL https://claude.ai/install.sh | bash' || warn "Claude install failed"
    fi
    if [[ ! -x $UHOME/.local/bin/agy ]]; then
        as_user bash -o pipefail -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash' || warn "agy install failed"
    fi
    if [[ ! -x $UHOME/.deno/bin/deno ]]; then
        as_user bash -o pipefail -c 'curl -fsSL https://deno.land/install.sh | sh -s -- -y' || warn "Deno install failed"
    fi
    if [[ ! -x $UHOME/.local/bin/omp ]]; then
        as_user bash -o pipefail -c 'curl -fsSL https://omp.sh/install | sh -s -- --binary' || warn "omp install failed"
    fi
    if [[ ! -x $UHOME/.local/bin/nanobot ]]; then
        as_user bash -o pipefail -c 'NANOBOT_SKIP_WIZARD=1 curl -fsSL https://raw.githubusercontent.com/HKUDS/nanobot/main/scripts/install.sh | sh' || warn "nanobot install failed"
    fi

    # Git Credential Manager (GCM)
    local gcm_url
    gcm_url=$(gh_asset "git-ecosystem/git-credential-manager" 'gcm-linux-x64-[0-9.]+\.tar\.gz$') || true
    if [[ -n $gcm_url ]]; then
        opt_install /opt/git-credential-manager "$gcm_url" 0 "$gcm_url"
        chmod +x /opt/git-credential-manager/git-credential-manager 2>/dev/null || true
        ln -sf /opt/git-credential-manager/git-credential-manager /usr/local/bin/git-credential-manager
    fi

    # Git configuration matching Windows workflow: longpaths, GCM credential helper, Secret Service
    if command -v git >/dev/null 2>&1; then
        as_user git config --global core.longpaths true
        as_user git config --global --unset-all credential.helper 2>/dev/null || true
        as_user git config --global credential.helper ""
        as_user git config --global --add credential.helper manager
        as_user git config --global credential.credentialStore secretservice
    fi
}

step_speakers() {
    log "Lenovo X1 Carbon Gen 10 speaker tuning"
    if in_chroot; then log "speakers: tuned by the first refresh.sh run after boot"; return 0; fi
    local win=/run/mysuse-windows part found="" src=/var/cache/speaker-tuning
    local bundled_xml=$FILES/audio/DEV_0287_SUBSYS_17AA22E7_PCI_SUBSYS_22E717AA.xml

    install -d -o "$USERNAME" -g "$USERNAME" "$src"
    if [[ -d $src/.git ]]; then as_user git -C "$src" pull -q --ff-only || true
    else as_user git clone -q --depth 1 https://github.com/antoinecellerier/speaker-tuning-to-easyeffects "$src"; fi

    if [[ -f $bundled_xml ]]; then
        as_user python3 "$src/dolby_to_easyeffects.py" "$bundled_xml" --all-profiles --enable autogain --autoload || warn "speakers: conversion failed"
        return 0
    fi

    mkdir -p "$win"
    while read -r part; do
        mountpoint -q "$win" || mount -t ntfs-3g -o ro "$part" "$win" 2>/dev/null ||
            mount -t ntfs3 -o ro "$part" "$win" 2>/dev/null || continue
        if [[ -d $win/Windows/System32/DriverStore ]]; then found=$part; break; fi
        umount "$win" 2>/dev/null || true
    done < <(lsblk -lnpo NAME,FSTYPE | awk '$2 == "ntfs" {print $1}')
    if [[ -z $found ]]; then warn "speakers: no Windows partition with Lenovo audio driver found"; return 0; fi

    as_user python3 "$src/dolby_to_easyeffects.py" --windows "$win" --all-profiles --enable autogain --autoload || warn "speakers: conversion failed"
    umount "$win" 2>/dev/null || true
}

step_vm() {
    log "virtualization: KVM, libvirt, swtpm, Windows 11 VM prep"
    systemctl enable --now libvirtd 2>/dev/null || systemctl enable --now libvirtd.socket 2>/dev/null || true

    if command -v virsh >/dev/null 2>&1; then
        virsh net-autostart default 2>/dev/null || true
        virsh net-start default 2>/dev/null || true
    fi

    mkdir -p /var/lib/libvirt/images "$UHOME/VMs"
    chattr +C /var/lib/libvirt/images 2>/dev/null || true
    chattr +C "$UHOME/VMs" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$UHOME/VMs" 2>/dev/null || true

    put 755 /usr/local/bin/win11-vm < "$FILES/win11-vm"
    desktop_entry win11-vm "Windows 11 VM" "/usr/local/bin/win11-vm start" \
        "qemu" "System;Emulator;"
}

step_finish() {
    # only regenerate when boot inputs changed: dracut is the slowest part of a routine refresh
    local stamp=/var/lib/mysuse/boot.sha sum
    sum=$({ cat /etc/default/grub /etc/sysconfig/bootloader /etc/crypttab /etc/vconsole.conf \
        /etc/dracut.conf.d/* 2>/dev/null || true; } | sha256sum)
    if [[ -f /boot/grub2/grub.cfg && $(cat "$stamp" 2>/dev/null) == "$sum" ]]; then
        log "boot configuration unchanged - initramfs and grub.cfg left as they are"
        return 0
    fi
    log "regenerating dracut initramfs and bootloader configuration"
    dracut --force --hostonly 2>/dev/null || true
    update-bootloader --refresh 2>/dev/null || grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    mkdir -p /var/lib/mysuse
    echo "$sum" > "$stamp"
}

ensure_tools() {
    if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
        log "installing core setup utilities (jq, curl, tar, xz, unzip)..."
        zypper --ignore-unknown in -y --no-recommends jq curl ca-certificates-mozilla tar xz unzip 2>/dev/null || true
    fi
}

repo_hash() {
    (cd "$HERE" && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}

# Named steps run as asked. No steps: all of them, resuming an interrupted run of the same repo content.
run_steps() {
    local s state=/var/lib/mysuse/progress hash
    if [[ $# -gt 0 ]]; then
        for s; do declare -F "step_$s" >/dev/null || die "unknown step '$s' (steps: ${ALL_STEPS[*]} dotfiles)"; done
        for s; do "step_$s"; done
        return 0
    fi
    mkdir -p /var/lib/mysuse
    hash=$(repo_hash)
    [[ $(head -n1 "$state" 2>/dev/null) == "$hash" ]] || echo "$hash" > "$state"
    for s in "${ALL_STEPS[@]}"; do
        if grep -qx "$s" "$state"; then log "$s: finished in the interrupted run - skipped"; continue; fi
        "step_$s"
        echo "$s" >> "$state"
    done
    rm -f "$state"
}

# ---------------------------------------------------------------- main

[[ $EUID -eq 0 ]] || exec sudo bash "$SELF" "$@"

# pull as the repo owner (git refuses a repo owned by someone else), then restart with the new script
if [[ -z ${MYSUSE_PULLED:-} && -d $HERE/.git ]] && ! in_chroot; then
    owner=$(stat -c %U "$HERE")
    log "pulling repository changes"
    runuser -u "$owner" -- env HOME="$(getent passwd "$owner" | cut -d: -f6)" git -C "$HERE" pull -q --ff-only ||
        warn "git pull failed - continuing with the local copy"
    export MYSUSE_PULLED=1
    exec bash "$SELF" "$@"
fi

if ! in_chroot && is_live; then MODE=live; LOGDIR=/tmp; else MODE=system; LOGDIR=/var/log/mysuse; fi
mkdir -p "$LOGDIR"
LOG=$LOGDIR/$(date +%F_%H-%M-%S)-refresh.log
exec > >(tee -a "$LOG") 2>&1
TEE_PID=$!
trap 'exec >&- 2>&-; wait "$TEE_PID"' EXIT

if [[ $MODE == live ]]; then
    live_install "$@"
else
    ensure_tools
    run_steps "$@"
fi
log "refresh finished${1:+: $*}  (log: $LOG)"
