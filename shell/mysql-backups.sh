#!/bin/sh
#
# Backups all mysql databses
#
# TODO:
# - Cleanup old backups
#

# Enable debug mode
if [ ! -z "$DEBUG" ]; then
  set -x
  VERBOSE=1
fi

UTILS_FILE=$(realpath "$(dirname $0)/_utils.sh")
if [ ! -r $UTILS_FILE  ]; then
  echo "Missing required _utils.sh file."
  exit 1
else
  . $UTILS_FILE
fi

# Include config
CONF_FILENAME="esolitos-mysql-backups"
include_conf_file $CONF_FILENAME

# Set some default values if not provided
if [ -z "$BKP_DATE" ]; then
  BKP_DATE="$(date '+%Y-%W')"
fi

if [ -z "$BKP_DIR" ]; then
  BKP_DIR='/var/backups/mysql'
fi

if [ -z "$MYSQL_DEFAULTS" ]; then
  MYSQL_DEFAULTS='/etc/mysql/debian.cnf'
fi

# Create snapshot of all mysql databases
mkdir -p "$BKP_DIR/$BKP_DATE"
DB_LIST=$(mysql --defaults-file="$MYSQL_DEFAULTS" --local-infile --batch --skip-column-names -e "SHOW DATABASES;" | grep -vE '(performance_schema)')
for dbname in $DB_LIST; do
  verbose_printer "Backing up: $dbname with destination $BKP_DIR/$BKP_DATE/$dbname.sql.gz"
  mysqldump --defaults-file="$MYSQL_DEFAULTS" --add-drop-table --add-locks --comments --flush-privileges --lock-all-tables --dump-date "$dbname" | pigz -c > "$BKP_DIR/$BKP_DATE/$dbname.sql.gz"
done

# Upload to BackBlaze
if [ ! check_backblaze_status ]; then
  error_printer "Mysql backups not mirrored: missing b2 command"
  exit 10
elif [ -z "$B2_BUCKET" ]; then
  error_printer "Mysql backups not mirrored: missing bucket name"
  exit 11
else
  # Sync weekly directory with remote one.
  verbose_printer "Mirroring backups to b2://$B2_BUCKET/$B2_SUB_PATH"
  verbose_printer "$(b2 sync --keepDays 120 --noProgress "$BKP_DIR/$BKP_DATE" "b2://$B2_BUCKET/$B2_SUB_PATH")"
fi
