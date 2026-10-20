#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install Ubuntu Workspace Manager for the current user.
#
#   ./install.sh                         use the default shortcut (Shift+Alt+Space)
#   ./install.sh --shortcut '<Super>m'   use a different shortcut
#
# Checks that the shortcut isn't used elsewhere (asking for another one if it
# is), writes it into the installed schema, compiles the schema and copies the
# extension to ~/.local/share/gnome-shell/extensions/<uuid>/.
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
KEY=show-move-to-workspace-menu
EXT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"

die() { echo "Error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

confirm() {
    [ -t 0 ] || return 1
    local answer
    read -r -p "$1 [y/N] " answer
    [[ $answer == [yY]* ]]
}

SHORTCUT=
while [ $# -gt 0 ]; do
    case $1 in
    --shortcut)
        [ $# -ge 2 ] || die "--shortcut needs a value, e.g. --shortcut '<Super>m'"
        SHORTCUT=$2
        shift 2
        ;;
    -h | --help)
        sed -n '4,11s/^# \{0,1\}//p' "$0"
        exit 0
        ;;
    *) die "Unknown option '$1' (see --help)" ;;
    esac
done

for cmd in gnome-shell gsettings dconf glib-compile-schemas; do
    command -v "$cmd" >/dev/null || die "'$cmd' not found. Is GNOME installed?"
done

# --- Read the extension's metadata and schema -------------------------------

for f in extension.js metadata.json; do
    [ -f "$SRC/$f" ] || die "$f is missing from $SRC"
done
SCHEMA_XML=$(find "$SRC/schemas" -maxdepth 1 -name '*.gschema.xml' 2>/dev/null | head -n 1)
[ -n "$SCHEMA_XML" ] || die "No schemas/*.gschema.xml in $SRC"

UUID=$(sed -n 's/.*"uuid": *"\([^"]*\)".*/\1/p' "$SRC/metadata.json")
[[ $UUID =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$ ]] || die "Invalid uuid in metadata.json: '$UUID'"
SCHEMA_ID=$(sed -n 's/.*<schema id="\([^"]*\)".*/\1/p' "$SCHEMA_XML")
SCHEMA_PATH=$(sed -n 's/.*path="\([^"]*\)".*/\1/p' "$SCHEMA_XML")
DEFAULT=$(sed -n "s/.*<default><!\[CDATA\[\['\(.*\)'\]\]\]><\/default>.*/\1/p" "$SCHEMA_XML")
[ -n "$SCHEMA_ID" ] && [ -n "$SCHEMA_PATH" ] && [ -n "$DEFAULT" ] ||
    die "Couldn't read the schema id, path or default shortcut from $SCHEMA_XML"
DEST="$EXT_ROOT/$UUID"

SHELL_MAJOR=$(gnome-shell --version | sed -n 's/^GNOME Shell \([0-9]*\).*/\1/p')
if ! grep -q "\"shell-version\":.*\"$SHELL_MAJOR\"" "$SRC/metadata.json"; then
    echo "Warning: GNOME Shell $SHELL_MAJOR isn't listed in metadata.json's shell-version,"
    echo "         so GNOME will refuse to load the extension."
    confirm "Install anyway?" || die "Cancelled; nothing was installed."
fi

# --- Shortcut conflict check -------------------------------------------------

# Every accelerator GNOME knows about, as "SOURCE<TAB>VALUE" lines.
BINDINGS=$(mktemp)
STAGE=
cleanup() {
    rm -f "$BINDINGS"
    if [ -n "$STAGE" ]; then rm -rf "$STAGE"; fi
}
trap cleanup EXIT

{
    # Installed schemas, defaults included: GNOME, Ubuntu, IBus, system extensions.
    gsettings list-recursively 2>/dev/null |
        awk '{ src = $1 " " $2; $1 = $2 = ""; print src "\t" $0 }'

    # Custom shortcuts from Settings > Keyboard.
    media=org.gnome.settings-daemon.plugins.media-keys
    for p in $(gsettings get $media custom-keybindings | grep -o "/[^']*/"); do
        printf 'custom shortcut %s\t%s\n' \
            "$(gsettings get $media.custom-keybinding:"$p" name)" \
            "$(gsettings get $media.custom-keybinding:"$p" binding)"
    done

    # Values you've changed, including user-installed extensions' settings.
    # This extension's own settings are skipped.
    dconf dump / | awk -v ours="${SCHEMA_PATH#/}" '
        /^\[/ { sec = substr($0, 2, length($0) - 2) "/"; next }
        index(sec, ours) == 1 { next }
        /=/ { i = index($0, "="); print "dconf /" sec substr($0, 1, i - 1) "\t" substr($0, i + 1) }'

    # Defaults of user-installed extensions (their schemas aren't system-wide).
    for f in "$EXT_ROOT"/*/schemas/*.gschema.xml; do
        [ -f "$f" ] || continue
        case $f in "$DEST"/*) continue ;; esac
        ext=$(basename "$(dirname "$(dirname "$f")")")
        sed -n 's/&lt;/</g; s/&gt;/>/g; /<default>/p' "$f" | sed "s|^|extension $ext (default)\t|"
    done
} >"$BINDINGS"

# Print who uses accelerator $1. Modifier order, case and aliases
# (<Ctrl>/<Control>/<Primary>, <Mod1>/<Alt>) don't matter.
find_users() {
    awk -F '\t' -v target="$1" '
        function canon(m) {
            if (m == "control" || m == "ctrl" || m == "primary") return "ctrl"
            if (m == "mod1") return "alt"
            if (m == "mod4") return "super"
            return m
        }
        function norm(a,    mods, n, i, j, t, c, parts, out) {
            a = tolower(a); n = 0
            while (match(a, /<[^>]+>/)) {
                mods[++n] = canon(substr(a, RSTART + 1, RLENGTH - 2))
                a = substr(a, RSTART + RLENGTH)
            }
            if (n == 0) {  # IBus style: Shift+Alt+space
                c = split(a, parts, "+")
                for (i = 1; i < c; i++) mods[++n] = canon(parts[i])
                a = parts[c]
            }
            if (a == "") return ""
            for (i = 2; i <= n; i++)
                for (j = i; j > 1 && mods[j - 1] > mods[j]; j--) {
                    t = mods[j]; mods[j] = mods[j - 1]; mods[j - 1] = t
                }
            out = ""
            for (i = 1; i <= n; i++)
                if (i == 1 || mods[i] != mods[i - 1]) out = out mods[i] "+"
            return out a
        }
        BEGIN { want = norm(target) }
        {
            src = $1; v = $2
            while (match(v, /'"'"'[^'"'"']*'"'"'/)) {
                tok = substr(v, RSTART + 1, RLENGTH - 2)
                v = substr(v, RSTART + RLENGTH)
                if (index(tok, "<") == 0 && !(src ~ /^org\.freedesktop\.ibus/ && index(tok, "+")))
                    continue
                if (norm(tok) == want) print src "  (" tok ")"
            }
        }' "$BINDINGS" | sort -u
}

valid_shortcut() {
    local valid='^(<(shift|control|ctrl|primary|alt|super|meta|hyper|mod[1-5])>)+[a-z0-9_]+$'
    local shift_only='^(<shift>)+[a-z0-9_]+$'
    local s=${1,,}
    [[ $s =~ $valid ]] || return 1
    # Shift alone would steal normal typing (Shift+A is a capital A).
    [[ $s =~ $shift_only ]] && return 1
    return 0
}

suggest_free() {
    local found=0 c
    for c in '<Super><Alt>m' '<Control><Super>m' '<Super><Alt>w' '<Control><Alt>m' \
        '<Shift><Super>space' '<Control><Shift><Alt>space'; do
        if valid_shortcut "$c" && [ -z "$(find_users "$c")" ]; then
            echo "    $c"
            found=$((found + 1))
            [ $found -lt 3 ] || break
        fi
    done
}

SHORTCUT=${SHORTCUT:-$DEFAULT}
while true; do
    if ! valid_shortcut "$SHORTCUT"; then
        echo "'$SHORTCUT' isn't a usable shortcut. Use GNOME's format with at least one"
        echo "modifier besides Shift alone, e.g. <Shift><Alt>space, <Super>m or <Control><Super>Page_Up."
    else
        users=$(find_users "$SHORTCUT")
        if [ -z "$users" ]; then
            info "Shortcut $SHORTCUT is free"
            break
        fi
        echo "Shortcut $SHORTCUT is already used by:"
        echo "$users" | sed 's/^/    /'
    fi

    echo "Some free shortcuts:"
    suggest_free
    [ -t 0 ] || die "Run again with a free shortcut: ./install.sh --shortcut '<shortcut>'"
    read -r -p "Enter a different shortcut (empty to cancel): " SHORTCUT
    [ -n "$SHORTCUT" ] || die "Cancelled; nothing was installed."
done

# --- Install -----------------------------------------------------------------

if [ -L "$DEST" ]; then
    die "$DEST is a symlink (a development install). Remove it with ./uninstall.sh first."
elif [ -e "$DEST" ]; then
    grep -q "\"uuid\": *\"$UUID\"" "$DEST/metadata.json" 2>/dev/null ||
        die "$DEST exists but isn't this extension. Not touching it."
    info "Updating the existing install"
fi

# Build the new copy next to the extensions folder, then swap it in.
mkdir -p "$EXT_ROOT"
STAGE=$(mktemp -d "$(dirname "$EXT_ROOT")/.uwm-install.XXXXXX")
cp "$SRC/extension.js" "$SRC/metadata.json" "$STAGE/"
if [ -f "$SRC/LICENSE" ]; then cp "$SRC/LICENSE" "$STAGE/"; fi
mkdir "$STAGE/schemas"
sed "s|<default><!\[CDATA\[.*\]\]></default>|<default><![CDATA[['$SHORTCUT']]]></default>|" \
    "$SCHEMA_XML" >"$STAGE/schemas/$SCHEMA_ID.gschema.xml"
info "Compiling the settings schema"
glib-compile-schemas --strict "$STAGE/schemas"

# The installer's choice wins over any shortcut set earlier with gsettings.
dconf reset -f "$SCHEMA_PATH"
got=$(gsettings --schemadir "$STAGE/schemas" get "$SCHEMA_ID" "$KEY")
[ "$got" = "['$SHORTCUT']" ] || die "Schema check failed: expected ['$SHORTCUT'], got $got"

chmod 755 "$STAGE"
if [ -d "$DEST" ]; then rm -rf -- "$DEST"; fi
mv "$STAGE" "$DEST"
STAGE=
info "Installed to $DEST"

# Turn it on: GNOME enables it at the next login.
list=$(gsettings get org.gnome.shell enabled-extensions)
case $list in
*"'$UUID'"*) ;;
"@as []" | "[]") gsettings set org.gnome.shell enabled-extensions "['$UUID']" ;;
*) gsettings set org.gnome.shell enabled-extensions "${list%]}, '$UUID']" ;;
esac
list=$(gsettings get org.gnome.shell disabled-extensions)
uuid_re=${UUID//./\\.}
new=$(printf '%s' "$list" | sed -e "s/'$uuid_re', //; s/, '$uuid_re'//; s/'$uuid_re'//")
if [ "$new" != "$list" ]; then gsettings set org.gnome.shell disabled-extensions "$new"; fi
info "Enabled $UUID"

if [ "$(gsettings get org.gnome.shell disable-user-extensions)" = true ]; then
    echo "Warning: user extensions are turned off. Turn them on in the Extensions app, or run:"
    echo "    gsettings set org.gnome.shell disable-user-extensions false"
fi

cat <<EOF

Done. Log out and back in to load the extension (Wayland only loads
extensions at login). Then check it with:
    gnome-extensions info $UUID
Shortcut: $SHORTCUT
EOF
