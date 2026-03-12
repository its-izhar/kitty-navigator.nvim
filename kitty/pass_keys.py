from kittens.tui.handler import result_handler

from kitty.key_encoding import KeyEvent, parse_shortcut


def is_window_running_an_editor(window, var_names):
    """Check if any of the specified user variables are set in the window.

    We only check for variable existence, not value. This is intentional:
    - Neovim sets the var with a value (e.g., "in_editor=1") on VimEnter
    - Neovim unsets by sending just the name (e.g., "in_editor") on VimLeave
    - Kitty removes the variable entirely when unset, so existence = editor active
    """
    if len(window.user_vars) == 0:
        return False
    for var_name in var_names:
        if var_name in window.user_vars:
            return True
    return False


def encode_key_mapping(window, key_mapping):
    mods, key = parse_shortcut(key_mapping)
    event = KeyEvent(
        mods=mods,
        key=key,
        shift=bool(mods & 1),
        alt=bool(mods & 2),
        ctrl=bool(mods & 4),
        super=bool(mods & 8),
        hyper=bool(mods & 16),
        meta=bool(mods & 32),
    ).as_window_system_event()

    return window.encoded_key(event)


def main():
    pass


@result_handler(no_ui=True)
def handle_result(args, result, target_window_id, boss):
    direction = args[1]
    key_mapping = args[2]
    # Parse variable names from args (comma-separated, default: "in_editor")
    var_names_csv = args[3] if len(args) > 3 else "in_editor"
    var_names = [name.strip() for name in var_names_csv.split(",") if name.strip()]

    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    # if the window is running one of the specified processes, send the key mapping to it
    ## if is_window_among_procs(window, proc_list, win_title_list):
    if is_window_running_an_editor(window, var_names):
        for keymap in key_mapping.split(">"):
            encoded = encode_key_mapping(window, keymap)
            window.write_to_child(encoded)
    else:
        # else, switch to the neighboring window in the specified direction
        boss.active_tab.neighboring_window(direction)
