// SPDX-License-Identifier: GPL-2.0-or-later

import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {WindowMenu} from 'resource:///org/gnome/shell/ui/windowMenu.js';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

// Set while the shortcut opens the menu, so _buildMenu shows only the workspace list.
let workspacesOnly = false;

export default class UbuntuWorkspaceManagerExtension extends Extension {
    enable() {
        this._injections = new InjectionManager();
        this._injections.overrideMethod(WindowMenu.prototype, '_buildMenu', original => {
            return function (window) {
                if (workspacesOnly) {
                    addWorkspaceItems(this, window);
                    return;
                }
                original.call(this, window);
                addWorkspaceSubmenu(this, window);
            };
        });

        Main.wm.addKeybinding('show-move-to-workspace-menu', this.getSettings(),
            Meta.KeyBindingFlags.NONE, Shell.ActionMode.NORMAL, showWorkspaceMenu);
    }

    disable() {
        Main.wm.removeKeybinding('show-move-to-workspace-menu');
        this._injections.clear();
        this._injections = null;
    }
}

function canMove(window) {
    return Main.sessionMode.hasWorkspaces &&
        global.workspace_manager.get_n_workspaces() > 1 &&
        !window.is_on_all_workspaces();
}

function addWorkspaceItems(menu, window) {
    const wm = global.workspace_manager;
    const current = window.get_workspace().index();
    for (let i = 0; i < wm.get_n_workspaces(); i++) {
        // Custom name (e.g. set via Workspace Indicator), else "Workspace N".
        const item = menu.addAction(Meta.prefs_get_workspace_name(i), () => {
            window.change_workspace(wm.get_workspace_by_index(i));
        });
        item.setOrnament(i === current ? PopupMenu.Ornament.DOT : PopupMenu.Ornament.NO_DOT);
        item.setSensitive(i !== current);
    }
}

function addWorkspaceSubmenu(menu, window) {
    if (!canMove(window))
        return;

    const submenu = new PopupMenu.PopupSubMenuMenuItem('Move to Workspace');
    submenu.setOrnament(PopupMenu.Ornament.NONE); // align with sibling items
    addWorkspaceItems(submenu.menu, window);

    // The workspace items are the last block before the first separator.
    const items = menu._getMenuItems();
    const separator = items.findIndex(i => i instanceof PopupMenu.PopupSeparatorMenuItem);
    menu.addMenuItem(submenu, separator === -1 ? undefined : separator);
}

function showWorkspaceMenu() {
    const window = global.display.focus_window;
    if (!window || !canMove(window))
        return;

    // Open at the window's top-left corner, like Alt+Space.
    const {x, y} = window.get_frame_rect();
    workspacesOnly = true;
    try {
        Main.wm._windowMenuManager.showWindowMenuForWindow(window,
            Meta.WindowMenuType.WM, {x, y, width: 0, height: 0});
    } finally {
        workspacesOnly = false;
    }
}
