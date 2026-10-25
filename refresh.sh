#!/bin/sh
# Run as yourself inside KDE Plasma: pull the repo, install packages/apps/dev tools added since,
# take its dotfiles (your old ones go to ~/.backup), and apply Plasma configuration.
#
# Every run is wrapped in snapper pre/post snapshots of / and /home. If something breaks afterwards:
#   ~/mySuse/refresh.sh undo     (also works from a text console: Ctrl+Alt+F2, log in)
# reverts everything the last run changed in your home plus /usr/local.
set -e
[ "$(id -u)" -ne 0 ] || { echo "run refresh.sh as yourself, not root (it calls sudo itself)"; exit 1; }
state=${XDG_STATE_HOME:-$HOME/.local/state}/mysuse/refresh-snapshots

has_cfg() {
    sudo snapper --no-dbus list-configs 2>/dev/null | awk -v c="$1" '$1 == c {found=1} END {exit !found}'
}

if [ "$1" = undo ]; then
    if [ -z "$REFRESH_UNDO_COPY" ]; then
        copy=$(mktemp "${TMPDIR:-/tmp}/refresh-undo.XXXXXX")
        cp "$0" "$copy"
        REFRESH_UNDO_COPY=$copy exec sh "$copy" undo
    fi
    [ -s "$state" ] || { echo "no refresh.sh run recorded in $state"; exit 1; }
    read -r rpre rpost hpre hpost <<EOF
$(tail -n 1 "$state")
EOF
    echo "undoing the last refresh: home snapshots $hpre..$hpost, / snapshots $rpre..$rpost"
    if [ "$hpre" != "none" ] && [ "$hpost" != "none" ] && has_cfg home; then
        sudo snapper --no-dbus -c home undochange "$hpre..$hpost" || true
    fi
    if [ "$rpre" != "none" ] && [ "$rpost" != "none" ] && has_cfg root; then
        sudo snapper --no-dbus -c root status "$rpre..$rpost" | sed 's/^[^ ]* //' | grep -E '^/(usr/local)(/|$)' |
            xargs -r -d '\n' sudo snapper --no-dbus -c root undochange "$rpre..$rpost"
    fi
    sed -i '$d' "$state"
    plasma-suse-config -f 2>/dev/null || true
    rm -f "$REFRESH_UNDO_COPY"
    echo "done - log out and back in if the desktop still looks wrong"
    exit 0
fi

cd "$(dirname "$0")"

# Pull latest repository changes
git pull --ff-only || true

rpre="none"
hpre="none"
if has_cfg root; then
    rpre=$(sudo snapper --no-dbus -c root create -t pre -p -c number -d "refresh.sh" 2>/dev/null || echo "none")
fi
if has_cfg home; then
    hpre=$(sudo snapper --no-dbus -c home create -t pre -p -c number -d "refresh.sh" 2>/dev/null || echo "none")
fi

finish() {
    rc=$?
    rpost="none"
    hpost="none"
    if [ "$rpre" != "none" ] && has_cfg root; then
        rpost=$(sudo snapper --no-dbus -c root create -t post --pre-number "$rpre" -p -c number -d "refresh.sh" 2>/dev/null || echo "none")
    fi
    if [ "$hpre" != "none" ] && has_cfg home; then
        hpost=$(sudo snapper --no-dbus -c home create -t post --pre-number "$hpre" -p -c number -d "refresh.sh" 2>/dev/null || echo "none")
    fi
    if [ "$rpre" != "none" ] || [ "$hpre" != "none" ]; then
        mkdir -p "${state%/*}"
        echo "$rpre $rpost $hpre $hpost" >> "$state"
    fi
    [ $rc -eq 0 ] && echo "done" || echo "refresh.sh failed (exit $rc)"
    echo "something wrong now? ~/mySuse/refresh.sh undo"
    exit $rc
}
trap finish EXIT

sudo ./setup.sh packages security apps login devtools speakers dotfiles

# Re-apply Plasma configuration (layout, theme, icons, shortcuts)
plasma-suse-config -f 2>/dev/null || true

if ! gh auth status >/dev/null 2>&1 || ! git config --global --get credential.https://github.com.helper >/dev/null; then
    echo "note: git can't push to GitHub yet - run once: gh auth login, then: gh auth setup-git"
fi
