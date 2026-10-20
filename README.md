# Ubuntu Workspace Manager

A small GNOME Shell extension that moves a window to any workspace **without
switching your view**.

- **Window menu:** right-click a window's title bar (or press `Alt+Space`) →
  **Move to Workspace** → pick a workspace.
- **Shortcut:** press `Shift+Alt+Space` to open the workspace list for the
  focused window directly. Use the arrow keys + `Enter`, or click. `Esc` closes it.

Workspaces are listed by their names: the custom names you set (for example
with the **Workspace Indicator** extension), or "Workspace N" for any workspace
without one. The window's current workspace is marked with a dot and can't be selected.
Nothing is shown if there is only one workspace, or if the window is set to
"Always on Visible Workspace".

Built for **GNOME Shell 50** (tested on Ubuntu, GNOME Shell 50.1, Wayland).

## Files

| File | Purpose |
| --- | --- |
| `extension.js` | The extension code |
| `metadata.json` | UUID (`ubuntu-workspace-manager@jaidheer007.github.io`), supported shell version, settings schema |
| `schemas/*.gschema.xml` | Defines the shortcut setting (default `<Shift><Alt>space`) |
| `install.sh` | Checks the shortcut is free, builds the schema, installs and enables the extension |
| `uninstall.sh` | Removes only this extension's files and settings |
| `run-nested.sh` | Runs the extension in a nested test shell |
| `LICENSE` | GPL-2.0-or-later |

`schemas/gschemas.compiled` is generated (by `install.sh`, `run-nested.sh`, or
`glib-compile-schemas schemas/`) and isn't committed.

## How it works

1. **Window menu hook.** GNOME builds the window menu in
   `WindowMenu._buildMenu()` (`resource:///org/gnome/shell/ui/windowMenu.js`).
   On `enable()`, the extension wraps that method with an `InjectionManager`.
   GNOME's original code runs first, then the extension adds a
   **Move to Workspace** submenu right after GNOME's
   "Move to Workspace Left/Right/Up/Down" items (just before the first separator).
2. **Workspace names.** Each entry's label comes from
   `Meta.prefs_get_workspace_name(i)`, the same call Workspace Indicator uses.
   It reads GNOME's `org.gnome.desktop.wm.preferences workspace-names` setting
   and falls back to "Workspace N". The menu is rebuilt each time it opens, so
   a renamed workspace shows up immediately. To see your current names:

   ```sh
   gsettings get org.gnome.desktop.wm.preferences workspace-names
   ```

3. **Moving without switching.** Each entry calls
   `window.change_workspace(workspace)`. GNOME's own "Move to Workspace
   Left/Right" menu items use the same call. GNOME's built-in *keyboard*
   shortcuts for moving windows also switch your view, so the extension
   doesn't use them.
4. **Shortcut.** On `enable()`, the extension registers the
   `show-move-to-workspace-menu` key from its settings schema with
   `Main.wm.addKeybinding()`. When you press the key, it sets a flag and asks
   GNOME's own window-menu manager to open a menu for the focused window. With
   the flag set, the hooked `_buildMenu()` builds only the workspace list. The
   shortcut menu therefore positions, takes keyboard focus and closes exactly
   like `Alt+Space`.
5. **Cleanup.** `disable()` removes the shortcut and restores the original
   `_buildMenu()`. The window menu is rebuilt every time it opens, so nothing
   else is left behind.

## Check whether a shortcut is already used

Before you pick a key, make sure GNOME, Ubuntu or another extension isn't
already using it. Modifiers can be stored in any order (`<Shift><Alt>` or
`<Alt><Shift>`), so search for both.

**1. All built-in and system extension shortcuts** (includes default values):

```sh
gsettings list-recursively | grep -iE "shift>.*alt>space|alt>.*shift>space"
```

No output means the key is free. Example for a different key, `Super+M`:

```sh
gsettings list-recursively | grep -iE "<super>m'"
```

**2. Your own custom shortcuts** (Settings → Keyboard → Custom Shortcuts):

```sh
for p in $(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | grep -o "/[^']*/"); do
  gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$p name
  gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$p binding
done
```

**3. User-installed extensions.** Their schemas live inside their own folders,
so step 1 doesn't see them. This finds any shortcut whose value you've changed:

```sh
dconf dump / | grep -iE "shift>.*alt>space|alt>.*shift>space"
```

Default values of user-installed extensions aren't stored in dconf. To check
them too, search the extensions' schema files:

```sh
grep -rilE "shift>.*alt>space|alt>.*shift>space" ~/.local/share/gnome-shell/extensions/*/schemas/*.xml
```

**4. Input method (IBus)** uses its own format, such as `Control+space` or `Shift+Alt+space`:

```sh
gsettings list-recursively org.freedesktop.ibus.general.hotkey
```

You can also browse **Settings → Keyboard → View and Customize Shortcuts**.

### Change the shortcut

Once installed (see below), change it without logging out:

```sh
gsettings --schemadir ~/.local/share/gnome-shell/extensions/ubuntu-workspace-manager@jaidheer007.github.io/schemas \
  set org.gnome.shell.extensions.ubuntu-workspace-manager show-move-to-workspace-menu "['<Super>m']"
```

Read it back with `get` in place of `set ... "[...]"`. To restore the default:

```sh
gsettings --schemadir ~/.local/share/gnome-shell/extensions/ubuntu-workspace-manager@jaidheer007.github.io/schemas \
  reset org.gnome.shell.extensions.ubuntu-workspace-manager show-move-to-workspace-menu
```

## Install

Everything installs for your user only (no `sudo`) to:

```
~/.local/share/gnome-shell/extensions/ubuntu-workspace-manager@jaidheer007.github.io/
```

The folder name must match the `uuid` in `metadata.json`.

### Recommended: `install.sh`

From the repo folder:

```sh
./install.sh                          # default shortcut: Shift+Alt+Space
./install.sh --shortcut '<Super><Alt>m'   # or pick your own
```

The script:

1. Checks that GNOME Shell and the needed tools are present, and warns if your
   GNOME Shell version isn't listed in `metadata.json`.
2. Checks the shortcut against every source listed in
   [Check whether a shortcut is already used](#check-whether-a-shortcut-is-already-used):
   GNOME, Ubuntu, IBus, your custom shortcuts, and other extensions' defaults
   and changed values. Modifier order, case and aliases like `<Ctrl>`,
   `<Control>` and `<Primary>` don't matter.
3. If the shortcut is taken, shows what uses it, suggests some free ones, and
   asks for another. Leave the answer empty to cancel. When not run in a
   terminal, it stops instead and tells you to pass `--shortcut`.
4. Writes your shortcut into the installed schema as its default, compiles the
   schema and checks the result.
5. Copies `extension.js`, `metadata.json`, `LICENSE` and the schema into the
   extension folder. A previous install of this extension is replaced. It
   refuses to touch the folder if it's a symlink or belongs to something else.
6. Adds the extension to GNOME's enabled list.

Running it again is safe. It updates the install, and the shortcut you pick
replaces any you set earlier with `gsettings`.

Then **log out and log back in**. On Wayland, GNOME Shell only finds new
extensions, and loads code changes, at login. Check that it loaded:

```sh
gnome-extensions info ubuntu-workspace-manager@jaidheer007.github.io
```

`State: ACTIVE` means it's working.

### For development: symlink the repo

The installed extension *is* this repo, so edits are picked up at the next login.
Run this from the repo folder (remove an existing install first with `./uninstall.sh`):

```sh
glib-compile-schemas schemas/
mkdir -p ~/.local/share/gnome-shell/extensions
ln -s "$PWD" ~/.local/share/gnome-shell/extensions/ubuntu-workspace-manager@jaidheer007.github.io
```

Log out and back in, then:

```sh
gnome-extensions enable ubuntu-workspace-manager@jaidheer007.github.io
```

The symlink uses the repo's default shortcut. Check it's free first (see
[Check whether a shortcut is already used](#check-whether-a-shortcut-is-already-used)).

## Test safely in a nested shell (optional)

Run the extension in a separate GNOME Shell inside a window, without logging out
and without touching your real session:

```sh
sudo apt install mutter-dev-bin   # once; provides the --devkit viewer
./run-nested.sh
```

Open an app from the nested shell's Activities overview, then try the right-click
menu and `Shift+Alt+Space`. Errors print straight to the terminal. The nested
shell uses throwaway settings, which are deleted when you close it. The script
copies your workspace names, workspace count and dynamic-workspaces setting
into it, so the menu shows the same names as your real session.

## Troubleshooting

- **Watch the shell log** while you enable the extension or open the menu:

  ```sh
  journalctl -f -o cat /usr/bin/gnome-shell
  ```

  Look for `JS ERROR` lines that mention `ubuntu-workspace-manager`.
- **`State: ERROR` or `OUT OF DATE`.** Check the log above. `OUT OF DATE` means
  your GNOME Shell version isn't listed in `metadata.json`'s `shell-version`.
- **Extensions turned off globally?** This command must print `false`:

  ```sh
  gsettings get org.gnome.shell disable-user-extensions
  ```

- **Shortcut does nothing.** Another app or extension may be using the same key
  (see [Check whether a shortcut is already used](#check-whether-a-shortcut-is-already-used)).
  Also check that `schemas/gschemas.compiled` exists in the installed folder.

## Known issues and limitations

- **Relies on a private GNOME API.** The shortcut opens its menu through
  `Main.wm._windowMenuManager`, an internal part of GNOME Shell. It exists in
  GNOME 50, but a future release could rename it. If that happens, the
  shortcut stops working (an error appears in the log) while the right-click
  menu keeps working.
- **GNOME Shell 50 only.** `metadata.json` lists only `"50"`. After a GNOME
  upgrade, the extension shows as `OUT OF DATE` until you test it and add the
  new version.
- **Shortcut conflicts aren't reported.** If another component already uses
  the key, GNOME doesn't warn you; the shortcut just doesn't work, or does the
  other thing.
- **Nested shell keys.** In `run-nested.sh`, keys that your real shell also
  uses (such as `Alt+Space`) go to the real shell, not the test window. You'll
  see the real shell's menu, without this extension. `Shift+Alt+Space` isn't
  used by the real shell, so it reaches the test window.
- **Dynamic workspaces** (if you use them). GNOME always keeps one empty
  workspace at the end, and it appears in the list. Moving a window there makes
  GNOME add another empty one.
- **Workspaces on primary display only.** If that setting is on, windows on
  other monitors are on every workspace, so the menu is hidden for them.
  GNOME's own workspace items behave the same way.
- **"Move to Workspace" is English only.** The submenu title isn't translated.
  Workspace names are yours, and the "Workspace N" fallback comes from GNOME in
  your system language.
- **More workspaces than names.** If you have more workspaces than entries in
  `workspace-names`, the extra ones show as "Workspace N".
- **Code changes need a new login** on Wayland (or use `run-nested.sh`).
  `gnome-extensions disable`/`enable` doesn't reload changed code.

## Uninstall

### Recommended: `uninstall.sh`

```sh
./uninstall.sh       # shows what it will remove and asks first
./uninstall.sh -y    # no question
```

It only touches this extension:

- **Symlink install:** removes just the link, never the repo it points to.
- **Folder install:** first checks that the folder's `metadata.json` has this
  extension's UUID; otherwise it stops without changing anything. It then
  deletes only the files `install.sh` creates. If you added other files, the
  folder and those files are kept, and the script lists them.
- **Settings:** disables the extension and removes its UUID from GNOME's
  `enabled-extensions` and `disabled-extensions` lists. Other extensions'
  entries stay as they are. Resets only
  `/org/gnome/shell/extensions/ubuntu-workspace-manager/`.

Then log out and back in to clear it from the running shell completely.

### Manually

1. Disable it:

   ```sh
   gnome-extensions disable ubuntu-workspace-manager@jaidheer007.github.io
   ```

2. Remove the installed extension.

   - **If you used `install.sh` (a folder):**

     ```sh
     rm -r ~/.local/share/gnome-shell/extensions/ubuntu-workspace-manager@jaidheer007.github.io
     ```

   - **If you used a symlink:** remove only the link. Use plain `rm`,
     **no `-r` and no trailing `/`**, or you may delete this repo's files:

     ```sh
     rm ~/.local/share/gnome-shell/extensions/ubuntu-workspace-manager@jaidheer007.github.io
     ```

   To check which one you have: `ls -ld ~/.local/share/gnome-shell/extensions/ubuntu-workspace-manager@jaidheer007.github.io`.
   A line starting with `l` and showing `->` is a symlink.

3. Optional: remove a custom shortcut you set:

   ```sh
   dconf reset -f /org/gnome/shell/extensions/ubuntu-workspace-manager/
   ```

4. Log out and back in to clear it from the running shell completely.

## License

Copyright (C) 2026 JAIDHEER007

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version. See [`LICENSE`](LICENSE) for the full text.
