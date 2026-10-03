#!/usr/bin/env bash
#
# kanata-layer-watcher
#
# Watches fcitx5's active input method and tells kanata to switch to the
# matching keyboard layer over its TCP IPC interface.
#
# fcitx5's English IM (keyboard-us) uses a plain US layout, so kanata must
# apply Programmer Dvorak when it is active. Cangjie expects physical QWERTY,
# so kanata must pass keys through when cangjie3 is active.
#
#   keyboard-us  -> base    (Programmer Dvorak)
#   cangjie3     -> cangjie (physical QWERTY, so Cangjie sees QWERTY keys)
#   anything else -> base
#
# kanata MUST be started with a TCP port (e.g. --port 17000).
set -u

KANATA_PORT="${KANATA_PORT:-17000}"
CUR_LAYER=""
IPC_FD=""

# --------------------------------------------------------------------------
# kanata IPC
#
# kanata's TCP protocol is newline-delimited JSON. The connection is held open
# for the lifetime of the watcher: kanata coalesces changes that arrive over
# separate short-lived connections, and a fresh connection also races kanata's
# device scan on startup.
# --------------------------------------------------------------------------

# connect_kanata -- open the persistent IPC connection, waiting for kanata to
# be ready. Connecting succeeds only once kanata is accepting IPC clients.
#
# The connect runs inside a braces group with fd 2 silenced: bash reports a
# failed /dev/tcp redirect itself, and that message is not silenced by
# redirecting the command's stderr.
connect_kanata() {
    while :; do
        if { exec {IPC_FD}<>"/dev/tcp/127.0.0.1/${KANATA_PORT}"; } 2>/dev/null; then
            # Drain the initial LayerChange event kanata sends on connect.
            IFS= read -r -t 1 _line <&"$IPC_FD" 2>/dev/null
            return 0
        fi
        IPC_FD=""
        sleep 0.1
    done
}

# send_raw <layer> -- write a ChangeLayer request on the open connection.
send_raw() {
    printf '{"ChangeLayer":{"new":"%s"}}\n' "$1" >&"$IPC_FD" 2>/dev/null || {
        # The connection dropped (kanata restarted); reconnect and retry once.
        IPC_FD=""
        connect_kanata || return 1
        printf '{"ChangeLayer":{"new":"%s"}}\n' "$1" >&"$IPC_FD" 2>/dev/null
    }
}

# current_layer -- ask kanata which layer it is really on.
# Prints the layer name, or returns non-zero if kanata did not answer in time.
# Pending unsolicited LayerChange events are drained first so the line we read
# is the reply to our request, not an echo of a change we just sent.
current_layer() {
    local line name
    while IFS= read -r -t 0.01 _line <&"$IPC_FD" 2>/dev/null; do :; done
    printf '{"RequestCurrentLayerName":{}}\n' >&"$IPC_FD" 2>/dev/null || return 1
    IFS= read -r -t 1 line <&"$IPC_FD" 2>/dev/null || return 1
    name="${line##*\"name\":\"}"
    name="${name%%\"*}"
    [[ -n "$name" ]] || return 1
    printf '%s\n' "$name"
}

send_layer() {
    local layer="$1"
    if [[ "$layer" == "$CUR_LAYER" ]]; then
        return
    fi
    if send_raw "$layer"; then
        echo "kanata-layer-watcher: switched to '$layer'" >&2
        CUR_LAYER="$layer"
    fi
}

# force_layer <layer> -- make kanata actually enter <layer>, and keep trying
# until kanata confirms it has stuck.
#
# kanata opens its IPC port while it is still registering input devices and
# only "starts kanata proper" afterwards; a layer change sent during that window
# is discarded when the initial state is applied a moment later. Worse, a
# ChangeLayer for the layer kanata already starts on (`base`, its first deflayer)
# is a no-op, so a freshly-started session would never apply `base` at all.
#
# Bounce through a different layer first so the target is a real transition,
# then read the layer back and confirm it is still the target after a settle
# long enough to outlast kanata's startup reset (measured at ~0.5s between the
# port opening and "Starting kanata proper"). A change that survives the settle
# has outlived that reset; anything caught by it fails the check and is retried,
# so the exact startup time does not have to be known in advance.
force_layer() {
    local layer="$1"
    local bounce="qwerty"
    [[ "$layer" == "qwerty" ]] && bounce="base"

    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        send_raw "$bounce" || return 1
        sleep 0.05
        send_raw "$layer" || return 1
        sleep 0.7
        if [[ "$(current_layer)" == "$layer" ]]; then
            echo "kanata-layer-watcher: forced layer '$layer'" >&2
            CUR_LAYER="$layer"
            return 0
        fi
    done
    echo "kanata-layer-watcher: could not force layer '$layer'" >&2
    return 1
}

layer_for_im() {
    case "$1" in
        cangjie3)  echo "cangjie" ;;
        *)         echo "base" ;;
    esac
}

# Initial sync: connect, then force the layer so it is applied even if kanata
# booted straight into that same layer.
connect_kanata || exit 1
im="$(fcitx5-remote -n 2>/dev/null)"
force_layer "$(layer_for_im "$im")" || CUR_LAYER=""

# Poll for changes.
while true; do
    im="$(fcitx5-remote -n 2>/dev/null)"
    send_layer "$(layer_for_im "$im")"
    sleep 0.05
done
