#!/usr/bin/env bash
# Probe whether an API route exists without credentials, and whether it
# accepts the request shape you intend to send.
#
#   scripts/probe_route.sh https://host/api/v1/completions '{"prompt":"x"}'
#
# A live, auth-gated route answers 401/403 for a well-formed request.
# 404 means the path is not a route at all.
# 400/422 means the route exists but rejects this body shape.
# Compare against a deliberately bogus sibling path.
set -u

base_url="${1:?usage: probe_route.sh <full-url> [json-body]}"
body="${2:-{\"prompt\":\"probe\"}}"

probe() {
  local url="$1"
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    -X POST "$url" \
    -A 'Mozilla/5.0' \
    -H 'Content-Type: application/json' \
    -d "$body"
}

real_code="$(probe "$base_url")"

# Sibling path built by replacing the last segment, so the bogus probe stays
# inside the same API surface rather than escaping to the site root.
bogus_url="${base_url%/*}/__hermes_probe_nonexistent__"
bogus_code="$(probe "$bogus_url")"

printf 'target %s -> %s\n' "$base_url" "$real_code"
printf 'bogus  %s -> %s\n' "$bogus_url" "$bogus_code"

echo
if [ "$bogus_code" = "404" ] && [ "$real_code" != "404" ]; then
  case "$real_code" in
    401|403) echo 'VERDICT: route EXISTS and is auth-gated (credentials are the next thing to check).' ;;
    400|422) echo 'VERDICT: route EXISTS but rejects this body shape — check the request contract (field names, prompt vs messages).' ;;
    2*)    echo 'VERDICT: route EXISTS and accepted the body.' ;;
    405)   echo 'VERDICT: path exists but not for POST.' ;;
    *)     echo "VERDICT: route exists, answered $real_code." ;;
  esac
elif [ "$real_code" = "404" ]; then
  echo 'VERDICT: target path is NOT a route. Confirm the full path — a client may be'
  echo '         sending your base URL verbatim, or the path differs from the docs.'
else
  echo "VERDICT: inconclusive (bogus probe answered $bogus_code, not 404)."
  echo '         The host may auth-gate unknown paths too. Verify the route in the source.'
fi
