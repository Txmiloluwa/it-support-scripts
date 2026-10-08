#!/usr/bin/env bash
#
# network_check.sh - step-by-step check for "the internet isn't working".
#
# Works through the network from the inside out, the same order a help desk
# would: local IP -> default gateway -> DNS -> internet -> website. The first
# step that fails tells you where the problem is.
#
# Usage: ./network_check.sh [host-to-test]   (default: www.google.com)

set -uo pipefail   # no -e: we want to keep going and report every step

TARGET="${1:-www.google.com}"
OS="$(uname -s)"
FAILED=0

pass() { printf '  [PASS] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n         Likely cause: %s\n' "$1" "$2"; FAILED=$((FAILED + 1)); }

ping_once() {
  # macOS uses -t for timeout in seconds, Linux uses -W.
  if [[ "$OS" == "Darwin" ]]; then
    ping -c 1 -t 3 "$1" > /dev/null 2>&1
  else
    ping -c 1 -W 3 "$1" > /dev/null 2>&1
  fi
}

echo "Network check ($(date '+%Y-%m-%d %H:%M:%S'))"
echo

echo "1. Local IP address"
if [[ "$OS" == "Darwin" ]]; then
  LOCAL_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
else
  LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
if [[ -n "${LOCAL_IP:-}" ]]; then
  pass "This machine has IP $LOCAL_IP"
  if [[ "$LOCAL_IP" == 169.254.* ]]; then
    fail "IP $LOCAL_IP is a self-assigned address" "the DHCP server (usually the router) did not respond"
  fi
else
  fail "No IP address found" "Wi-Fi is off, the cable is unplugged, or the adapter is disabled"
fi

echo "2. Default gateway (your router)"
if [[ "$OS" == "Darwin" ]]; then
  GATEWAY="$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')"
else
  GATEWAY="$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')"
fi
if [[ -z "${GATEWAY:-}" ]]; then
  fail "No default gateway configured" "not connected to a network, or DHCP failed"
elif ping_once "$GATEWAY"; then
  pass "Router $GATEWAY responds"
else
  # Some routers block ping, so this is a warning rather than proof of failure.
  fail "Router $GATEWAY did not reply to ping" "router is down, or it is configured to ignore ping"
fi

echo "3. DNS (turning names into IP addresses)"
if RESOLVED="$(getent hosts "$TARGET" 2>/dev/null | awk '{print $1; exit}')" && [[ -n "$RESOLVED" ]]; then
  pass "$TARGET resolves to $RESOLVED"
elif RESOLVED="$(nslookup "$TARGET" 2>/dev/null | awk '/^Address: / {print $2; exit}')" && [[ -n "$RESOLVED" ]]; then
  pass "$TARGET resolves to $RESOLVED"
else
  fail "Could not resolve $TARGET" "DNS server is unreachable or misconfigured; try 1.1.1.1 or 8.8.8.8"
fi

echo "4. Internet connectivity (by IP, skipping DNS)"
if ping_once 1.1.1.1 || ping_once 8.8.8.8; then
  pass "Public internet is reachable"
else
  fail "Cannot reach 1.1.1.1 or 8.8.8.8" "no internet from the router, ISP outage, or a firewall blocking ping"
fi

echo "5. Website (HTTPS)"
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://$TARGET" 2>/dev/null || true)"
if [[ "$HTTP_CODE" =~ ^[23] ]]; then
  pass "https://$TARGET answered with HTTP $HTTP_CODE"
else
  fail "https://$TARGET did not load (HTTP code: ${HTTP_CODE:-none})" "website down, proxy or firewall blocking HTTPS"
fi

echo
if (( FAILED == 0 )); then
  echo "Result: all checks passed"
  exit 0
fi
echo "Result: $FAILED check(s) failed. Start fixing from the FIRST failure above."
exit 1
