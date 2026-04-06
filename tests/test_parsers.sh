#!/usr/bin/env bash
# tests/test_parsers.sh — Test suite for parse-keybindings.sh
#
# Usage: ./tests/test_parsers.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="${SCRIPT_DIR}/../parse-keybindings.sh"
FIXTURES="${SCRIPT_DIR}/fixtures"

VERBOSE="${1:-}"
PASS=0
FAIL=0
ERRORS=()

# ── Helpers ────────────────────────────────────────────────────────────────────

run_parser() {
    local compositor="$1" config="$2" extras="${3:-}"
    bash "$PARSER" "$compositor" "$config" "$extras" 2>/dev/null
}

assert_contains() {
    local name="$1" output="$2" expected="$3"
    if echo "$output" | grep -qF "$expected"; then
        (( PASS++ )) || true
        [[ "$VERBOSE" == "--verbose" ]] && echo "  PASS: $name"
    else
        (( FAIL++ )) || true
        ERRORS+=("$name — expected: $expected")
        echo "  FAIL: $name"
        echo "        expected:  $expected"
        [[ "$VERBOSE" == "--verbose" ]] && echo "        in output: $output"
    fi
}

assert_not_contains() {
    local name="$1" output="$2" unexpected="$3"
    if ! echo "$output" | grep -qF "$unexpected"; then
        (( PASS++ )) || true
        [[ "$VERBOSE" == "--verbose" ]] && echo "  PASS: $name"
    else
        (( FAIL++ )) || true
        ERRORS+=("$name — unexpected: $unexpected")
        echo "  FAIL: $name"
        echo "        unexpected: $unexpected"
    fi
}

assert_json_valid() {
    local name="$1" output="$2"
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        (( PASS++ )) || true
        [[ "$VERBOSE" == "--verbose" ]] && echo "  PASS: $name"
    else
        (( FAIL++ )) || true
        ERRORS+=("$name — invalid JSON")
        echo "  FAIL: $name — invalid JSON"
        [[ "$VERBOSE" == "--verbose" ]] && echo "        output: $output"
    fi
}

section() { echo ""; echo "── $* ──────────────────────────────────────────────"; }

# ── Hyprland ───────────────────────────────────────────────────────────────────

section "Hyprland"
H="$(run_parser hyprland "${FIXTURES}/hyprland.conf")"

assert_json_valid  "hyprland: valid JSON"                        "$H"
assert_contains    "hyprland: has sections key"                  "$H" '"sections"'
assert_contains    "hyprland: resolves \$mainMod → SUPER"        "$H" 'SUPER'
assert_contains    "hyprland: resolves \$terminal → alacritty"   "$H" 'alacritty'
assert_contains    "hyprland: resolves \$browser → firefox"      "$H" 'firefox'
assert_contains    "hyprland: Applications section"              "$H" '"Applications"'
assert_contains    "hyprland: Windows section"                   "$H" '"Windows"'
assert_contains    "hyprland: Focus section"                     "$H" '"Focus"'
assert_contains    "hyprland: killactive binding"                "$H" 'killactive'
assert_contains    "hyprland: movefocus binding"                 "$H" 'movefocus'
assert_contains    "hyprland: empty-mod key (Print)"             "$H" 'Print'
assert_contains    "hyprland: MOD + KEY format"                  "$H" 'SUPER + Return'
assert_contains    "hyprland: shifted combo"                     "$H" 'SUPER SHIFT + Space'

# source = include
assert_contains    "hyprland: loads sourced file"                "$H" '"Workspaces"'
assert_contains    "hyprland: workspace binding from source"     "$H" 'workspace'
assert_contains    "hyprland: mouse bind from source"            "$H" 'movewindow'

# Plain comments must NOT become sections
assert_not_contains "hyprland: plain comments ignored"           "$H" '"Hyprland test fixture"'

# ── MangoWC ────────────────────────────────────────────────────────────────────

section "MangoWC"
M="$(run_parser mangowc "${FIXTURES}/mango.conf")"

assert_json_valid  "mangowc: valid JSON"                         "$M"
assert_contains    "mangowc: resolves \$mainMod → SUPER"         "$M" 'SUPER'
assert_contains    "mangowc: Applications section"               "$M" '"Applications"'
assert_contains    "mangowc: Window Management section"          "$M" '"Window Management"'
assert_contains    "mangowc: Workspaces section"                 "$M" '"Workspaces"'
assert_contains    "mangowc: alacritty binding"                  "$M" 'alacritty'
assert_contains    "mangowc: killactive binding"                 "$M" 'killactive'
assert_contains    "mangowc: workspace binding"                  "$M" 'workspace'

# ── Sway ───────────────────────────────────────────────────────────────────────

section "Sway"
S="$(run_parser sway "${FIXTURES}/sway.conf")"

assert_json_valid  "sway: valid JSON"                            "$S"
assert_contains    "sway: resolves \$mod → Mod4"                 "$S" 'Mod4'
assert_contains    "sway: resolves \$term → alacritty"           "$S" 'alacritty'
assert_contains    "sway: Applications section"                  "$S" '"Applications"'
assert_contains    "sway: Window Management section"             "$S" '"Window Management"'
assert_contains    "sway: Focus section"                         "$S" '"Focus"'
assert_contains    "sway: Workspaces section"                    "$S" '"Workspaces"'
assert_contains    "sway: kill binding"                          "$S" 'kill'
assert_contains    "sway: focus binding"                         "$S" 'focus'
assert_contains    "sway: workspace binding"                     "$S" 'workspace'
assert_not_contains "sway: --to-code not in key field"           "$S" '"--to-code'
assert_contains    "sway: --locked bind included"                "$S" 'playerctl'

# include
assert_contains    "sway: loads included file"                   "$S" '"Media"'
assert_contains    "sway: XF86 keys from include"                "$S" 'XF86AudioRaiseVolume'

# ── Niri ───────────────────────────────────────────────────────────────────────

section "Niri"
N="$(run_parser niri "${FIXTURES}/niri.kdl")"

assert_json_valid  "niri: valid JSON"                            "$N"
assert_contains    "niri: Applications section"                  "$N" '"Applications"'
assert_contains    "niri: Windows section"                       "$N" '"Windows"'
assert_contains    "niri: Focus section"                         "$N" '"Focus"'
assert_contains    "niri: Workspaces section"                    "$N" '"Workspaces"'
assert_contains    "niri: spawn alacritty"                       "$N" 'alacritty'
assert_contains    "niri: close-window"                          "$N" 'close-window'
assert_contains    "niri: Mod+Return key"                        "$N" 'Mod+Return'
assert_contains    "niri: focus-column-left"                     "$N" 'focus-column-left'
assert_contains    "niri: focus-workspace"                       "$N" 'focus-workspace'

# ── Extra files ────────────────────────────────────────────────────────────────

section "Extra files arg"
E="$(run_parser hyprland "${FIXTURES}/hyprland.conf" "${FIXTURES}/hyprland_extra.conf")"

assert_json_valid  "extras: valid JSON"                          "$E"
assert_contains    "extras: sections from main config"           "$E" '"Applications"'
# extra file is already sourced inside conf — confirm no crash with duplicate
assert_contains    "extras: Workspaces still present"            "$E" '"Workspaces"'

# ── Error handling ─────────────────────────────────────────────────────────────

section "Error handling"
assert_contains    "error: missing compositor arg" \
    "$(bash "$PARSER" 2>/dev/null || true)" '"error"'

assert_contains    "error: unknown compositor returns error key" \
    "$(bash "$PARSER" unknownwm 2>/dev/null || true)" '"error"'

MISSING="$(run_parser hyprland "/nonexistent/config.conf")"
assert_json_valid  "error: missing config file → valid JSON"     "$MISSING"
assert_contains    "error: missing config file → empty sections" "$MISSING" '"sections":[]'

# ── Annotation strictness ──────────────────────────────────────────────────────

section "Annotation strictness"
# Plain comments must never create sections
assert_not_contains "strict: plain # comment not a section (hyprland)" "$H" '"name":"$'
assert_not_contains "strict: plain # comment not a section (sway)"     "$S" '"name":"set'
assert_not_contains "strict: plain // comment not a section (niri)"    "$N" '"name":"binds'

# ── Ignore blocks ─────────────────────────────────────────────────────────────

section "@ignore / @end-ignore"
I="$(run_parser hyprland "${FIXTURES}/hyprland_ignore.conf")"

assert_json_valid  "ignore: valid JSON"                          "$I"
assert_contains    "ignore: Visible section present"             "$I" '"Visible"'
assert_contains    "ignore: Also Visible section present"        "$I" '"Also Visible"'
assert_contains    "ignore: alacritty in output"                 "$I" 'alacritty'
assert_contains    "ignore: firefox in output"                   "$I" 'firefox'
assert_not_contains "ignore: hidden-app excluded"                "$I" 'hidden-app'
assert_not_contains "ignore: also-hidden excluded"               "$I" 'also-hidden'

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════"
printf "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "══════════════════════════════════════════════════════════"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo "Failed:"
    for e in "${ERRORS[@]}"; do echo "  • $e"; done
    echo ""
    exit 1
fi

echo ""
exit 0
