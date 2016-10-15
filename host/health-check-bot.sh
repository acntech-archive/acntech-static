#!/bin/bash

PORTS=()
PROCESSES=()
CONTAINERS=()

EMAIL_ACTIVE=${1:true}
EMAIL_SENDER="hostmaster@acntech.no"
EMAIL_RECIPIENTS=()
EMAIL_SUBJECT="Health check for server $(hostname)"
EMAIL_BODY="Health check for server $(hostname) has the result:"

MESSAGE=""

log() {
   echo "$(date +'%F %T.%3N %Z') - $1"
}

send_email() {
   sender=$1
   recipient=$2
   subject=$3
   body=$4

   if ! ${EMAIL_ACTIVE} ; then
      log "Email sending inactive."
      return 0;
   fi

   if [ -z "$recipient" ]; then
      log "Email recipient is not set."
      return 1;
   fi

   if [ -z "$subject" ]; then
      log "Email subject is not set."
      return 1;
   fi

   if [ -z "$body" ]; then
      body="$subject";
   fi

   echo "$body" | mail -s "$subject" "$recipient" -aFrom:$sender
   log "Email sent to recipient $recipient from sender $sender."
   return 0;
}

send_emails() {
   message=$1

   for EMAIL_RECIPIENT in ${EMAIL_RECIPIENTS}; do
      if ! send_email "${EMAIL_SENDER}" "${EMAIL_RECIPIENT}" "${EMAIL_SUBJECT}" "${EMAIL_BODY}\n$message" ; then
         return 1;
      fi
   done
   return 0;
}

handle_error() {
   if [ ! -z "${MESSAGE}" ]; then
      log "${MESSAGE}"
   fi

   if ! send_emails "${MESSAGE}" ; then
      log "Unable to send error email."
   fi

   echo "###  Server health check completed with errors at $(date +'%F %T.%3N %Z')  ###"
   exit 1
}

handle_success() {
   if [ ! -z "${MESSAGE}" ]; then
      log "${MESSAGE}"
   fi

   echo "###  Server health check completed successfully at $(date +'%F %T.%3N %Z')  ###"
   exit 0;
}

handle_exit() {
   local status=$?

   case $status in
      0) handle_success
         ;;
      *) handle_error
         ;;
   esac
}

check_ports() {
   for PORT in "${PORTS[@]}" ; do
      if [ ! netstat -ptnl | grep ":${PORT}\s*.*LISTEN" > /dev/null ]; then
         MESSAGE="Network port ${PORT} is not open or listening."
         exit 1;
      else
         log "Network port ${PORT} is open and listening."
      fi
   done
   log "All ${#PORTS[@]} network ports open and listening."
}

check_processes() {
   for PROC in "${PROCESSES[@]}" ; do
      if [ ! ps -aux | grep "${PROC}" > /dev/null ]; then
         MESSAGE="Process ${PROC} is not running."
         exit 1;
      else
         log "Process ${PROC} is running."
      fi
   done
   log "All ${#PROCESSES[@]} processes running."
}

check_containers() {
   for CONTAINER in "${CONTAINERS[@]}" ; do
      if [ ! docker ps -f "name=${CONTAINER}" -f "status=running" | grep "${CONTAINER}" > /dev/null ]; then
         MESSAGE="Container ${CONTAINER} is not running."
         exit 1;
      else
         log "Container ${CONTAINER} is running."
      fi
   done
   log "All ${#CONTAINERS[@]} containers running."
}

trap handle_error ERR
trap handle_exit EXIT

echo "###  Starting server health check at $(date +'%F %T.%3N %Z')  ###"

check_ports

check_processes

check_containers

exit 0;
