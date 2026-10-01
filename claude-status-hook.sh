#!/bin/bash
# Claude Traffic Light — Claude Code hook.
#
# Usage (configured automatically in ~/.claude/settings.json by install.sh):
#   claude-status-hook.sh <HookEvent> [notification_type]
#
# Reads the hook JSON from stdin and writes one small JSON file per Claude Code session to
#   ~/.claude/traffic-light/sessions/<session_id>.json
# which the widget app polls.
#
#   SessionStart            -> ready    "Ready"
#   UserPromptSubmit        -> working  "Thinking…"     (remembers where this run starts in the transcript)
#   PreToolUse              -> working  "Thinking…"
#   PostToolUse             -> working  "Thinking…"
#   PreCompact              -> working  "Thinking…"
#   Notification idle       -> ready    "Ready"
#   Notification permission -> ready    "Approve?"
#   Stop                    -> done     "Done"          (+ "Last Run" token figures)
#   SessionEnd              -> removes the session file
#
# "Last Run" figures come from Claude Code's own usage records in the session transcript:
#   seconds = run duration, from the prompt's timestamp to the last assistant message
#   out     = output tokens generated during the run  (footer: "4m 44s · 4.6k tokens")
#   ctx     = tokens in the context window after the run (input + cache read + cache write of the
#             last API call) — the same number Claude Code shows as "tokens used" (menu: Context)
#   delta   = ctx now minus ctx after the previous run
#
# Manual test:  echo '{"session_id":"test"}' | ~/.claude/traffic-light/claude-status-hook.sh Stop

EVENT="${1:-}"
SUBTYPE="${2:-}"
BASE="${HOME}/.claude/traffic-light/sessions"
mkdir -p "$BASE" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null)"
NOW="$(date +%s)"

# --- hook input ---------------------------------------------------------------
SESSION=""; TRANSCRIPT=""
eval "$(printf '%s' "$INPUT" | jq -r '@sh "SESSION=\(.session_id // "") TRANSCRIPT=\(.transcript_path // "")"' 2>/dev/null)"
SESSION="${SESSION:-default}"
SESSION="$(printf '%s' "$SESSION" | tr -c 'A-Za-z0-9_-' '_')"
FILE="$BASE/$SESSION.json"

# --- previous state of this session (carried over between events) ------------
PID=0; TURN_START=0; TURN_TS=0; TURN_DONE_TS=0; TOKENS=null
if [ -f "$FILE" ]; then
  eval "$(jq -r '@sh "PID=\(.pid // 0) TURN_START=\(.turn_start // 0) TURN_TS=\(.turn_ts // 0) TURN_DONE_TS=\(.turn_done_ts // 0) TOKENS=\((.tokens // null) | tojson)"' "$FILE" 2>/dev/null)"
fi
for v in PID TURN_START TURN_TS TURN_DONE_TS; do
  case "${!v}" in ''|*[!0-9]*) printf -v "$v" '%s' 0 ;; esac
done
case "$TOKENS" in \{*\}) ;; *) TOKENS=null ;; esac

# --- "Last Run" figures from the transcript -----------------------------------
# Prints a JSON object, or nothing if the run produced no assistant message.
run_stats() {
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0
  local seconds=0
  [ "$TURN_TS" -gt 0 ] && seconds=$((NOW - TURN_TS))
  local prev_ctx
  prev_ctx="$(printf '%s' "$TOKENS" | jq -r '.ctx // 0' 2>/dev/null)"
  case "$prev_ctx" in ''|*[!0-9]*) prev_ctx=0 ;; esac
  local defs='
    def human: .type=="user" and ((.isMeta // false)|not) and ((.isSidechain // false)|not)
      and ((.message.content|type)=="string"
           or ((.message.content|type)=="array" and ([.message.content[]? | select(.type=="tool_result")] | length)==0));
    def ts(e): (e | .timestamp? // "")
      | if type=="string" and length > 0 then (sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch null) else null end;
    def run_stats:
      [ .[] | select(.type=="assistant" and .message.usage != null) ] as $msgs
      | if ($msgs|length) == 0 then empty else
        ($msgs | last | .message) as $last
        | ($msgs | map({id: (.message.id // .uuid), u: .message.usage}) | group_by(.id)
                 | map([.[].u.output_tokens // 0] | max)) as $outs
        | (($last.usage.input_tokens // 0) + ($last.usage.cache_read_input_tokens // 0)
           + ($last.usage.cache_creation_input_tokens // 0)) as $ctx
        | ([ .[] | ts(.) | select(. != null) ] | first) as $t0
        | (ts($msgs | last)) as $t1
        | (if $t0 != null and $t1 != null and $t1 >= $t0 then ($t1 - $t0) else $seconds end) as $dur
        | { "ctx": $ctx, "prev_ctx": $prev, "delta": ($ctx - $prev),
            "out": (($outs | add) // 0), "calls": ($outs | length),
            "model": ($last.model // ""), "seconds": $dur }
        end;'
  local out
  if [ "$TURN_TS" -gt 0 ]; then
    # exact: everything appended to the transcript since UserPromptSubmit
    out="$(tail -n +"$((TURN_START + 1))" "$TRANSCRIPT" 2>/dev/null \
          | jq -c -n --argjson seconds "$seconds" --argjson prev "$prev_ctx" "$defs"' [inputs] | run_stats' 2>/dev/null)"
  else
    # fallback: everything after the last human prompt (bounded to the last 5000 lines)
    out="$(tail -n 5000 "$TRANSCRIPT" 2>/dev/null \
          | jq -c -n --argjson seconds "$seconds" --argjson prev "$prev_ctx" "$defs"' [inputs] as $all
              | ([ $all | to_entries[] | select(.value | human) | .key ] | max // -1) as $start
              | $all[(if $start < 0 then 0 else $start end):] | run_stats' 2>/dev/null)"
  fi
  case "$out" in \{*\}) printf '%s' "$out" ;; esac
}

# --- event -> state -----------------------------------------------------------
case "$EVENT" in
  SessionStart)      STATUS="ready";   LABEL="Ready" ;;
  UserPromptSubmit)  STATUS="working"; LABEL="Thinking…"
                     TURN_TS="$NOW"; TURN_START=0
                     if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
                       TURN_START="$(wc -l < "$TRANSCRIPT" | tr -d ' ')"
                       case "$TURN_START" in ''|*[!0-9]*) TURN_START=0 ;; esac
                     fi ;;
  PreToolUse)        STATUS="working"; LABEL="Thinking…" ;;
  PostToolUse)       STATUS="working"; LABEL="Thinking…" ;;
  PreCompact)        STATUS="working"; LABEL="Thinking…" ;;
  Stop)              STATUS="done";    LABEL="Done"
                     T="$(run_stats)"
                     if [ -n "$T" ]; then TOKENS="$T"; TURN_DONE_TS="$NOW"; fi
                     TURN_TS=0 ;;
  Notification)
    case "$SUBTYPE" in
      permission_prompt) STATUS="ready"; LABEL="Approve?" ;;
      idle_prompt)       STATUS="ready"; LABEL="Ready" ;;
      *) exit 0 ;;
    esac ;;
  SessionEnd)        rm -f "$FILE"; exit 0 ;;
  *) exit 0 ;;
esac

# --- pid of the Claude Code process (lets the widget ignore dead sessions) ----
if [ "$PID" -gt 0 ] && ! kill -0 "$PID" 2>/dev/null; then PID=0; fi
if [ "$PID" -eq 0 ]; then
  # Walk up from our parent until a process whose command mentions "claude",
  # skipping our own wrapper shell.
  PID="$(ps -axo pid=,ppid=,command= 2>/dev/null | awk -v start="$PPID" '
    { pid=$1; par=$2; $1=""; $2=""; cmd[pid]=$0; parent[pid]=par }
    END {
      p=start
      for (i=0; i<6 && p>1; i++) {
        if (cmd[p] ~ /[Cc]laude/ && cmd[p] !~ /claude-status-hook/ \
            && cmd[p] !~ /^ *([^ ]*\/)?(ba|z|da)?sh( |$)/) { print p; exit }
        p=parent[p]
      }
    }')"
  case "$PID" in ''|*[!0-9]*) PID=0 ;; esac
fi

# --- write atomically -------------------------------------------------------
TMP="$FILE.$$.tmp"
printf '{"status":"%s","label":"%s","event":"%s","ts":%s,"pid":%s,"turn_start":%s,"turn_ts":%s,"turn_done_ts":%s,"tokens":%s}\n' \
  "$STATUS" "$LABEL" "$EVENT" "$NOW" "$PID" "$TURN_START" "$TURN_TS" "$TURN_DONE_TS" "$TOKENS" > "$TMP" 2>/dev/null \
  && mv -f "$TMP" "$FILE" 2>/dev/null
exit 0
