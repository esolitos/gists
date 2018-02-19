#!/bin/sh
#
# Utilist functions to use in other scripts.
#

#
# Prints a log message only if VERBOSE or DEBUG are defined
#
verbose_printer() {
  if [ -z "$VERBOSE" -a -z "$DEBUG" ]; then
    return 0
  fi;
  printf "%s\n" "$1"
}

#
# Prints a message into the stderr, in red if supported
#
error_printer() {
  string-format-get
  printf "${FMT_red}%s${FMT_normal}\n" "$1" 1>&2
}

#
# Includes the standard config files in the logical order
#
include_conf_file() {
  # Only one parameter should be passed, the config file name
  if [ $# -ne 1 ]; then
    error_printer "One argument is required: config filename"
    return 1
  fi

  # Global config file
  cfg_global="/etc/$1"
  if [ -f "$cfg_global" -a -r "$cfg_global" ]; then
    verbose_printer "Sourcing global conf: $cfg_global"
    . "$cfg_global"
  fi
  # Current user config file
  cfg_user="$HOME/.config/$1"
  if [ -f "$cfg_user" -a -r "$cfg_user" ]; then
    verbose_printer "Sourcing user conf: $cfg_user"
    . "$cfg_user"
  fi
}

#
# Checks if terminal supports color and if so defines a few FMT_* constants to
#  allow wasy color swapping.
#
string_format_get() {
  # check if stdout is a terminal...
  if test -t 1; then
    # see if it supports colors...
    ncolors=$(tput colors)

    if test -n "$ncolors" && test $ncolors -ge 8; then
      FMT_bold="$(tput bold)"
      FMT_underline="$(tput smul)"
      FMT_invert="$(tput smso)"
      FMT_normal="$(tput sgr0)"
      FMT_black="$(tput setaf 0)"
      FMT_red="$(tput setaf 1)"
      FMT_green="$(tput setaf 2)"
      FMT_yellow="$(tput setaf 3)"
      FMT_blue="$(tput setaf 4)"
      FMT_magenta="$(tput setaf 5)"
      FMT_cyan="$(tput setaf 6)"
      FMT_white="$(tput setaf 7)"
    fi
  fi
}

#
# Checks if BackBlaze command (b2) is available and configured
#
check_backblaze_status() {
  which b2 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    error_printer "Missing b2 executable in path."
    return 1
  fi

  b2 get-account-info >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    error_printer "b2 account not configured"
    return 2
  fi

  return 0
}
