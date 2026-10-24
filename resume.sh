#!/usr/bin/env bash
# resume.sh - run from an openSUSE live USB to re-enter a broken or half-finished install and run setup.sh.
# Usage: sudo ./resume.sh [step...]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
die() { printf '\e[1;31m!! %s\e[0m\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root: sudo $0 $*"

if ! mountpoint -q /mnt; then
    if [[ -e /dev/disk/by-id ]]; then
        part=$(ls /dev/disk/by-id/*part* 2>/dev/null | grep -v 'nvme.*-eui' | head -n1 || true)
    fi
    if cryptsetup isLuks "${part:-}" 2>/dev/null; then
        cryptsetup status cryptroot >/dev/null 2>&1 || cryptsetup open "$part" cryptroot
        dev=/dev/mapper/cryptroot
    else
        dev=$(blkid -L root 2>/dev/null || blkid -L opensuse 2>/dev/null || true)
        [[ -n $dev ]] || die "no LUKS partition or btrfs labeled 'root' found"
    fi
    mount -o subvol=@ "$dev" /mnt
    while read -r src mp type opts _; do
        [[ $src == \#* || $mp == / || ! $type =~ ^(btrfs|vfat|ext4)$ ]] && continue
        mkdir -p "/mnt$mp"
        mount -t "$type" -o "$opts" "$src" "/mnt$mp" 2>/dev/null || true
    done < /mnt/etc/fstab
fi

for d in sys dev proc; do
    mountpoint -q "/mnt/$d" || { mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; }
done

if [[ -f /mnt/swap/swapfile ]] && ! grep -q /swap/swapfile /proc/swaps; then swapon /mnt/swap/swapfile 2>/dev/null || true; fi
cp -L /etc/resolv.conf /mnt/etc/
rm -rf /mnt/root/mySuse
cp -r "$HERE" /mnt/root/mySuse
chroot /mnt /root/mySuse/setup.sh "${@:-all}"
echo "Done. When finished: swapoff -a; umount -R /mnt; cryptsetup close cryptroot; reboot"
