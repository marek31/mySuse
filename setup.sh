#!/usr/bin/env bash
# Stage 2 - run as root, inside the install chroot (install.sh does it) or on the running openSUSE system.
# Safe to re-run. Usage: sudo ./setup.sh [all | step...]
# Steps: base packages user security snapper desktop apps login devtools speakers dotfiles finish
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=config.sh
source "$HERE/config.sh"
FILES=$HERE/files
UHOME=/home/$USERNAME

log() { printf '\e[1;34m==> %s\e[0m\n' "$*"; }
warn() { printf '\e[1;33m!! %s\e[0m\n' "$*" >&2; }
die() { printf '\e[1;31m!! %s\e[0m\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root: sudo $0 $*"

mkdir -p /var/log/mysuse
LOG=/var/log/mysuse/$(date +%F_%H-%M-%S)-setup.log
exec > >(tee -a "$LOG") 2>&1
TEE_PID=$!
trap 'exec >&- 2>&-; wait "$TEE_PID"' EXIT

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

in_chroot() { [[ $(stat -c %d:%i /) != "$(stat -c %d:%i /proc/1/root/. 2>/dev/null)" ]]; }
in_vmware() { grep -qi vmware /sys/class/dmi/id/sys_vendor 2>/dev/null || [[ $(systemd-detect-virt 2>/dev/null) == "vmware" ]]; }
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
    local key=$1 val=${2:-} line out=() word found=0
    [[ -f /etc/default/grub ]] || return 0
    line=$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/\1/p' /etc/default/grub)
    for word in $line; do
        if [[ $word == "$key" || $word == "$key="* ]]; then
            [[ -n $val ]] && out+=("$key=$val") || out+=("$key")
            found=1
        else
            out+=("$word")
        fi
    done
    [[ $found -eq 0 ]] && { [[ -n $val ]] && out+=("$key=$val") || out+=("$key"); }
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${out[*]}\"|" /etc/default/grub
}

tpl() {
    sed -e "s|@USERNAME@|$USERNAME|g" \
        -e "s|@HOME@|$UHOME|g" \
        -e "s|@SCALE@|$DISPLAY_SCALE|g" \
        -e "s|@SCALE_4K@|$DISPLAY_SCALE_4K|g" \
        -e "s|@XKB@|$XKB_LAYOUT|g" \
        "$1"
}

build_jobs() {
    local free_kb jobs
    free_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    jobs=$(( free_kb / 1572864 ))
    (( jobs < 1 )) && jobs=1
    (( jobs > $(nproc) )) && jobs=$(nproc)
    echo "$jobs"
}

step_base() {
    log "base configuration: hostname, locale, console, grub command line"
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

    if [[ -f /swap/swapfile ]]; then
        local uuid dev off
        dev=$(findmnt -no SOURCE /swap)
        uuid=$(blkid -s UUID -o value "$dev")
        off=$(btrfs inspect-internal map-swapfile -r /swap/swapfile 2>/dev/null || true)
        if [[ -n $uuid && -n $off ]]; then
            cmdline_set resume "UUID=$uuid"
            cmdline_set resume_offset "$off"
        fi
    fi

    setkv /etc/default/grub GRUB_DISABLE_OS_PROBER false
}

step_packages() {
    log "package installation via zypper"
    if ! zypper lr packman >/dev/null 2>&1; then
        log "adding Packman repository for full multimedia codecs"
        zypper ar -cfp 90 "$REPO_PACKMAN" packman
    fi
    zypper --gpg-auto-import-keys refresh

    # Remove conflicting power-profiles-daemon if present so TLP installs without prompts
    if rpm -q power-profiles-daemon >/dev/null 2>&1; then
        log "removing power-profiles-daemon (conflicts with TLP)"
        zypper --non-interactive rm -y power-profiles-daemon 2>/dev/null || true
    fi

    # Install base utilities first so downstream tools never fail for missing jq/curl
    zypper --ignore-unknown in -y --no-recommends jq curl ca-certificates-mozilla tar xz unzip

    local pkgs=() line
    while IFS= read -r line || [[ -n $line ]]; do
        line="${line%%#*}"
        line="${line##*( )}"
        [[ -z $line ]] && continue
        # shellcheck disable=SC2206
        pkgs+=($line)
    done < "$HERE/packages.txt"

    if in_vmware; then
        log "VMware detected: adding open-vm-tools-desktop"
        pkgs+=(open-vm-tools-desktop)
    fi

    log "installing ${#pkgs[@]} packages..."
    zypper --non-interactive --ignore-unknown in -y --no-recommends --auto-agree-with-licenses --force-resolution "${pkgs[@]}" || warn "some packages could not be installed"
    zypper dup -y --from packman --allow-vendor-change || true
}

step_user() {
    log "user account, groups, sudo timeout, privileges"
    if ! id "$USERNAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -c "$FULLNAME" "$USERNAME"
    fi
    for g in wheel audio video input disk storage network; do
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
}

step_security() {
    log "security hardening: sysctl, apparmor, firewall"

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
        put 644 /etc/nftables.conf < "$FILES/nftables.conf"
        systemctl enable --now nftables 2>/dev/null || true
    fi

    # disable aggressive background polling services on laptops
    for s in smartd cups-browsed ipp-usb; do
        systemctl disable --now "$s" 2>/dev/null || true
    done
}

step_snapper() {
    log "snapper snapshot configuration"
    [[ -f /etc/snapper/configs/root ]] || snapper create-config / 2>/dev/null || true

    if [[ ! -f /etc/snapper/configs/home ]]; then
        local home_fs
        home_fs=$(findmnt -no FSTYPE /home 2>/dev/null || true)
        if [[ $home_fs == "btrfs" ]]; then
            if [[ -d /home/.snapshots && ! -d /home/.snapshots/1 ]]; then
                btrfs subvolume delete /home/.snapshots 2>/dev/null || rm -rf /home/.snapshots 2>/dev/null || true
            fi
            snapper -c home create-config /home 2>/dev/null || true
        fi
    fi

    for cfg in root home; do
        if [[ -f /etc/snapper/configs/$cfg ]]; then
            sed -i "s|^TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY=\"$SNAP_KEEP_HOURLY\"|" "/etc/snapper/configs/$cfg"
            sed -i "s|^TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY=\"$SNAP_KEEP_DAILY\"|" "/etc/snapper/configs/$cfg"
            sed -i "s|^TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY=\"$SNAP_KEEP_WEEKLY\"|" "/etc/snapper/configs/$cfg"
            sed -i "s|^TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY=\"$SNAP_KEEP_MONTHLY\"|" "/etc/snapper/configs/$cfg"
        fi
    done

    systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
}

step_desktop() {
    log "desktop environment: TLP, thermald, PipeWire, helper scripts, dotfiles"
    if ! in_vmware; then
        systemctl enable --now tlp thermald 2>/dev/null || true
    else
        log "VMware detected: enabling vmtoolsd"
        systemctl enable --now vmtoolsd 2>/dev/null || true
    fi
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
    tpl "$FILES/plasma-displays" | put 755 /usr/local/bin/plasma-displays
    put 755 /usr/local/bin/plasma-keys < "$FILES/plasma-keys"
    put 755 /usr/local/bin/plasma-noctalia-colors < "$FILES/plasma-noctalia-colors"
    tpl "$FILES/plasma-suse-config" | put 755 /usr/local/bin/plasma-suse-config
    put 755 /usr/local/bin/plasma-suse-session < "$FILES/plasma-suse-session"
    put 755 /usr/local/bin/niri-suse-session < "$FILES/niri-suse-session"

    # Install mySuse look-and-feel package system-wide so plasma-apply-lookandfeel finds it
    local lnf_src=$FILES/home/.local/share/plasma/look-and-feel/org.mysuse.desktop
    local lnf_dst=/usr/share/plasma/look-and-feel/org.mysuse.desktop
    if [[ -d $lnf_src ]]; then
        mkdir -p "$lnf_dst"
        cp -r "$lnf_src"/* "$lnf_dst/"
        tpl "$lnf_src/contents/layouts/org.kde.plasma.desktop-layout.js" | put 644 "$lnf_dst/contents/layouts/org.kde.plasma.desktop-layout.js"
    fi

    if [[ $HERE != /usr/local/lib/mysuse ]]; then
        rm -rf /usr/local/lib/mysuse.new
        cp -r "$HERE" /usr/local/lib/mysuse.new
        chown -R root:root /usr/local/lib/mysuse.new
        rm -rf /usr/local/lib/mysuse
        mv /usr/local/lib/mysuse.new /usr/local/lib/mysuse
    fi

    put 644 /etc/cron.d/mysuse <<'EOF'
PATH=/usr/local/bin:/usr/bin:/usr/sbin:/bin
# package index refresh so update-notify can count updates
17 */6 * * * root zypper refresh >/dev/null 2>&1
# Helium, Floorp, Resilio, RustDesk, fonts, cursor, Noctalia: daily upkeep
47 * * * * root power-ok 80 && ! find /var/lib/mysuse/apps.stamp -mmin -1440 2>/dev/null | grep -q . && /usr/local/lib/mysuse/setup.sh apps >/dev/null 2>&1 && touch /var/lib/mysuse/apps.stamp
# monthly btrfs scrub
0 11 1 * * root btrfs scrub start -Bd / >/dev/null 2>&1 || logger -t mysuse "btrfs scrub reported errors"
# plocate index
30 12 * * * root updatedb
# hibernate at 5 % battery
*/2 * * * * root battery-guard
EOF

    # PipeWire user services
    systemctl --user --global enable pipewire wireplumber pipewire-pulse 2>/dev/null || true

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

    # Wallpapers
    as_user mkdir -p "$UHOME/Pictures/Wallpapers"
    local wp=$UHOME/Pictures/Wallpapers/great-wave.jpg
    if [[ ! -s $wp ]] && ! as_user curl -fsSL --max-time 120 -o "$wp" \
        https://upload.wikimedia.org/wikipedia/commons/a/a5/Tsunami_by_hokusai_19th_century.jpg; then
        rm -f "$wp"
        warn "wallpaper download failed; put any image into ~/Pictures/Wallpapers"
    fi

    if command -v typst >/dev/null 2>&1; then
        (cd "$FILES/wallpaper" && typst compile keys-niri.typ "$UHOME/Pictures/Wallpapers/keys-niri.png" 2>/dev/null) || true
        (cd "$FILES/wallpaper" && typst compile keys-plasma.typ "$UHOME/Pictures/Wallpapers/keys-plasma.png" 2>/dev/null) || true
        chown "$USERNAME:$USERNAME" "$UHOME/Pictures/Wallpapers"/keys-*.png 2>/dev/null || true
    fi

    if [[ $HERE != "$UHOME/mySuse" && ! -d "$UHOME/mySuse" ]]; then
        cp -r "$HERE" "$UHOME/mySuse"
        chown -R "$USERNAME:$USERNAME" "$UHOME/mySuse" 2>/dev/null || true
    fi
}

gh_asset() {
    local repo=$1 re=$2 json url=""
    json=$(curl -fsSL --max-time 30 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null) || {
        warn "GitHub API request failed for $repo"
        return 1
    }
    if command -v jq >/dev/null 2>&1; then
        url=$(echo "$json" | jq -r --arg re "$re" '[.assets[]? | select(.name | test($re))][0].browser_download_url // empty' 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        url=$(echo "$json" | python3 -c '
import sys, json, re
try:
    data = json.load(sys.stdin)
    rgx = re.compile(sys.argv[1])
    for a in data.get("assets", []):
        if rgx.search(a.get("name", "")):
            print(a.get("browser_download_url", ""))
            sys.exit(0)
except Exception:
    pass
' "$re" 2>/dev/null)
    fi
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
    put 644 "/usr/local/share/applications/$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$4
Categories=$5
${6:+MimeType=$6}
Terminal=false
EOF
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
    log "upstream applications: Helium, Floorp, Resilio, Noctalia, fonts"
    local h_url f_url
    h_url=$(gh_asset "imputnet/helium-linux" '.*-x86_64_linux\.tar\.xz$') || true
    if [[ -n $h_url ]]; then
        opt_install /opt/helium "$h_url" 1 "$h_url"
        put 755 /usr/local/bin/helium <<'EOF'
#!/bin/sh
exec /opt/helium/helium --password-store=gnome-libsecret --enable-features=VaapiVideoDecodeLinuxGL "$@"
EOF
        desktop_entry helium "Helium" /usr/local/bin/helium /opt/helium/product_logo_128.png \
            "Network;WebBrowser;" "text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;"
    else
        warn "Helium installation skipped (could not fetch release asset)"
    fi

    f_url=$(gh_asset "Floorp-Projects/Floorp" 'floorp.*linux-x86_64\.tar\.xz$') || true
    if [[ -n $f_url ]]; then
        opt_install /opt/floorp "$f_url" 1 "$f_url"
        desktop_entry floorp "Floorp" /opt/floorp/floorp /opt/floorp/browser/chrome/icons/default/default128.png \
            "Network;WebBrowser;" "text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;"
    else
        warn "Floorp installation skipped (could not fetch release asset)"
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

    # Noctalia shell build from git release
    local tag src=/var/cache/noctalia
    if command -v jq >/dev/null 2>&1; then
        tag=$(curl -fsSL --max-time 30 https://api.github.com/repos/noctalia-dev/noctalia/releases/latest 2>/dev/null | jq -r '.tag_name // empty') || tag=""
    elif command -v python3 >/dev/null 2>&1; then
        tag=$(curl -fsSL --max-time 30 https://api.github.com/repos/noctalia-dev/noctalia/releases/latest 2>/dev/null | python3 -c 'import sys, json; print(json.load(sys.stdin).get("tag_name", ""))' 2>/dev/null) || tag=""
    fi
    if [[ -z $tag ]]; then warn "could not determine Noctalia version"; return 0; fi
    if [[ -x /usr/local/bin/noctalia && $(cat /usr/local/share/noctalia/.version 2>/dev/null) == "$tag" ]]; then
        log "Noctalia $tag is current"
    else
        log "building Noctalia $tag..."
        rm -rf "$src"
        if git clone -q --depth 1 --branch "$tag" https://github.com/noctalia-dev/noctalia "$src"; then
            local jobs; jobs=$(build_jobs)
            local lto_opts=("-Db_lto_threads=$jobs")
            if in_vmware; then
                log "VMware detected: disabling LTO to speed up Noctalia build and prevent OOM"
                lto_opts=("-Db_lto=false")
            fi
            if (cd "$src" && just configure release &&
                meson configure build-release "${lto_opts[@]}" &&
                meson compile -C build-release -j "$jobs" noctalia &&
                rm -f /usr/local/bin/noctalia &&
                just install release); then
                mkdir -p /usr/local/share/noctalia
                echo "$tag" > /usr/local/share/noctalia/.version
            else
                warn "Noctalia compilation failed; continuing setup"
            fi
        else
            warn "could not clone Noctalia repository"
        fi
    fi
}

step_login() {
    log "login screen: greetd + tuigreet"
    mkdir -p /usr/share/wayland-sessions
    put 644 /usr/share/wayland-sessions/niri-suse.desktop <<EOF
[Desktop Entry]
Name=Niri (mySuse)
Comment=Scrollable-tiling Wayland compositor
Exec=/usr/local/bin/niri-suse-session
Type=Application
DesktopNames=niri
EOF

    put 644 /usr/share/wayland-sessions/plasma-suse.desktop <<EOF
[Desktop Entry]
Name=Plasma (mySuse)
Comment=KDE Plasma 6 (Wayland)
Exec=/usr/local/bin/plasma-suse-session
Type=Application
DesktopNames=KDE
EOF

    mkdir -p /etc/greetd
    put 644 /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-user-session --sessions /usr/share/wayland-sessions"
user = "greetd"
EOF

    # Ensure greetd user exists
    id greetd >/dev/null 2>&1 || useradd -r -s /bin/false -d /var/lib/greetd -m greetd 2>/dev/null || true

    if command -v greetd >/dev/null 2>&1 && command -v tuigreet >/dev/null 2>&1; then
        systemctl disable sddm gdm lightdm 2>/dev/null || true
        systemctl enable greetd 2>/dev/null || true
    else
        warn "greetd/tuigreet not found; keeping current display manager"
    fi
}

step_devtools() {
    log "developer tools: rustup, Claude Code, Antigravity CLI, Deno, oh-my-pi"
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
}

step_speakers() {
    log "Lenovo X1 Carbon Gen 10 speaker tuning"
    if in_chroot; then log "speakers: tuned after the first boot (sudo ~/mySuse/setup.sh speakers)"; return 0; fi
    local win=/run/mysuse-windows part found="" src=/var/cache/speaker-tuning
    mkdir -p "$win"
    while read -r part; do
        mountpoint -q "$win" || mount -t ntfs3 -o ro "$part" "$win" 2>/dev/null ||
            mount -t ntfs-3g -o ro "$part" "$win" 2>/dev/null || continue
        if [[ -d $win/Windows/System32/DriverStore ]]; then found=$part; break; fi
        umount "$win" 2>/dev/null || true
    done < <(lsblk -lnpo NAME,FSTYPE | awk '$2 == "ntfs" {print $1}')
    if [[ -z $found ]]; then warn "speakers: no Windows partition with Lenovo audio driver found"; return 0; fi

    install -d -o "$USERNAME" -g "$USERNAME" "$src"
    if [[ -d $src/.git ]]; then as_user git -C "$src" pull -q --ff-only || true
    else as_user git clone -q --depth 1 https://github.com/antoinecellerier/speaker-tuning-to-easyeffects "$src"; fi
    as_user python3 "$src/dolby_to_easyeffects.py" --windows "$win" --autoload || warn "speakers: conversion failed"
    umount "$win" 2>/dev/null || true
}

step_finish() {
    log "regenerating dracut initramfs and grub2 configuration"
    dracut --force --hostonly 2>/dev/null || true
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || update-bootloader 2>/dev/null || true
}

ensure_tools() {
    if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
        log "installing core setup utilities (jq, curl, tar, xz, unzip)..."
        zypper --ignore-unknown in -y --no-recommends jq curl ca-certificates-mozilla tar xz unzip 2>/dev/null || true
    fi
}

ensure_tools

steps=("$@")
[[ ${#steps[@]} -eq 0 || ${steps[0]} == all ]] && steps=(base packages user security snapper desktop apps login devtools speakers finish)
for s in "${steps[@]}"; do
    declare -F "step_$s" >/dev/null || die "unknown step '$s'"
    "step_$s"
done
log "setup finished: ${steps[*]}  (log: $LOG)"
