#!/bin/sh
# /etc/NetworkManager/dispatcher.d/99-save-wifi-psk.sh
# Automatically locks Wi-Fi passwords into the system connection profile (psk-flags 0)
# upon successful connection so NetworkManager never prompts again on reconnects.

if [ "$2" = "up" ] && [ -n "$CONNECTION_UUID" ]; then
    nmcli connection modify "$CONNECTION_UUID" 802-11-wireless-security.psk-flags 0 2>/dev/null || true
fi
