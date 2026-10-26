// KDE Plasma key cheat sheet, rendered to ~/Pictures/Wallpapers/keys-plasma.png by setup.sh (step desktop/dotfiles).
// Our keys come from files/plasma-suse-config, the rest are Plasma 6 defaults.
#import "keys-style.typ": *

#show: sheet.with("Plasma  ·  x1-suse",
  [Meta = Super  ·  Meta+Shift+/ shows this sheet (Esc closes)  ·  Meta+Shift+D shows the desktop], size: 14.6pt, cols: 3)

#section(blue, "Apps",
  ("Meta", "application menu"),
  ("Meta+D / Space", "KRunner: apps, files, 2+2"),
  ("Alt+Space / Alt+F2", "KRunner too"),
  ("Meta+Return", "terminal (foot)"),
  ("Meta+B / Shift+B", "Helium / Floorp"),
  ("Meta+E", "files (Thunar)"),
  ("Meta+A", "audio mixer"),
  ("Shift+Esc", "btop (system monitor)"),
)

#section(violet, "Desktop",
  ("Meta+Shift+/", "this sheet full screen"),
  ("Meta+V", "clipboard history"),
  ("Meta+.", "emoji"),
  ("Meta+O / W", "overview"),
  ("Meta+Shift+D", "peek at desktop"),
  ("Meta+P", "extend / mirror screens"),
  ("Meta+= / - / 0", "zoom in / out / reset"),
)

#section(pink, "Session",
  ("Meta+Esc / Meta+L", "lock"),
  ("Meta+Shift+E", "log out"),
  ("Ctrl+Alt+Del", "log out too"),
)

#section(green, "Windows",
  ("Meta+Q / Alt+F4", "close"),
  ("Meta+F / PgUp", "maximise"),
  ("Meta+PgDn", "minimise"),
  ("Meta+Shift+F", "fullscreen"),
  ("Alt+Tab", "switch windows"),
  ("Alt+F3", "window menu"),
  ("Meta+drag", "move  ·  right-drag resizes"),
)

#section(yellow, "Tiling",
  ("Meta+Left / Right", "left / right half"),
  ("Meta+Up / Down", "top / bottom half"),
  ("Meta+T", "tiling layout editor"),
  ("Shift+drag", "drop into a tile"),
)

#section(aqua, "Desktops & screens",
  ("Meta+1..4", "go to desktop"),
  ("Meta+Shift+1..4", "window to N"),
  ("Meta+Ctrl+Left/Right", "desktop left / right"),
  ("Ctrl+F1..F4", "go to desktop"),
  ("Meta+Shift+Left/Right", "window to other screen"),
)

#section(orange, "Screenshots",
  ("PrtSc", "Spectacle"),
  ("Meta+Shift+PrtSc", "region"),
  ("Meta+PrtSc", "active window"),
  ("Shift+PrtSc", "whole desktop"),
)

#cmd(green, "Screens (kept by Plasma)",
  ("kscreen-doctor -o", "names, modes, scale, position"),
  ("kscreen-doctor output.eDP-1.mode.1920x1200@60", "resolution"),
  ("kscreen-doctor output.eDP-1.scale.1.25", "scaling"),
  ("kscreen-doctor output.eDP-1.position.512,1440", "place it (logical px)"),
  ("kscreen-doctor output.HDMI-A-1.disable", "screen off (enable = on)"),
  ("kscreen-doctor output.eDP-1.rotation.left", "rotate"),
  ("System Settings > Display & Monitor", "the same with the mouse"),
)

#cmd(yellow, "Plasma",
  ("plasma-apply-wallpaperimage <file>", "wallpaper"),
  ("plasma-apply-colorscheme <name>", "colours (e.g. BreezeDark)"),
  ("plasma-apply-lookandfeel -a org.mysuse.desktop --resetLayout", "panel back to the repo layout"),
  ("kquitapp6 plasmashell; kstart plasmashell", "restart the panel / desktop"),
)

#cmd(pink, "System",
  ("zu  ·  zi <pkg>", "update all  ·  install (snapper snapshots)"),
  ("nmtui  ·  nmcli device wifi", "wifi"),
  ("loginctl suspend  ·  hibernate", "sleep"),
  ("snapper -c home list", "snapshots (also root)"),
  ("~/mySuse/refresh.sh undo", "revert the last refresh"),
)
