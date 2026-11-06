for (let w of workspace.windowList()) {
    if (w.desktopFileName === "btop" || w.resourceClass === "btop") {
        if (w.minimized) {
            w.minimized = false;
        }
        if (w.desktops && w.desktops.length > 0) {
            workspace.currentDesktop = w.desktops[0];
        }
        workspace.activeWindow = w;
        break;
    }
}
