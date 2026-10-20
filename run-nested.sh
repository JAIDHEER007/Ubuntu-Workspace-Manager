#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Run this extension in a nested GNOME Shell window with throwaway settings,
# so the real session's extensions and dconf are left untouched.
# Needs: sudo apt install mutter-dev-bin
set -e
cd "$(dirname "$0")"
glib-compile-schemas schemas/

UUID=ubuntu-workspace-manager@jaidheer007.github.io
WM_PREFS=org.gnome.desktop.wm.preferences

# Copy your real workspace setup so the test shell shows the same names.
NAMES=$(gsettings get $WM_PREFS workspace-names)
NUM=$(gsettings get $WM_PREFS num-workspaces)
DYNAMIC=$(gsettings get org.gnome.mutter dynamic-workspaces)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/data/gnome-shell/extensions"
ln -s "$PWD" "$TMP/data/gnome-shell/extensions/$UUID"

export XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data"
export MUTTER_DEBUG_DUMMY_MODE_SPECS=${MUTTER_DEBUG_DUMMY_MODE_SPECS:-1280x800}

# A private D-Bus session gets its own dconf-service, which writes under $TMP.
dbus-run-session sh -c "
    gsettings set org.gnome.shell enabled-extensions \"['$UUID']\"
    gsettings set $WM_PREFS workspace-names \"$NAMES\"
    gsettings set $WM_PREFS num-workspaces $NUM
    gsettings set org.gnome.mutter dynamic-workspaces $DYNAMIC
    gnome-shell --devkit --wayland
"
