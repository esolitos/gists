#!/bin/sh
#
# Utilist functions to use in other scripts.
#

#
# Includes the standard config files in the logical order
#
include-conf-file() {
  # Only one parameter should be passed, the config file name
  if [ $# -ne 1 ]; then
    return 1
  fi
  # Global config file
  if [ -r "/etc/$CONF_FILE" ]; then
    source "/etc/$CONF_FILE"
  fi
  # Current user config file
  if [ -r "$HOME/.config/$CONF_FILE" ]; then
    source "$HOME/.config/$CONF_FILE"
  fi
}

#
# Checks if terminal supports color and if so defines a few FMT_* constants to
#  allow wasy color swapping.
#
string-format-get() {
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
# Prints a log message only if VERBOSE or DEBUG are defined
#
verbose-only-printer() {
  if [[ -z "$VERBOSE" -a -z "$DEBUG" ]]; then
    return 0
  fi;
  printf "%s\n" $1
}

#
# Prints a message into the stderr, in red if supported
#
error-printer() {
  string-format-get
  printf "${FMT_red}%s${FMT_normal}\n" $1 1>&2
}
