#!/bin/sh

if [ ! -z "$DEBUG" ]; then
  set -x
fi

verify_and_reload_nginx() {
  # Verify nginx configuration
  /usr/sbin/nginx -t -c /etc/nginx/nginx.conf
  if [ $? -ne 0 ]; then
    printf "\nSomething is wrong in nginx config, please fix ASAP!!" >&2
    exit 2
  else
    printf "Reloading nginx to apply new config.\n"
    /usr/sbin/nginx -s reload >/dev/null
  fi
}

while true; do
  read -p "Slug (short name) for the new domain: " SLUG
  if [ -z "$SLUG" ]; then
    printf "Empty value not allowed.\n\n"
  elif [ ! -z "$(printf "%s" "$SLUG" | tr -d [a-z\-])" ]; then
    printf "Only lowercase letters are allowed.\n\n"
  else
    # All good, we can continue
    break
  fi
done

FQDN_DEFAULT="${SLUG}.ads.ramsalt.com"
while true; do
  read -p "FQDN for the new domain [$FQDN_DEFAULT]: " FQDN
  if [ -z "$FQDN" ]; then
    FQDN="$FQDN_DEFAULT"
    break;
  elif [ ! -z "$(printf "%s" "$FQDN" | tr -d '[a-z\.\-]')" ]; then
    echo "Only lowercase letters, dashes (-) and dots (.) are allowed."
  else
    # All good, we can continue
    break
  fi
done

WEBROOT_DEFAULT="/var/www/$FQDN"
while true; do
  read -p "Webroot for the new domain [$WEBROOT_DEFAULT]: " WEBROOT
  if [ -z "$WEBROOT" ]; then
    WEBROOT="$WEBROOT_DEFAULT"
  fi
  if [ -d "$WEBROOT" ]; then
    # All good, it's a directory
    break
  else
    echo "Webroot doesn't exist or is not a directory."
  fi
done

nginx_conf_tpl="/etc/nginx/sites-available/EXAMPLE.ads.ramsalt.com.tpl"
nginx_conf_out="/etc/nginx/sites-available/$FQDN"

if [ ! -f "$nginx_conf_tpl" ]; then
  printf "Missing nginx config tempalte file: %s" "$nginx_conf_tpl" >&2
  exit 2
fi

# Write out configuration from template
printf "Generating new nginx vhost config.\n"
sed "s:TPL_DOMAIN:$FQDN:;\
  s:TPL_WEBROOT:$WEBROOT:;" "$nginx_conf_tpl" > "$nginx_conf_out"

# Enable new site (symlink) new configuration
(
  cd '/etc/nginx/sites-enabled' || (echo "Missing nginx sites-enabled directory." && exit 2)
  ln -s "../sites-available/$FQDN" "$FQDN"
)

# Check new config and reload if good
verify_and_reload_nginx


printf "Fetching SSL certificate...\n"
/usr/bin/certbot certonly --non-interactive --webroot -w "$WEBROOT" -d "$FQDN" --post-hook="/usr/sbin/nginx -s reload"
if [ $? -ne 0 ]; then
  printf "\nPossible error detected while generating certificate. Terminating here.\nManual actions still required:\n\t- SSL NOT ENABLED" >&2
  exit 4
else
  printf "Enabling SSL..\n"
  # Remove lines marked as "For SSL" in the template
  sed -i 's:#TPL_SSL_LINE#::' "$nginx_conf_out"
fi

# Check new config and reload if good
verify_and_reload_nginx

printf "\n#\n# Process Completed.\n#\n"
printf "# Recap:\n# Site: https://%s/\n# Webroot: %s\n#\n" "$FQDN" "$WEBROOT"
