#!/usr/bin/env bash
# parse-keybindings.sh — Parse compositor keybinding configs and emit JSON
#
# Usage:
#   parse-keybindings.sh COMPOSITOR [CONFIG_PATH] [EXTRA_FILES_CSV]
#
# COMPOSITOR:      hyprland | mangowc | sway | niri
# CONFIG_PATH:     path to main config (default: compositor default path)
# EXTRA_FILES_CSV: comma-separated additional files to parse
#
# Output: JSON object { "sections": [ { "id", "name", "bindings": [ { "key", "description" } ] } ] }

set -euo pipefail

# ── Args ───────────────────────────────────────────────────────────────────────
COMPOSITOR="${1:-}"
ARG_CONFIG_PATH="${2:-}"
ARG_EXTRA_FILES="${3:-}"

if [[ -z "$COMPOSITOR" ]]; then
    printf '{"error":"compositor argument required","sections":[]}\n'
    exit 1
fi

HOME_DIR="${HOME:-$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6 || echo "/root")}"

# ── Output accumulator ─────────────────────────────────────────────────────────
# Each entry: "SECTION:<name>" or "BIND:<key>|||<description>"
declare -a OUTPUT=()

# ── Utilities ──────────────────────────────────────────────────────────────────

expand_path() {
    local p="${1:-}" base_dir="${2:-}"
    p="${p/#\~/$HOME_DIR}"
    # Resolve relative paths against the directory of the referencing file
    if [[ -n "$base_dir" ]] && [[ "$p" != /* ]]; then
        p="${base_dir}/${p}"
    fi
    echo "$p"
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

make_id() {
    echo "${1,,}" | sed 's/[^a-z0-9]/_/g; s/__*/_/g; s/^_//; s/_$//'
}

emit_section() {
    local name
    name="$(trim "$1")"
    [[ -n "$name" ]] && OUTPUT+=("SECTION:$name")
}

emit_bind() {
    local key="$1" desc="$2"
    [[ -n "$key" ]] && OUTPUT+=("BIND:${key}|||${desc}")
}

# ── Hyprland / MangoWC parser ──────────────────────────────────────────────────
# Format:
#   $VAR = VALUE
#   bind[flags] = MOD, KEY, dispatcher[, params]
#   source = /path/to/extra.conf
#   # @section Name   ← explicit section marker (plain comments are ignored)

parse_hyprland() {
    # Uses index-based queue so appending inside the loop works
    local -a queue=("$@")
    local -A seen=()
    local -A vars=()
    local idx=0

    while [[ $idx -lt ${#queue[@]} ]]; do
        local file="${queue[$idx]}"
        (( idx++ )) || true

        [[ -n "${seen["$file"]:-}" ]] && continue
        seen["$file"]=1
        [[ ! -f "$file" ]] && continue

        local ignoring=false
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            # Strip leading whitespace only (preserve inline content)
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$line" ]] && continue

            # Ignore block markers
            [[ "$line" =~ ^#[[:space:]]*@ignore([[:space:]]|$) ]]     && ignoring=true  && continue
            [[ "$line" =~ ^#[[:space:]]*@end-ignore([[:space:]]|$) ]] && ignoring=false && continue
            $ignoring && continue

            # Variable definition: $VAR = VALUE
            if [[ "$line" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                vars["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]% }"
                continue
            fi

            # Source include: source = PATH
            if [[ "$line" =~ ^[Ss]ource[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                local src="${BASH_REMATCH[1]%% *}"
                local file_dir
                file_dir="$(dirname "$file")"
                src="$(expand_path "$src" "$file_dir")"
                # Resolve variables in path
                for v in "${!vars[@]}"; do
                    src="${src//\$$v/${vars[$v]}}"
                done
                queue+=("$src")
                continue
            fi

            # Section marker: # @section Name
            if [[ "$line" =~ ^#[[:space:]]*@section[[:space:]]+(.+)$ ]]; then
                emit_section "${BASH_REMATCH[1]}"
                continue
            fi

            # bind[flags] = MOD, KEY, DISPATCHER[, PARAMS]
            # flags: l (locked), r (release), e (repeat), t (transparent), m (mouse), n (non-consuming)
            if [[ "$line" =~ ^bind[a-z]*[[:space:]]*=[[:space:]]*([^,#]*),([^,#]*),([^,#]*),?([^#]*)$ ]]; then
                local mod key disp params
                mod="$(trim "${BASH_REMATCH[1]}")"
                key="$(trim "${BASH_REMATCH[2]}")"
                disp="$(trim "${BASH_REMATCH[3]}")"
                params="$(trim "${BASH_REMATCH[4]}")"

                # Resolve variables
                for v in "${!vars[@]}"; do
                    mod="${mod//\$$v/${vars[$v]}}"
                    key="${key//\$$v/${vars[$v]}}"
                    params="${params//\$$v/${vars[$v]}}"
                done

                local combo desc
                [[ -n "$mod" ]] && combo="${mod} + ${key}" || combo="$key"
                [[ -n "$params" ]] && desc="${disp} ${params}" || desc="$disp"

                emit_bind "$(trim "$combo")" "$(trim "$desc")"
            fi

        done < "$file"
    done
}

# ── Sway parser ────────────────────────────────────────────────────────────────
# Format:
#   set $VAR value
#   bindsym [--flags] MOD+KEY action
#   include /path/to/file

parse_sway() {
    local -a queue=("$@")
    local -A seen=()
    local -A vars=()
    local idx=0

    while [[ $idx -lt ${#queue[@]} ]]; do
        local file="${queue[$idx]}"
        (( idx++ )) || true

        [[ -n "${seen["$file"]:-}" ]] && continue
        seen["$file"]=1
        [[ ! -f "$file" ]] && continue

        local ignoring=false
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$line" ]] && continue

            # Ignore block markers
            [[ "$line" =~ ^#[[:space:]]*@ignore([[:space:]]|$) ]]     && ignoring=true  && continue
            [[ "$line" =~ ^#[[:space:]]*@end-ignore([[:space:]]|$) ]] && ignoring=false && continue
            $ignoring && continue

            # set $VAR value
            if [[ "$line" =~ ^set[[:space:]]+\$([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(.+)$ ]]; then
                vars["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]%% #*}"
                continue
            fi

            # include path
            if [[ "$line" =~ ^include[[:space:]]+(.+)$ ]]; then
                local inc="${BASH_REMATCH[1]%% #*}"
                local file_dir
                file_dir="$(dirname "$file")"
                inc="$(expand_path "$(trim "$inc")" "$file_dir")"
                for v in "${!vars[@]}"; do
                    inc="${inc//\$$v/${vars[$v]}}"
                done
                # include supports globs — expand if possible
                # shellcheck disable=SC2206
                local -a expanded=($inc)
                for f in "${expanded[@]}"; do
                    queue+=("$f")
                done
                continue
            fi

            # Section marker: # @section Name
            if [[ "$line" =~ ^#[[:space:]]*@section[[:space:]]+(.+)$ ]]; then
                emit_section "${BASH_REMATCH[1]}"
                continue
            fi

            # bindsym [--flag ...] KEY action
            if [[ "$line" =~ ^bindsym[[:space:]]+(.+)$ ]]; then
                local rest="${BASH_REMATCH[1]}"

                # Strip optional flags: --to-code, --whole-window, --locked, --release, --no-warn
                while [[ "$rest" =~ ^--[^[:space:]]+[[:space:]]+(.+)$ ]]; do
                    rest="${BASH_REMATCH[1]}"
                done

                if [[ "$rest" =~ ^([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local action="${BASH_REMATCH[2]%% #*}"

                    for v in "${!vars[@]}"; do
                        key="${key//\$$v/${vars[$v]}}"
                        action="${action//\$$v/${vars[$v]}}"
                    done

                    emit_bind "$key" "$(trim "$action")"
                fi
            fi

        done < "$file"
    done
}

# ── Niri parser ────────────────────────────────────────────────────────────────
# Format (KDL):
#   binds {
#       Mod+Key allow-inhibiting=false { action "arg1" "arg2"; }
#       Mod+Key { action; }
#   }
#   include "path/to/file.kdl"
#   // Section comment (inside binds block)

parse_niri() {
    local -a files=("$@")

    for file in "${files[@]}"; do
        [[ ! -f "$file" ]] && continue

        local in_binds=false
        local brace_depth=0
        local pending_line=""
        local ignoring=false

        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            local trimmed="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$trimmed" ]] && continue

            # include directive (outside binds)
            if ! $in_binds && [[ "$trimmed" =~ ^include[[:space:]]+\"([^\"]+)\" ]]; then
                local inc file_dir
                file_dir="$(dirname "$file")"
                inc="$(expand_path "${BASH_REMATCH[1]}" "$file_dir")"
                parse_niri "$inc"
                continue
            fi

            # Enter binds block
            if [[ "$trimmed" == "binds {" ]] || [[ "$trimmed" =~ ^binds[[:space:]]*\{ ]]; then
                in_binds=true
                brace_depth=1
                continue
            fi

            $in_binds || continue

            # Track brace depth to know when binds block ends
            local opens="${trimmed//[^\{]/}"
            local closes="${trimmed//[^\}]/}"
            local delta=$(( ${#opens} - ${#closes} ))

            # Pure closing brace — exits binds block
            if [[ "$trimmed" == "}" ]]; then
                (( brace_depth-- )) || true
                if [[ $brace_depth -le 0 ]]; then
                    in_binds=false
                    brace_depth=0
                fi
                continue
            fi

            # Ignore block markers (inside binds)
            [[ "$trimmed" =~ ^//[[:space:]]*@ignore([[:space:]]|$) ]]     && ignoring=true  && continue
            [[ "$trimmed" =~ ^//[[:space:]]*@end-ignore([[:space:]]|$) ]] && ignoring=false && continue
            $ignoring && continue

            # Section marker inside binds: // @section Name
            if [[ "$trimmed" =~ ^//[[:space:]]*@section[[:space:]]+(.+)$ ]]; then
                emit_section "${BASH_REMATCH[1]}"
                continue
            fi

            # Accumulate multi-line bind entries (rare but possible)
            local full_line="${pending_line}${trimmed}"
            pending_line=""

            # Bind line: Key+Combo [option=val ...] { action "args"; }
            # The combo is the first token (letters, digits, + - _)
            if [[ "$full_line" =~ ^([A-Za-z0-9_+\-]+)[[:space:]]*(.*)\{[[:space:]]*([^\}]*)\} ]]; then
                local combo="${BASH_REMATCH[1]}"
                local action_block="${BASH_REMATCH[3]}"

                # action_block: e.g.  spawn "alacritty"  or  close-window
                # Strip trailing semicolon and quotes
                action_block="$(trim "${action_block%;}")"
                action_block="${action_block//\"/}"
                action_block="$(trim "$action_block")"

                emit_bind "$combo" "$action_block"
            elif [[ "$full_line" =~ ^[A-Za-z0-9_+\-]+ ]] && [[ ! "$full_line" =~ \} ]]; then
                # Line doesn't have closing brace yet — carry to next line
                pending_line="${full_line} "
            fi

            # Adjust depth for lines that opened nested blocks
            (( brace_depth += delta )) || true

        done < "$file"
    done
}

# ── Default config paths ───────────────────────────────────────────────────────

default_config_path() {
    case "$1" in
        hyprland) echo "${HOME_DIR}/.config/hypr/hyprland.conf" ;;
        mangowc)  echo "${HOME_DIR}/.config/mango/config.conf" ;;
        sway)     echo "${HOME_DIR}/.config/sway/config" ;;
        niri)     echo "${HOME_DIR}/.config/niri/config.kdl" ;;
        *)        echo "" ;;
    esac
}

# ── JSON emitter ───────────────────────────────────────────────────────────────

emit_json() {
    local -a section_names=()
    local -a section_ids=()
    local -A section_bindings=()  # id → newline-separated "key|||desc" lines
    local -A id_counts=()
    local current_id=""
    local current_name=""

    for item in "${OUTPUT[@]}"; do
        if [[ "$item" == SECTION:* ]]; then
            current_name="${item#SECTION:}"
            local base_id
            base_id="$(make_id "$current_name")"
            local count="${id_counts["$base_id"]:-0}"
            if [[ $count -eq 0 ]]; then
                # First occurrence — register new section
                current_id="$base_id"
                id_counts["$base_id"]=1
                section_names+=("$current_name")
                section_ids+=("$current_id")
                section_bindings["$current_id"]=""
            else
                # Duplicate name — merge into existing section
                current_id="$base_id"
            fi

        elif [[ "$item" == BIND:* ]]; then
            if [[ -z "$current_id" ]]; then
                current_name="General"
                current_id="general"
                id_counts["general"]=$(( ${id_counts["general"]:-0} + 1 ))
                section_names+=("$current_name")
                section_ids+=("$current_id")
                section_bindings["$current_id"]=""
            fi
            local entry="${item#BIND:}"
            if [[ -z "${section_bindings["$current_id"]}" ]]; then
                section_bindings["$current_id"]="$entry"
            else
                section_bindings["$current_id"]+=$'\n'"$entry"
            fi
        fi
    done

    # Build JSON
    printf '{"sections":['
    local first_section=true

    for i in "${!section_ids[@]}"; do
        local sid="${section_ids[$i]}"
        local sname="${section_names[$i]}"
        local bindings_raw="${section_bindings["$sid"]:-}"

        # Skip sections with no bindings
        [[ -z "$bindings_raw" ]] && continue

        $first_section || printf ','
        first_section=false

        printf '{"id":"%s","name":"%s","bindings":[' \
            "$(json_escape "$sid")" "$(json_escape "$sname")"

        local first_bind=true
        while IFS= read -r binding; do
            [[ -z "$binding" ]] && continue
            local bkey="${binding%%|||*}"
            local bdesc="${binding#*|||}"
            $first_bind || printf ','
            first_bind=false
            printf '{"key":"%s","description":"%s"}' \
                "$(json_escape "$bkey")" "$(json_escape "$bdesc")"
        done <<< "$bindings_raw"

        printf ']}'
    done

    printf ']}'$'\n'
}

# ── Main ───────────────────────────────────────────────────────────────────────

# Resolve config path
CONFIG_PATH="${ARG_CONFIG_PATH:-$(default_config_path "$COMPOSITOR")}"
CONFIG_PATH="$(expand_path "$CONFIG_PATH")"

# Build file list: main config + extras
declare -a FILES=("$CONFIG_PATH")
if [[ -n "$ARG_EXTRA_FILES" ]]; then
    IFS=',' read -ra extras <<< "$ARG_EXTRA_FILES"
    for extra in "${extras[@]}"; do
        extra="$(trim "$extra")"
        extra="$(expand_path "$extra")"
        [[ -n "$extra" ]] && FILES+=("$extra")
    done
fi

case "$COMPOSITOR" in
    hyprland|mangowc)
        parse_hyprland "${FILES[@]}"
        ;;
    sway)
        parse_sway "${FILES[@]}"
        ;;
    niri)
        parse_niri "${FILES[@]}"
        ;;
    *)
        printf '{"error":"unknown compositor: %s","sections":[]}\n' "$(json_escape "$COMPOSITOR")"
        exit 1
        ;;
esac

emit_json
