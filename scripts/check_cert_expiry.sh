#!/usr/bin/env bash
# Checks TLS certificate expiry for the given domain.
# Exits 1 and prints a warning if the cert expires within WARN_DAYS days.
# Usage: ./check_cert_expiry.sh [domain] [warn_days]

DOMAIN="${1:-easyhealth.art}"
WARN_DAYS="${2:-30}"

expiry_date=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null \
  | cut -d= -f2)

if [ -z "$expiry_date" ]; then
  echo "ERROR: Could not retrieve certificate for $DOMAIN"
  exit 1
fi

expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s)
now_epoch=$(date +%s)
days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))

echo "Certificate for $DOMAIN expires in $days_remaining days ($expiry_date)"

if [ "$days_remaining" -lt "$WARN_DAYS" ]; then
  echo "WARNING: Certificate expires in less than $WARN_DAYS days — renew now!"
  exit 1
fi

exit 0
