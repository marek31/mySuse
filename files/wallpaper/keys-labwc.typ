// Labwc + Noctalia key cheat sheet, rendered to ~/Pictures/Wallpapers/keys-labwc.png by setup.sh.
#import "keys-style.typ": *

#show: sheet.with("Labwc + Noctalia  ·  x1-suse",
  [Meta = Super  ·  Meta+Shift+/ shows this sheet (Esc closes)  ·  Right-click desktop for menu],
  size: 13.2pt, cols: 4, margin: (left: 54pt, right: 54pt, top: 60pt, bottom: 84pt))

#section(blue, "Apps & Shell",
  ("Meta+Return", "terminal (foot)"),
  ("Meta+D / Space", "launcher (Noctalia)"),
  ("Meta+A", "control center (Noctalia)"),
  ("Meta+,", "Noctalia settings"),
  ("Meta+B / Shift+B", "Helium / Floorp"),
  ("Meta+E", "files (Thunar)"),
  ("Shift+Esc", "btop (system monitor)"),
  ("Right-click", "desktop context menu"),
)

#section(orange, "Screenshots",
  ("PrtSc", "region capture & annotate"),
  ("Shift+PrtSc", "full screen capture"),
  ("Meta+Shift+/", "this cheat sheet full screen"),
)

#section(green, "Windows",
  ("Meta+Q / Alt+F4", "close active window"),
  ("Meta+F / PgUp", "maximise toggle"),
  ("Meta+PgDn", "minimise to taskbar"),
  ("Meta+Shift+F", "fullscreen toggle"),
  ("Meta+V", "toggle always-on-top"),
  ("Alt+Tab / S-Tab", "cycle open windows"),
  ("Meta+drag", "move window"),
  ("Meta+right-drag", "resize window"),
)

#section(yellow, "Snapping & Tiling",
  ("Meta+Left", "snap to left half"),
  ("Meta+Right", "snap to right half"),
  ("Meta+Up", "snap to top half / max"),
  ("Meta+Down", "restore window size"),
  ("Drag to edge", "Aero snap half / quarter"),
)

#section(aqua, "Workspaces",
  ("Meta+1 .. 4", "switch to workspace 1..4"),
  ("Meta+Shift+1 .. 4", "send window to 1..4"),
  ("Taskbar pager", "click 1 2 3 4 to switch"),
)

#section(pink, "Session & Keys",
  ("Meta+L / Meta+Esc", "lock screen (Noctalia)"),
  ("Meta+Shift+E", "exit Labwc session"),
  ("Vol / Mic mute", "hardware audio keys"),
  ("Brightness Up/Dn", "hardware screen backlight"),
)

#cmd(green, "Display & Scaling (Kanshi)",
  ("kanshi", "auto-detects undocked vs 4K dock"),
  ("wlr-randr", "list active outputs & resolutions"),
  ("wlr-randr --output eDP-1 --scale 1.25", "set laptop scaling manually"),
  ("wlr-randr --output DP-1 --scale 1.5", "set 4K scaling manually"),
)

#cmd(yellow, "Labwc & Sfwbar",
  ("labwc --reconfigure", "reload rc.xml keybinds & themes"),
  ("killall -SIGUSR1 sfwbar", "reload taskbar & tray in place"),
  ("sfwbar", "lightweight Wayland taskbar & tray"),
)

#cmd(pink, "System & Snapshots",
  ("zu  ·  zi <pkg>", "zypper dup (auto snapshots) · install"),
  ("nmtui  ·  nmcli wifi", "network manager"),
  ("loginctl suspend  ·  hibernate", "sleep / hibernate"),
  ("snapper -c root list", "list root snapshots (zypper)"),
  ("snapper rollback <num>", "revert system to snapshot"),
)
