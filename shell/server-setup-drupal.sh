#!/bin/sh
#
# Setup of a server for a (Drupal) site with some dafaults.
#

# Enable debug mode
if [ ! -z "$DEBUG" ]; then
  set -x
  VERBOSE=1
fi

# Include utilities file
UTILS_FILE=$(realpath "$(dirname $0)/_utils.sh")
if [ ! -r $UTILS_FILE  ]; then
  echo "Missing required _utils.sh file."
  exit 1
else
  . $UTILS_FILE
fi

# Set some default values if not provided in the config
VHOST_BASEDIR='/var/www/vhosts'
FILES_BASEDIR='/var/www/files'

# User and group running the webserver (for chown)
WWW_USER='www-data'
WWW_GROUP="$WWW_USER"
# Key used for git clone
SSH_PUBKEY="$VHOST_BASEDIR/.ssh/id_rsa.pub"

DRUPAL_SETTINGS_FILE_TPL="$(dirname $0)/_templates/settings.d7.php.tpl"

MYSQL_DEFAULTS_FILE='/etc/mysql/debian.cnf'

NGINX_CONF_DIR='/etc/nginx'
NGINX_VHOST_TPL="$(dirname $0)/_templates/nginx-drupal.conf.tpl"

# Include config
CONF_FILENAME="esolitos-server-setup-drupal"
include_conf_file $CONF_FILENAME

SITE_DOMAIN="$1"
if [[ -z "$SITE_DOMAIN" ]]; then
  error_printer "Missing required argument: hostname"
  exit 1
elif [ -e "$VHOST_BASEDIR/$SITE_DOMAIN" ]; then
  error_printer "Site directory exists already, cowardly bailing out."
  exit 2
fi

# Use predefined repository name or provided one
if [[ -z "$2" ]]; then
  REPO_URL="esolitos@bitbucket.org:esolitos/$SITE_DOMAIN.git"
else
  CUSTOM_REPO=1
  REPO_URL="$2"
fi

# Define db user, db name based on hostnamem a random password and a random salt
DB_USER="$(printf "%s" "$SITE_DOMAIN"| tr -cd '[:alpha:]' | cut -c 1-16)"
DB_NAME="drupal_$DB_USER"
DB_PASS="$(/usr/bin/openssl rand -hex 16)"
DRUPAL_SALT="$(/usr/bin/openssl rand -hex 32)"

if [ -z $CUSTOM_REPO ]; then
  printf "### Add following key to: https://bitbucket.org/esolitos/%s/admin/access-keys/ ###\n\n" "$SITE_DOMAIN"
else
  printf "### Add following key to the repository ###\n\n"
fi
cat "$SSH_PUBKEY"
printf "\n### ENDKEY ###\n"
read -p 'Press any key once you are done.'

# Get the code
verbose_printer "Cloning repository"
git clone "$REPO_URL" "$VHOST_BASEDIR/$SITE_DOMAIN"
return_code=$?
if [ $return_code -ne 0 ]; then
  error_printer "Error occurred during git clone. Terminating."
  # Forward error code
  exit $return_code
fi

# Create anc set permission for files directories
verbose_printer "Creating files directories..."
if [ -e "$FILES_BASEDIR/$SITE_DOMAIN" ]; then
  printf "Site's files base directory already exists: %s" "$FILES_BASEDIR/$SITE_DOMAIN"
fi
mkdir -p "$FILES_BASEDIR/$SITE_DOMAIN/public" "$FILES_BASEDIR/$SITE_DOMAIN/private"
chown -R "$WWW_USER":"$WWW_GROUP" "$FILES_BASEDIR/$SITE_DOMAIN"
chmod -R ug=rwX,o=rX "$FILES_BASEDIR/$SITE_DOMAIN"

verbose_printer "Linking public files directory..."
if [ -e "$VHOST_BASEDIR/$SITE_DOMAIN/web/sites/default/files" ]; then
  error_printer "Public files directory exists. Please remove it and try again."
  exit 3
fi
ln -s "$FILES_BASEDIR/$SITE_DOMAIN/public" "$VHOST_BASEDIR/$SITE_DOMAIN/web/sites/default/files"
return_code=$?
if [ $return_code -ne 0 ]; then
  error_printer "Error occurred on public files symlink. Terminating."
  # Forward error code
  exit $return_code
fi

#
# Config: NginX
#
verbose_printer "Configuring nginx servers..."
NGINX_VHOST_OUT="$NGINX_CONF_DIR/sites-available/$SITE_DOMAIN.conf"
sed "s/THE_HOSTNAME/$SITE_DOMAIN/g;\
s/#{D7}//g;" "$NGINX_VHOST_TPL" > "$NGINX_VHOST_OUT"

printf "### NGINX CONF: $NGINX_VHOST_OUT ###\n"
cat "$NGINX_VHOST_OUT"
printf "\n### END CONF ###\n"
if [ ! $(prompt_confirm "Check the nginx config. Is that correct?") ]; then
  error_printer "Interrupted. Nginx config not accepted."
  exit 4
fi

#
# Config: MySQL
#
verbose_printer "Creating db, user and granting permissions."
if [ ! -f "$MYSQL_DEFAULTS_FILE" ]; then
  error_printer "MySQL defaults file is missing: $MYSQL_DEFAULTS_FILE"
  exit 5
fi
if [ 1 -eq $(mysql --defaults-file="$MYSQL_DEFAULTS_FILE" -N -B -e "SHOW DATABASES LIKE '$DB_NAME'" | wc -l) ]; then
  error_printer "Database exist already. Terminating."
  exit 6
fi
echo "CREATE DATABASE $DB_NAME;\
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" | mysql --defaults-file="$MYSQL_DEFAULTS_FILE"
return_code=$?
if [ $return_code -ne 0 ]; then
  error_printer "Error occurred with mysql step. Terminating."
  # Forward error code
  exit $return_code
fi

verbose_printer "Generate new settings.php with data..."
if [ ! -f "$DRUPAL_SETTINGS_FILE_TPL" ]; then
  error_printer "Drupal settings template is missing: $DRUPAL_SETTINGS_FILE_TPL"
  exit 7
fi
sed "s/TPL_site_domain/$SITE_DOMAIN/g;\
s/TPL_hash_salt/$DRUPAL_SALT/g;\
s/TPL_db_name/$DB_NAME/g;\
s/TPL_db_user/$DB_USER/g;\
s/TPL_db_pass/$DB_PASS/g;" "$DRUPAL_SETTINGS_FILE_TPL" > "$VHOST_BASEDIR/$SITE_DOMAIN/web/sites/default/settings.php"

#
# Final step: reload required daemons.
#
echo "Reloading nginx configuration..."
nginx -s reload


#certbot certonly --webroot -w /var/www/acme-challenge -d grandequercia.org -d www.grandequercia.org --post-hook='nginx -s reload'

printf "Completed!!\n\tTest the site: https://$SITE_DOMAIN/\n"
