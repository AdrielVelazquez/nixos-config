#!/usr/bin/env bash
# #region agent log: llama-server + opencode debug probe (session e977b0)
# Writes NDJSON entries to the debug log path so the agent can analyze runtime state.
set -u
LOG=/home/adriel/.nixos/.cursor/debug-e977b0.log
SID=e977b0
RUN=${RUN:-initial}

mkdir -p "$(dirname "$LOG")"

emit() {
  local hyp="$1" location="$2" message="$3" data_json="$4"
  local ts=$(date +%s%3N)
  jq -cn --arg sid "$SID" --arg run "$RUN" --arg hyp "$hyp" \
        --arg loc "$location" --arg msg "$message" \
        --argjson data "$data_json" --argjson ts "$ts" \
    '{sessionId:$sid, runId:$run, hypothesisId:$hyp, location:$loc, message:$msg, data:$data, timestamp:$ts}' \
    >> "$LOG"
}

# ---- H1: which llama-server process is actually running? ----
PS_OUT=$(ps -eo pid,etime,cmd | rg 'llama-server' | rg -v 'rg ' || true)
emit H1 "probe.sh:ps" "running llama-server processes" \
  "$(jq -cn --arg s "$PS_OUT" '{ps:$s}')"

# ---- H2/H5: what does /v1/models advertise? Do data[] capabilities differ from models[] capabilities? ----
MODELS=$(curl -s --max-time 5 http://127.0.0.1:8080/v1/models || echo '{}')
emit H2 "probe.sh:models" "/v1/models response (truncated)" \
  "$(jq -cn --arg s "${MODELS:0:2000}" '{body:$s}')"
emit H5 "probe.sh:caps" "compare data[0] vs models[0] capability fields" \
  "$(printf '%s' "$MODELS" | jq -c '{data_meta:(.data[0].meta // null), data_caps:(.data[0].capabilities // null), models_caps:(.models[0].capabilities // null)}' 2>/dev/null || echo '{"err":"jq parse failed"}')"

# ---- H1/H2: is the patched chat_template the one actually loaded? ----
PROPS=$(curl -s --max-time 5 http://127.0.0.1:8080/props || echo '{}')
TPL=$(printf '%s' "$PROPS" | jq -r '.chat_template // ""' 2>/dev/null)
TPL_LEN=${#TPL}
HAS_PATCH=false
HAS_RAISE=false
case "$TPL" in
  *"<|im_start|>system\\n' + content + '<|im_end|>\\n' }}"*) HAS_PATCH=true ;;
esac
case "$TPL" in
  *"System message must be at the beginning"*) HAS_RAISE=true ;;
esac
emit H1 "probe.sh:tpl" "active chat_template fingerprint" \
  "$(jq -cn --arg len "$TPL_LEN" --arg p "$HAS_PATCH" --arg r "$HAS_RAISE" \
     --arg head "${TPL:0:200}" \
     '{template_len:($len|tonumber), has_patch:($p=="true"), has_old_raise:($r=="true"), template_head:$head}')"

# ---- H3/H4: exercise the actual chat completions endpoint with several shapes ----
test_shape() {
  local name="$1" hyp="$2" body="$3"
  local resp_file=$(mktemp)
  local code=$(curl -s -o "$resp_file" -w '%{http_code}' --max-time 30 \
    -H 'content-type: application/json' \
    -d "$body" \
    http://127.0.0.1:8080/v1/chat/completions)
  local snippet=$(head -c 600 "$resp_file")
  emit "$hyp" "probe.sh:chat:$name" "POST /v1/chat/completions [$name]" \
    "$(jq -cn --arg c "$code" --arg s "$snippet" '{status:($c|tonumber), body:$s}')"
  rm -f "$resp_file"
}

# Shape A: minimal request, system first only — baseline
test_shape "baseline_system_first" H3 '{
  "messages":[
    {"role":"system","content":"You are concise."},
    {"role":"user","content":"Reply with the single word: pong"}
  ],
  "max_tokens":8, "stream":false
}'

# Shape B: mid-conversation system message — the original failing pattern
test_shape "mid_system" H4 '{
  "messages":[
    {"role":"system","content":"You are concise."},
    {"role":"user","content":"hi"},
    {"role":"assistant","content":"hello"},
    {"role":"system","content":"reminder: be terse"},
    {"role":"user","content":"reply with the single word: pong"}
  ],
  "max_tokens":8, "stream":false
}'

# Shape C: with tools — does the model actually emit a tool_call when asked?
test_shape "with_tools" H2 '{
  "messages":[
    {"role":"system","content":"You are a tool-using assistant."},
    {"role":"user","content":"What is the weather in Paris? Use the get_weather tool."}
  ],
  "tools":[{
    "type":"function",
    "function":{
      "name":"get_weather",
      "description":"Get weather for a city",
      "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}
    }
  }],
  "max_tokens":128, "stream":false
}'

# Shape D: tools + mid-conversation system — closest to what opencode actually sends
test_shape "tools_plus_mid_system" H4 '{
  "messages":[
    {"role":"system","content":"You are a tool-using assistant."},
    {"role":"user","content":"hi"},
    {"role":"assistant","content":"hello"},
    {"role":"system","content":"reminder: prefer tools"},
    {"role":"user","content":"What is the weather in Paris?"}
  ],
  "tools":[{
    "type":"function",
    "function":{
      "name":"get_weather",
      "description":"Get weather for a city",
      "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}
    }
  }],
  "max_tokens":128, "stream":false
}'

emit DONE "probe.sh:end" "probe complete" "$(jq -cn --arg p "$LOG" '{log_path:$p}')"
echo "wrote probes to $LOG"
# #endregion
