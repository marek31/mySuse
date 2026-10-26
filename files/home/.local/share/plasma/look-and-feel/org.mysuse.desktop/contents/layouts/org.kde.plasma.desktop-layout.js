// mySuse Plasma layout: one thin panel glued to the left edge, nothing on the desktop.
// Plasma runs this only when it starts with no layout (first login). Re-apply later (resets panels):
//   plasma-apply-lookandfeel -a org.mysuse.desktop --resetLayout
// Everything else (splash, lock screen, ...) falls back to Breeze.
var panel = new Panel;
panel.location = "left";
panel.height = 40;          // thickness of a vertical panel
panel.floating = false;
panel.hiding = "none";
panel.opacity = "opaque";

panel.addWidget("org.kde.plasma.kickoff");
var tasks = panel.addWidget("org.kde.plasma.icontasks");   // fills the free height
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "");                          // no pinned apps
panel.addWidget("org.kde.plasma.systemtray");
var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", false);
clock.writeConfig("showWeather", false);

desktopsForActivity(currentActivity()).forEach(function (d) {
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file://@HOME@/Pictures/Wallpapers/keys-plasma.png");   // key cheat sheet
});
