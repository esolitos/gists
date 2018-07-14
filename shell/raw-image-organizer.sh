#!/usr/bin/env bash
#
# Takes all the NEF files from a directory and copies them to $DEST_BASEDIR grouped
# by year-month directories and renames them based on DEST_FILENAME_FORMAT.
#

set -e
if [ $DEBUG ]; then
  set -x
fi

# Include config
if [ -f "$HOME/.eso-conf/raw-image-organizer" ]; then
  source "$HOME/.eso-conf/raw-image-organizer"
fi;

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NEUTRAL='\033[0m'

# Check requirements
SRC_DIR="$1"
if [ -z "$SRC_DIR" ]; then
  printf "\n${RED}You must specify a source directory.${NEUTRAL}\nNone provided.\n" 1>&2
  exit 1
elif [ ! -d "$SRC_DIR" ]; then
  printf "\n${RED}You must specify a source directory.${NEUTRAL}\nThis is not a directory: $SRC_DIR\n" 1>&2
  exit 1
fi

# exiftool is required
if ! command -v exiftool >/dev/null; then
  printf "\n${RED}Missing required program: exiftool${NEUTRAL}\n" 1>&2
  exit 1
fi

# Set some default values if not provided in the config

# Destination base directory
if [ -z "$DEST_BASEDIR" ]; then
  # Current directory
  DEST_BASEDIR='./'
elif [ ! "${DEST_BASEDIR: -1}" = '/' ]; then
  # Add a trailing slash if missing
  DEST_BASEDIR="${DEST_BASEDIR}/"
fi

# Date format used for rename, note that this can be a path.
# More info: https://sno.phy.queensu.ca/~phil/exiftool/filename.html
if [ -z "$DEST_DATE_FORMAT" ]; then
  # Group by year-month and start name with date of the shot
  DEST_DATE_FORMAT='%Y-%m/%Y-%m-%d'
fi

# Tag naming which will be directed to the `FileName` tag
# More info: https://sno.phy.queensu.ca/~phil/exiftool/filename.html
if [ -z "$DEST_FILENAME_FORMAT" ]; then
  # Use date from $DEST_DATE_FORMAT, camera model and original filename tags by default
  DEST_FILENAME_FORMAT='${DateTimeOriginal}.${Model;tr/ /_/}.${FileName}'
fi

# Wrap dateformat and filename
DATE_FMT="'${DEST_BASEDIR}${DEST_DATE_FORMAT}'"
FILENAME_FMT="'-filename<${DEST_FILENAME_FORMAT}'"

printf "\nOutput base directory is: ${GREEN}${DEST_BASEDIR}${NEUTRAL}\n"

sh -c "exiftool -preserve -ext NEF -out . -dateFormat $DATE_FMT $FILENAME_FMT $SRC_DIR"
