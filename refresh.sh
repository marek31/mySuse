#!/bin/sh
# Run as yourself inside Labwc: pull the repo, install packages/apps/dev tools added since,
# update dotfiles (prior versions backed up to ~/.backup), and re-apply live session configuration.
# Note: Zypper packages automatically take pre/post snapshots on root via snapper-zypp-plugin.
set -e
[ "$(id -u)" -ne 0 ] || { echo "run refresh.sh as yourself, not root (it calls sudo itself)"; exit 1; }

cd "$(dirname "$0")"

# Pull latest repository changes
git pull --ff-only || true

sudo ./setup.sh packages security desktop vm apps login devtools speakers

# Re-apply live session configuration
if [ "${XDG_CURRENT_DESKTOP#*labwc}" != "$XDG_CURRENT_DESKTOP" ] || pgrep -x labwc >/dev/null 2>&1; then
    labwc --reconfigure 2>/dev/null || true
    noctalia msg config-reload 2>/dev/null || true
    if ! pgrep -x noctalia >/dev/null 2>&1; then
        if [ -f "$HOME/Pictures/Wallpapers/keys-labwc.png" ]; then
            pkill -x swaybg 2>/dev/null || true
            swaybg -i "$HOME/Pictures/Wallpapers/keys-labwc.png" -m fill >/dev/null 2>&1 &
        fi
    fi
fi

if command -v git-credential-manager >/dev/null 2>&1; then
    if ! git credential-manager github list 2>/dev/null | grep -q ':'; then
        echo "note: GitHub is not authenticated yet - run: git credential-manager github login (or sign in via github-desktop)"
    fi
elif ! gh auth status >/dev/null 2>&1; then
    echo "note: GitHub is not authenticated yet - run once: gh auth login"
fi

echo "done - refresh complete"
