import re

from kittens.tui.handler import result_handler

from kitty.key_encoding import KeyEvent, parse_shortcut


def is_window_among_procs(window, proc_list):
    # See if the window's foreground process matches any in the proc_list
    fp = window.child.foreground_processes[0]["cmdline"]
    for proc in proc_list:
        if proc in fp[0]:
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
    proc_str_csv = args[3] if len(args) > 3 else "vim,nvim,ssh,zellij"
    proc_list = proc_str_csv.split(",")
    # print(f"Processes to check: {proc_list}")

    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return

    # if the window is running one of the specified processes, send the key mapping to it
    if is_window_among_procs(window, proc_list):
        for keymap in key_mapping.split(">"):
            encoded = encode_key_mapping(window, keymap)
            window.write_to_child(encoded)
    else:
        # else, switch to the neighboring window in the specified direction
        boss.active_tab.neighboring_window(direction)
