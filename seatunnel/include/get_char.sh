#!/bin/bash
# Author: OneinStack
# SeaTunnel Ops Code - Input Helper Functions
#
# Project home page:
#       https://github.com/oneinstack/oneinstack

get_char() {
  SAVEDSTTY=$(stty -g)
  stty -echo
  stty cbreak
  dd if=/dev/tty bs=1 count=1 2>/dev/null
  stty -raw
  stty echo
  stty "$SAVEDSTTY"
}

Press_Start() {
  echo
  echo "${CGREEN}Press any key to start...or Press Ctrl+c to cancel${CEND}"
  char=$(get_char)
}

Press_Continue() {
  echo
  echo "${CGREEN}Press any key to continue...${CEND}"
  char=$(get_char)
}
