#!/bin/sh
#
# Setup script for new Revive server
#
# TODO:
#  - Use custom static images folder

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
  elif [ -e "$WEBROOT" ]; then
    echo "Webroot *exist* but is *not a directory*."
  else
    read -p "Webroot doesn't exist, do you want to create it? [y/N] " yn
    if [ "$yn" = 'y' -o  "$yn" = 'Y' ]; then
      mkdir -p "$WEBROOT" || (printf "Cannot create webroot directory." >&2 && exit 1)
    else
      printf "Ok, interrupting. (You answered: %s)" "$yn"
      break;
    fi
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

REVIVE_VERSION_DEFAULT='4.1.3'
while true; do
  read -p "Revive version to install [$REVIVE_VERSION_DEFAULT]: " REVIVE_VERSION
  if [ ! -z "$(printf "%s" "$REVIVE_VERSION" | tr -d [0-9\.])" ]; then
    echo "Only numbers and dots (.) are allowed."
  else
    read -p "Selected >${REVIVE_VERSION}<, correct? [y/n]" yn
    if [ "$yn" = 'y' -o  "$yn" = 'Y' ]; then
      break;
    fi
  fi
done

DL_DIR="/root/downloads"
REVIVE_FILENAME="revive-adserver-${REVIVE_VERSION}"

if [ ! -f "${DL_DIR}/${REVIVE_FILENAME}.tar.gz" ]; then
  REVIVE_DL_URL="https://download.revive-adserver.com/${REVIVE_FILENAME}.tar.gz"
  printf "Downloading file: %s ...\n" "$REVIVE_DL_URL"
  curl --location --output "${DL_DIR}/${REVIVE_FILENAME}.tar.gz" "$REVIVE_DL_URL"
  if [ $? -ne 0 ]; then
    printf "cURL returned non-zero status, something went wrong. Terminating" >&2
    exit 5
  fi
else
  printf "Using cache file: %s\n" "${DL_DIR}/${REVIVE_FILENAME}.tar.gz"
fi

printf "Extracting file to destination.\n"
tar --extract --file "${DL_DIR}/${REVIVE_FILENAME}.tar.gz" "$WEBROOT/$REVIVE_FILENAME"
if [ $? -ne 0 ]; then
  printf "Tarball extraction failed. Terminating" >&2
  exit 5
fi

# Generate valid password, username and db name
DB_PASS="$(openssl rand -hex 32)"
DB_USERNAME="$(printf "revive_%s" "$SLUG" | tr -cd '[a-z\_]' | cut -c 1-24)"
DB_NAME="$(printf "%s_%s" "$DB_USERNAME" "$REVIVE_VERSION" | tr -cd '[a-z\_]' | cut -c 1-32)"

# Check if database exists already, if so suggest an alternative name
I=0
while true; do
  mysql --defaults-file=/etc/mysql/debian.cnf --local-infile --batch --skip-column-names -e "SHOW DATABASES;" | grep --silent -E "^$DB_NAME$"
  if [ $? -ne 0 ]; then
    # All good db name is not in use
    break
  else
    printf "A database with same name (%s) exists!\n" "$DB_NAME"
    DB_NAME_SUGGEST="${DB_NAME}_$((I=I+1))"
    printf "Fallback db name: [%s]\nTo accept type [y], to cancel and interrupt type [n].\n" "$DB_NAME_SUGGEST"
    read -p "Any other input will be considered a new db name: " answer
    if [ "$answer" = 'y' -o "$answer" = 'Y' ]; then
      DB_NAME="$DB_NAME_SUGGEST"
    elif [ "$answer" = 'n' -o "$answer" = 'N' ]; then
      printf "Ok, stopping process."
      exit 100
    else
      DB_NAME_SUGGEST="$(printf "%s" "$answer" | tr -cd '[a-z\_]' | cut -c 1-32)"
    fi
  else
    break;
  fi
done

printf "Creating database and granting permissions to mysql user...\n"
echo "CREATE DATABASE $DB_NAME;\
  GRANT ALL PRIVILAGES ON ${DB_NAME}.* TO '${DB_USERNAME}'@'localhost' IDENTIFIED BY '${DB_PASS}';\
" | mysql --defaults-file=/etc/mysql/debian.cnf

printf "Creating static images directory"
mkdir -P "$WEBROOT/revive-static/images"
chmod -R a=rwX "$WEBROOT/revive-static/images"

printf "Creating default index.php for /revive redirect.."
echo '<?php \
header("HTTP/1.1 301 Moved Permanently");\
header("Location: /revive");\
header("Connection: close");\
exit();' > "$WEBROOT/index.php"

# Enable current version if it's the only existing one
if [ -e "$WEBROOT/revive" ]; then
  printf "A revive version seems to be already existing, not enabling current as default." >&2
else
  printf "Enable version $REVIVE_VERSION as default."
  (
    cd "$WEBROOT" && ln -s "$REVIVE_FILENAME" 'revive'
    if [ $? -ne 0]; then
      printf "Symlink failed.\n" >&2
      exit 10
    fi
  )
fi

printf "\n#\n# Process Completed.\n#\n"
printf "# Process recap:\n"
printf "#\n"
printf "# Site URL: https://%s/\n" "$FQDN"
printf "# Webroot: %s\n" "$WEBROOT"
printf "#\n"
printf "# DB Name: %s\n" "$DB_NAME"
printf "# DB User: %s\n" "$DB_USER"
printf "# DB Pass: %s\n" "$DB_PASS"
printf "#\n"
