"""Kitty kitten for seamless navigation between Kitty panes and Neovim splits.

This kitten intercepts navigation keys (e.g., Ctrl+Arrow) and decides whether to:
1. Forward the key to Neovim (if an editor is detected via user variables)
2. Switch to a neighboring Kitty pane (if no editor is active)

Usage in kitty.conf:
    map ctrl+left  kitten pass_keys.py left  ctrl+left  "in_editor"
    map ctrl+down  kitten pass_keys.py bottom ctrl+down "in_editor"
    map ctrl+up    kitten pass_keys.py top   ctrl+up    "in_editor"
    map ctrl+right kitten pass_keys.py right ctrl+right "in_editor"

Arguments:
    direction   : Kitty direction (left, right, top, bottom)
    key_mapping : Key sequence to forward to the editor (e.g., "ctrl+left")
    var_names   : Comma-separated user variable names to check (default: "in_editor")
"""

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
    """Convert a key mapping string to encoded bytes for the terminal.

    Takes a human-readable key combo (e.g., "ctrl+left") and converts it to
    the escape sequence that Kitty sends to the terminal application.

    Args:
        window: The Kitty window to encode for
        key_mapping: Key combo string (e.g., "ctrl+left", "ctrl+shift+h")

    Returns:
        Encoded bytes representing the key event
    """
    mods, key = parse_shortcut(key_mapping)
    # Build KeyEvent with explicit modifier flags
    # Modifier bitmask: shift=1, alt=2, ctrl=4, super=8, hyper=16, meta=32
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
    """Required entry point for Kitty kittens (unused, logic is in handle_result)."""
    pass


@result_handler(no_ui=True)
def handle_result(args, result, target_window_id, boss):
    """Main handler called by Kitty when the kitten is invoked.

    This is the entry point when a mapped key triggers pass_keys.py.
    Kitty calls this with the parsed arguments from kitty.conf.

    Args:
        args: List of arguments [script_name, direction, key_mapping, var_names?]
        result: Unused (required by Kitty's result_handler interface)
        target_window_id: ID of the window where the key was pressed
        boss: Kitty's Boss object for window/tab management
    """
    direction = args[1]
    key_mapping = args[2]

    # Parse variable names from args (comma-separated, default: "in_editor")
    # Multiple variables can be specified: "in_editor,in_vim,in_neovim"
    var_names_csv = args[3] if len(args) > 3 else "in_editor"
    var_names = [name.strip() for name in var_names_csv.split(",") if name.strip()]

    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    if is_window_running_an_editor(window, var_names):
        # Editor is active: forward the key to Neovim so it can handle navigation
        # The ">" separator allows sending multiple keys (rarely needed)
        for keymap in key_mapping.split(">"):
            encoded = encode_key_mapping(window, keymap)
            window.write_to_child(encoded)
    else:
        # No editor detected: use Kitty's native pane navigation
        boss.active_tab.neighboring_window(direction)
