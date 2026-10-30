#!/usr/bin/env bash
#
# kanata-layer-watcher
#
# Watches fcitx5's active input method and tells kanata to switch to the
# matching keyboard layer over its TCP IPC interface.
#
# When fcitx5's active IM is English US (keyboard-us), kanata applies the
# Programmer Dvorak layout. Every other IM (Cangjie, Quick, Chinese and so on)
# expects physical QWERTY, so kanata passes keys through.
#
#   keyboard-us  -> base   (Programmer Dvorak)
#   anything else -> qwerty (physical QWERTY passthrough)
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
        keyboard-us)  echo "base" ;;
        *)            echo "qwerty" ;;
    esac
}

KANATA_UNIT="kanata.service"
KANATA_DEVICE_NAME="kanata"
KEY_A_BIT=$((1 << 30))
GUARD_INTERVAL_SEC=2
GUARD_MISS_LIMIT=2
GUARD_RESTART_COOLDOWN_SEC=60
LAST_GUARD_SEC=0
LAST_RESTART_SEC=0
MISS_COUNT=0
MISSED_PREVIOUS=""
KANATA_PID=""

kanata_pid() {
    local pid process_name=""
    if [[ -n "$KANATA_PID" ]]; then
        { read -r process_name < "/proc/$KANATA_PID/comm"; } 2>/dev/null
        if [[ "$process_name" == "${KANATA_DEVICE_NAME}"* ]]; then
            printf '%s\n' "$KANATA_PID"
            return 0
        fi
    fi
    pid="$(systemctl --user show --property MainPID --value "$KANATA_UNIT")"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    KANATA_PID="$pid"
    printf '%s\n' "$pid"
}

is_keyboard_node() {
    local node="$1" device name capabilities last_word
    device="/sys/class/input/${node##*/}/device"
    [[ -r "$device/name" && -r "$device/capabilities/key" ]] || return 1
    name="$(< "$device/name")"
    [[ "$name" == "$KANATA_DEVICE_NAME" ]] && return 1
    capabilities="$(< "$device/capabilities/key")"
    last_word="${capabilities##* }"
    (( 16#${last_word:-0} & KEY_A_BIT ))
}

ungrabbed_keyboards() {
    local pid held_fd target node
    local -A held=()
    pid="$(kanata_pid)" || return 0
    for held_fd in /proc/"$pid"/fd/*; do
        target="$(readlink "$held_fd" 2>/dev/null)"
        [[ "$target" == /dev/input/event* ]] && held["$target"]=1
    done
    for node in /dev/input/event*; do
        is_keyboard_node "$node" || continue
        [[ -n "${held[$node]:-}" ]] && continue
        printf '%s\n' "$node"
    done
}

restart_kanata() {
    echo "kanata-layer-watcher: kanata holds no grab on [$1]; restarting $KANATA_UNIT" >&2
    [[ -n "$IPC_FD" ]] && exec {IPC_FD}>&-
    IPC_FD=""
    CUR_LAYER=""
    KANATA_PID=""
    systemctl --user restart "$KANATA_UNIT" || return 1
    connect_kanata || return 1
    force_layer "$(layer_for_im "$(fcitx5-remote -n 2>/dev/null)")" || CUR_LAYER=""
}

guard_keyboard_grabs() {
    local now missed
    printf -v now '%(%s)T' -1
    (( now - LAST_GUARD_SEC >= GUARD_INTERVAL_SEC )) || return 0
    LAST_GUARD_SEC="$now"

    missed="$(ungrabbed_keyboards)"
    if [[ -z "$missed" ]]; then
        MISS_COUNT=0
        MISSED_PREVIOUS=""
        return 0
    fi
    if [[ "$missed" == "$MISSED_PREVIOUS" ]]; then
        MISS_COUNT=$((MISS_COUNT + 1))
    else
        MISS_COUNT=1
        MISSED_PREVIOUS="$missed"
    fi
    (( MISS_COUNT >= GUARD_MISS_LIMIT )) || return 0
    (( now - LAST_RESTART_SEC >= GUARD_RESTART_COOLDOWN_SEC )) || return 0

    LAST_RESTART_SEC="$now"
    MISS_COUNT=0
    MISSED_PREVIOUS=""
    restart_kanata "${missed//$'\n'/, }"
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
    guard_keyboard_grabs
    sleep 0.05
done
