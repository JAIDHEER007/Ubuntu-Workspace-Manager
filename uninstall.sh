#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Uninstall Ubuntu Workspace Manager for the current user.
#
#   ./uninstall.sh       show what will be removed and ask first
#   ./uninstall.sh -y    don't ask
#
# Removes only this extension's own files and settings. Other extensions and
# anything you added to the extension folder are left alone.
set -euo pipefail

UUID=ubuntu-workspace-manager@jaidheer007.github.io
SCHEMA_ID=org.gnome.shell.extensions.ubuntu-workspace-manager
SETTINGS_PATH=/org/gnome/shell/extensions/ubuntu-workspace-manager/
EXT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
DEST="$EXT_ROOT/$UUID"

# Exactly the files install.sh creates.
FILES=(extension.js metadata.json LICENSE "schemas/$SCHEMA_ID.gschema.xml" schemas/gschemas.compiled)

die() { echo "Error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

YES=false
case ${1-} in
"") ;;
-y | --yes) YES=true ;;
-h | --help) sed -n '4,10s/^# \{0,1\}//p' "$0"; exit 0 ;;
*) die "Unknown option '$1' (see --help)" ;;
esac

# --- Work out what's installed ----------------------------------------------

if [ -L "$DEST" ]; then
    KIND=symlink
    echo "Found a symlink (development install):"
    echo "    $DEST -> $(readlink "$DEST")"
    echo "Only the link is removed; the folder it points to is not touched."
elif [ -d "$DEST" ]; then
    grep -q "\"uuid\": *\"$UUID\"" "$DEST/metadata.json" 2>/dev/null ||
        die "$DEST doesn't contain this extension's metadata.json. Not touching it."
    KIND=folder
    echo "Found the extension in $DEST. These files will be removed:"
    for f in "${FILES[@]}"; do
        if [ -e "$DEST/$f" ]; then echo "    $f"; fi
    done
elif [ -e "$DEST" ]; then
    die "$DEST exists but isn't a folder or symlink. Not touching it."
else
    KIND=none
    echo "No installed files found at $DEST."
fi
echo "Its settings ($SETTINGS_PATH) are reset and it's removed from GNOME's extension lists."

if ! $YES; then
    [ -t 0 ] || die "Not running in a terminal; use -y to uninstall without asking."
    read -r -p "Continue? [y/N] " answer
    [[ $answer == [yY]* ]] || die "Cancelled; nothing was changed."
fi

# --- Uninstall ----------------------------------------------------------------

# Let the running shell call disable(), so the shortcut goes away right now.
if gnome-extensions disable "$UUID" 2>/dev/null; then
    info "Disabled $UUID"
fi

# Drop the UUID from both lists, leaving every other extension's entry as is.
uuid_re=${UUID//./\\.}
for key in enabled-extensions disabled-extensions; do
    list=$(gsettings get org.gnome.shell $key)
    new=$(printf '%s' "$list" | sed -e "s/'$uuid_re', //; s/, '$uuid_re'//; s/'$uuid_re'//")
    if [ "$new" != "$list" ]; then
        gsettings set org.gnome.shell $key "$new"
        info "Removed it from $key"
    fi
done

case $KIND in
symlink)
    # No -r and no trailing slash: removes the link, never what it points to.
    rm -- "$DEST"
    info "Removed the symlink"
    ;;
folder)
    for f in "${FILES[@]}"; do rm -f -- "$DEST/$f"; done
    rmdir -- "$DEST/schemas" 2>/dev/null || true
    if rmdir -- "$DEST" 2>/dev/null; then
        info "Removed $DEST"
    else
        echo "Kept $DEST because it still has files install.sh didn't put there:"
        find "$DEST" -mindepth 1 | sed 's/^/    /'
    fi
    ;;
esac

dconf reset -f "$SETTINGS_PATH"
info "Reset its settings"

echo
echo "Done. Log out and back in to clear it from the running shell completely."
