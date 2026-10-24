// niri + Noctalia key cheat sheet, rendered to ~/Pictures/Wallpapers/keys-niri.png by setup.sh (step desktop/dotfiles).
// Keep in sync with files/home/.config/niri/config.kdl (binds) - Super+Shift+/ shows the live list.
#import "keys-style.typ": *

#show: sheet.with("niri  ·  x1-suse",
  [Super = Mod  ·  H J K L and arrows are interchangeable  ·  Super+Shift+/ shows every bind  ·  read this: Super+Page Down to an empty workspace])

#section(blue, "Apps",
  ("Super+Return", "terminal (foot)"),
  ("Super+Shift+Return", "floating terminal"),
  ("Super+Space / D", "launcher"),
  ("Super+B / Shift+B", "Helium / Floorp"),
  ("Super+E", "files (Thunar)"),
  ("Super+A", "audio mixer"),
  ("Super+P", "KeePassXC"),
  ("Ctrl+Shift+Esc", "task manager (btop)"),
)

#section(violet, "Shell (Noctalia)",
  ("Super+S", "control center"),
  ("Super+,", "settings"),
  ("Super+V", "clipboard history"),
  ("Super+.", "emoji"),
  ("Super+N / Shift+N", "do not disturb / clear"),
  ("Super+Ctrl+N", "night light"),
  ("Super+Ctrl+W", "next wallpaper"),
  ("Super+Ctrl+T", "dark / light"),
  ("Alt+Tab", "window switcher"),
)

#section(pink, "Session",
  ("Super+Esc", "lock"),
  ("Super+Shift+Esc", "power menu"),
  ("Super+Shift+E", "log out"),
  ("Super+Shift+P", "screens off"),
  ("Super+Ctrl+Esc", "keys to the app (VM)"),
)

#section(green, "Focus  ·  crosses at the edges",
  ("Super+H / L", "left / right"),
  ("Super+J / K", "down / up"),
  ("Super+Home / End", "first / last column"),
  ("Super+`", "previous window"),
  ("Super+Shift+T", "float <-> tile focus"),
  ("Super+O", "overview"),
)

#section(yellow, "Move  ·  crosses at the edges",
  ("Super+Ctrl+H / L", "column left / right"),
  ("Super+Ctrl+J / K", "window down / up"),
  ("Super+Shift+J / K", "column to ws down / up"),
  ("Super+Shift+H / L", "column to other monitor"),
  ("Super+[ / ]", "into / out of column"),
  ("Super+Ctrl+Home/End", "column to first / last"),
)

#section(aqua, "Size",
  ("Super+Alt + dir", "resize"),
  ("Super+- / =", "width -10 % / +10 %"),
  ("Super+Shift+- / =", "height -10 % / +10 %"),
  ("Super+R / Shift+R", "width / height presets"),
  ("Super+Ctrl+R", "reset height"),
  ("Super+F", "maximise to edges"),
  ("Super+M", "full-width column"),
  ("Super+Ctrl+F", "fill free width"),
  ("Super+Shift+F", "fullscreen"),
  ("Super+Alt+F", "fullscreen in column"),
  ("Super+C / Ctrl+C", "centre / centre all"),
)

#section(orange, "Windows",
  ("Super+Q", "close"),
  ("Super+T", "float / tile"),
  ("Super+W", "tabs in the column"),
  ("Super+drag", "move  ·  right-drag resizes"),
)

#section(blue, "Workspaces",
  ("Super+1..9", "go to workspace"),
  ("Super+Shift+1..9", "column to N"),
  ("Super+Ctrl+1..9", "window to N"),
  ("Super+U / I", "down / up"),
  ("Super+Tab", "previous"),
  ("Super+Shift+PgDn/PgUp", "reorder"),
  ("Super+wheel", "scroll"),
)

#section(violet, "Screenshots  ·  PrtSc",
  ("PrtSc", "whole screen"),
  ("Shift+PrtSc", "region"),
  ("Alt+PrtSc", "window"),
  ("Ctrl+PrtSc", "annotate"),
  ("Super+PrtSc", "record start / stop"),
  ("Super+Shift+PrtSc", "record region"),
)

#cmd(green, "Screens (live, until relogin)",
  ("niri msg outputs", "names, modes, scale, position"),
  ("niri msg output eDP-1 mode 1920x1200@60", "resolution (auto = native)"),
  ("niri msg output eDP-1 scale 1.25", "scaling (auto = guess)"),
  ("niri msg output eDP-1 position set 0 0", "place it (logical px)"),
  ("niri msg output HDMI-A-1 off", "screen off / on"),
  ("niri msg output eDP-1 transform 90", "rotate"),
  ("~/.config/niri/config.kdl", "make it permanent: output blocks (reloads on save)"),
)

#cmd(yellow, "niri",
  ("niri validate", "check the config"),
  ("niri msg windows", "app-id / title (for window rules)"),
  ("niri msg pick-window", "click a window to see it"),
  ("noctalia msg panel-toggle launcher", "any shell action from a script"),
)

#cmd(pink, "System",
  ("zu  ·  zi <pkg>", "update all  ·  install (snapper snapshots)"),
  ("nmtui  ·  nmcli device wifi", "wifi"),
  ("brightnessctl set 50%", "brightness"),
  ("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+", "volume"),
  ("loginctl suspend  ·  hibernate", "sleep"),
  ("snapper -c home list", "snapshots (also root)"),
  ("~/mySuse/refresh.sh undo", "revert the last refresh"),
)
