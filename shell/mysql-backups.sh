#!/bin/sh
#
# Backups all mysql databses
#
# TODO:
# - Cleanup old backups
#

# Include config
if [ -f "$HOME/.eso-conf/mysql-backups" ]; then
  source "$HOME/.eso-conf/mysql-backups"
fi;

# Set some default values if not provided

if [ -z "$BKP_DATE" ]; then
  BKP_DATE="$(date '+%Y-%W')"
fi;

if [ -z "$BKP_DIR" ]; then
  BKP_DIR='/var/backups/mysql'
fi;

if [ -z "$MYSQL_DEFAULTS" ]; then
  MYSQL_DEFAULTS='/etc/mysql/debian.cnf'
fi;

# Create weekly db
mkdir -p "$BKP_DIR/$BKP_DATE"
DB_LIST=$(mysql --defaults-file="$MYSQL_DEFAULTS" --local-infile --batch --skip-column-names -e "SHOW DATABASES;" | grep -vE '(performance_schema)')
for dbname in $DB_LIST; do
  mysqldump --defaults-file="$MYSQL_DEFAULTS" --add-drop-table --add-locks --comments --flush-privileges --lock-all-tables --dump-date "$dbname" | pigz -c > "$BKP_DIR/$BKP_DATE/$dbname.sql.gz"
done;

# Upload to BackBlaze
which b2 >/dev/null 2>&1
if [ $? -ne 0 -o -z "$B2_BUCKET" ]; then
  printf "Backups not uploaded!" 1>&2
  exit 10
else
  # Sync weekly directory with remote one.
  b2 sync --keepDays 120 --noProgress "$BKP_DIR/$BKP_DATE" "b2://${B2_BUCKET}/mysql/"
fi;
