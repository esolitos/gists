#!/bin/sh
#
# Removes all RAW image files (Default: NEF) in a directory which don't have a matching JPG
#

# Enable debug mode
if [ ! -z "$DEBUG" ]; then
  set -x
  VERBOSE=1
fi

# Include utilities file
basepath=$(cd -P -- "$(dirname -- "$0")" && printf '%s\n' "$(pwd -P)")
UTILS_FILE="$basepath/_utils.sh"
if [ ! -r $UTILS_FILE  ]; then
  echo "Missing required $basepath/_utils.sh file."
  exit 1
else
  . $UTILS_FILE
fi

if [ ! -d "$1" ]; then
  error_printer "Not a directory: $1"
  exit 2
fi

remove_file() {
  FILE="$1"
  verbose_printer "Attempting removal of $FILE"
  rmcount=$(($rmcount + 1))
  rm "$FILE"
}

quit_with_summary() {
  printf "Quitting.\nProcessed %03d files, removed %d\n" "$1" "$2"

  RET=0
  if [ ! -z "$3" ]; then
    RET="$3"
  fi
  exit $RET
}

# Init counters
count=0
rmcount=0

SCAN_DIR="$1"
EXT_RAW="NEF"
for raw_image_name in $(find -E "$SCAN_DIR" -type f -name "*.$EXT_RAW" -print); do
  count=$(($count + 1))
  base_image_name="$(basename "$raw_image_name" | sed -e "s/\.$EXT_RAW$//")"
  jpg_image_name="$SCAN_DIR/${base_image_name}.JPG"
  verbose_printer "$(printf "%s ==> %s\n" "$raw_image_name" "$base_image_name")"

  if [ ! -f "$jpg_image_name" ]; then
    verbose_printer "File missing: $jpg_image_name"
    if [ "$AUTO_REMOVE" ]; then
      remove_file "$raw_image_name"
    else
      while true; do
        read -rep "Delete RAW file ($raw_image_name) [Y/n/q]?: " -n1 YN
        if [ "$YN" == "" -o "$YN" == 'Y' -o "$YN" == 'y' ]; then
          remove_file "$raw_image_name"
          # Exit loop once file is removed
          break
        elif [ "$YN" == 'N' -o "$YN" == 'n' ]; then
          # Do not delete file, just exit the loop.
          break
        elif [ "$YN" == 'Q' -o "$YN" == 'q' ]; then
          quit_with_summary $count $rmcount
        else
          verbose_printer "Invalid choice: $YN"
        fi
      done
    fi
  fi
done

# Print a report
quit_with_summary $count $rmcount
