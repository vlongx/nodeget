#!/usr/bin/env sh
set -eu

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

domain="${DOMAIN:-nodeget.example.com}"
backend_url="${STATUS_BACKEND_URL:-wss://${domain}/ws}"

json_escape() {
  printf '%s' "$1" | awk '
    BEGIN { ORS = "" }
    {
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      gsub(/\r/,"\\r")
      gsub(/\t/,"\\t")
      print
      if (NR > 1) print "\\n"
    }
  '
}

site_name="$(json_escape "${STATUS_SITE_NAME:-NodeGet Status}")"
site_logo="$(json_escape "${STATUS_SITE_LOGO:-}")"
site_footer="$(json_escape "${STATUS_SITE_FOOTER:-Powered by NodeGet}")"
backend_name="$(json_escape "${STATUS_BACKEND_NAME:-main}")"
backend_url_json="$(json_escape "$backend_url")"
status_token="$(json_escape "${STATUS_TOKEN:-}")"

mkdir -p statusshow
cat >statusshow/config.json <<EOF
{
  "site_name": "${site_name}",
  "site_logo": "${site_logo}",
  "footer": "${site_footer}",
  "site_tokens": [
    {
      "name": "${backend_name}",
      "backend_url": "${backend_url_json}",
      "token": "${status_token}"
    }
  ]
}
EOF

echo "Wrote statusshow/config.json"
