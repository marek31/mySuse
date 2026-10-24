#!/bin/sh
# Run as yourself inside niri: pull the repo, install packages/apps/dev tools added since,
# take its dotfiles (your old ones go to ~/.backup), and restart Noctalia.
#
# Every run is wrapped in snapper pre/post snapshots of / and /home. If something breaks afterwards:
#   ~/mySuse/refresh.sh undo     (also works from a text console: Ctrl+Alt+F2, log in)
# reverts everything the last run changed in your home plus /usr/local and /etc/greetd.
set -e
[ "$(id -u)" -ne 0 ] || { echo "run refresh.sh as yourself, not root (it calls sudo itself)"; exit 1; }
state=${XDG_STATE_HOME:-$HOME/.local/state}/mysuse/refresh-snapshots

restart_noctalia() {
    if [ "$XDG_CURRENT_DESKTOP" != niri ] || [ -z "$WAYLAND_DISPLAY" ]; then
        echo "not inside niri, so Noctalia was not restarted (log out and back in to see changes)"
        return 0
    fi
    log=~/.local/state/noctalia/$(date '+%F')-noctalia.log
    mkdir -p "$(dirname "$log")"
    pkill -x noctalia || true
    i=0
    while pgrep -x noctalia >/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    pkill -KILL -x noctalia 2>/dev/null || true
    setsid -f noctalia >>"$log" 2>&1
    sleep 3
    pgrep -x noctalia >/dev/null || { echo "Noctalia did not start - last lines of $log:"; tail -n 20 "$log"; return 1; }
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
    sudo snapper --no-dbus -c home undochange "$hpre..$hpost"
    sudo snapper --no-dbus -c root status "$rpre..$rpost" | sed 's/^[^ ]* //' | grep -E '^/(usr/local|etc/greetd)(/|$)' |
        xargs -r -d '\n' sudo snapper --no-dbus -c root undochange "$rpre..$rpost"
    sed -i '$d' "$state"
    restart_noctalia || true
    rm -f "$REFRESH_UNDO_COPY"
    echo "done - log out and back in if the desktop still looks wrong"
    exit 0
fi

cd "$(dirname "$0")"
rpre=$(sudo snapper --no-dbus -c root create -t pre -p -c number -d "refresh.sh")
hpre=$(sudo snapper --no-dbus -c home create -t pre -p -c number -d "refresh.sh")
finish() {
    rc=$?
    rpost=$(sudo snapper --no-dbus -c root create -t post --pre-number "$rpre" -p -c number -d "refresh.sh")
    hpost=$(sudo snapper --no-dbus -c home create -t post --pre-number "$hpre" -p -c number -d "refresh.sh")
    mkdir -p "${state%/*}"
    echo "$rpre $rpost $hpre $hpost" >> "$state"
    [ $rc -eq 0 ] && echo "done" || echo "refresh.sh failed (exit $rc)"
    echo "something wrong now? ~/mySuse/refresh.sh undo"
    exit $rc
}
trap finish EXIT

git pull --ff-only
sudo ./setup.sh packages security apps login devtools speakers dotfiles

grep -Eqs '^\[(bar|widget)' ~/.local/state/noctalia/settings.toml &&
    echo "note: ~/.local/state/noctalia/settings.toml overrides the bar; remove its [bar...]/[widget...] sections to get the repo look"

if ! gh auth status >/dev/null 2>&1 || ! git config --global --get credential.https://github.com.helper >/dev/null; then
    echo "note: git can't push to GitHub yet - run once: gh auth login, then: gh auth setup-git"
fi
restart_noctalia
