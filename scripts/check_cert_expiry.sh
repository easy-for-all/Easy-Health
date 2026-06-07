#!/usr/bin/env bash
# Checks TLS certificate expiry for one or more domains.
# Exits 1 and prints a warning if any cert expires within WARN_DAYS days.
# Usage: ./check_cert_expiry.sh [domain] [warn_days] [additional_domain...]

DOMAIN="${1:-easyhealth.art}"
WARN_DAYS="${2:-45}"
shift 2 2>/dev/null || true
DOMAINS=("$DOMAIN" "$@")

status=0

check_domain() {
  local domain="$1"
  local expiry_date
  local expiry_epoch
  local now_epoch
  local days_remaining

  expiry_date=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | cut -d= -f2)

  if [ -z "$expiry_date" ]; then
    echo "ERROR: Could not retrieve certificate for $domain"
    status=1
    return
  fi

  expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s)
  now_epoch=$(date +%s)
  days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))

  echo "Certificate for $domain expires in $days_remaining days ($expiry_date)"

  if [ "$days_remaining" -lt "$WARN_DAYS" ]; then
    echo "WARNING: Certificate for $domain expires in less than $WARN_DAYS days - renew now!"
    status=1
  fi
}

for domain in "${DOMAINS[@]}"; do
  check_domain "$domain"
done

exit "$status"
