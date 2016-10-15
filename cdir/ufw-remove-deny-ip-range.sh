#!/bin/bash

SCRIPT="${BASH_SOURCE-$0}"
SCRIPT_DIR="$( dirname "${SCRIPT}" )"

if [ $# < 1 ]; then
   echo "CDIR filename must be passed as an argument"
   echo "${SCRIPT} <cdir-file>"
   exit 1
fi

CDIR_FILE="$1"

if [ ! -f ${CDIR_FILE} ]; then
   echo "Cannot find CDIR file $1 in folder ${SCRIPT_DIR}"
   exit 1
fi

while IFS='' read -r line || [[ -n "${line}" ]]; do
   if [[ ! "${line}" =~ ^\s*# ]]; then
      ufw delete deny from ${line}
   else
      echo "Skipping commented line"
   fi
done < "${CDIR_FILE}"