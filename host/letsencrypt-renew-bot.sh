#!/bin/bash

EMAIL_ACTIVE=${1:true}
EMAIL_SENDER="hostmaster@acntech.no"
EMAIL_RECIPIENTS=()
EMAIL_SUBJECT="Let's Encrypt certificates renewal for $(hostname)"
EMAIL_BODY="Let's Encrypt certificates renewal for $(hostname) have been renewed"

DOCKER_NGINX="acntech-nginx"

LETSENCRYPT_DOMAINS=()
LETSENCRYPT_LIVE_DIR="/etc/letsencrypt/live"
LETSENCRYPT_LOG_DIR="/var/log/letsencrypt"

NGINX_CONFIG_DIR="/var/docker/${DOCKER_NGINX}/etc/nginx"
NGINX_SSL_DIR="${NGINX_CONFIG_DIR}/ssl"

MESSAGE=""

log() {
   local message=$1
   echo "$(date +'%F %T.%3N %Z') - $message"
}

send_email() {
   local sender=$1
   local recipient=$2
   local subject=$3
   local body=$4

   if ! ${EMAIL_ACTIVE} ; then
      log "Email sending inactive"
      return 0;
   fi

   if [ -z "$recipient" ]; then
      log "Email recipient is not set"
      return 1;
   fi

   if [ -z "$subject" ]; then
      log "Email subject is not set"
      return 1;
   fi

   if [ -z "$body" ]; then
      body="$subject";
   fi

   if echo "$body" | mail -s "$subject" "$recipient" -aFrom:$sender ; then
      log "Email sent to recipient $recipient from sender $sender"
      return 0;
   else
      log "Unable to send email to recipient $recipient from sender $sender"
      return 1;
   fi
}

send_emails() {
   for EMAIL_RECIPIENT in ${EMAIL_RECIPIENTS}; do
      send_email "${EMAIL_SENDER}" "${EMAIL_RECIPIENT}" "${MESSAGE}"
   done
}

handle_error() {
   if [ ! -z "${MESSAGE}" ]; then
      log "$MESSAGE"
   fi

   send_emails

   echo "###  Certificate renewal process completed with error at $(date +'%F %T.%3N %Z')  ###"
   exit 1
}

handle_success() {
   if [ ! -z "${MESSAGE}" ]; then
      log "$MESSAGE"
   fi

   send_emails

   echo "###  Certificate renewal process completed successfully at $(date +'%F %T.%3N %Z')  ###"
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

docker_container_running() {
   local name=$1

   docker ps | grep $name > /dev/null 2>&1
   return $?
}

check_nginx_container_running() {
   # Is Nginx Proxy running
   if ! docker_container_running ${DOCKER_NGINX} ; then
      MESSAGE="Docker container for Nginx proxy is not running"
      exit 1
   fi
}

stop_nginx_container() {
   # Stop Nginx Proxy
   log "Stopping docker container for Nginx proxy."
   if ! docker stop ${DOCKER_NGINX} > /dev/null 2>&1 ; then
      MESSAGE="Failed to stop docker container for Nginx proxy"
      exit 1
   fi
}

start_nginx_container() {
   # Start Nginx Proxy
   log "Starting docker container for Nginx proxy."
   if ! docker start ${DOCKER_NGINX} > /dev/null 2>&1  ; then
      MESSAGE="Failed to start docker container for Nginx proxy"
      exit 1
   fi
}

backup_old_and_activate_new_certificate() {
   local domain=$1

   LETSENCRYPT_DOMAIN_DIR="${LETSENCRYPT_LIVE_DIR}/$domain"
   NGINX_SSL_DOMAIN_DIR="${NGINX_SSL_DIR}/$domain"
   NGINX_SSL_DOMAIN_BACKUP_DIR="${NGINX_SSL_DOMAIN_DIR}.$(date +'%Y%m%d%H%M%S')"

   # Backup old certificates domain dir
   log "Backing up old domain certificates from ${NGINX_SSL_DOMAIN_DIR} to ${NGINX_SSL_DOMAIN_BACKUP_DIR}."
   if ! mv ${NGINX_SSL_DOMAIN_DIR} ${NGINX_SSL_DOMAIN_BACKUP_DIR} ; then
      MESSAGE="Failed to backup old certificate folder"
      exit 1
   fi

   # Recreate certificates domain dir
   log "Recreating domain certificates dir ${NGINX_SSL_DOMAIN_DIR}."
   if ! mkdir ${NGINX_SSL_DOMAIN_DIR} ; then
      MESSAGE="Failed to backup old certificate folder"
      exit 1
   fi

   # Copy new certificates to domain dir
   log "Copying new certificates to domain certificates dir ${NGINX_SSL_DOMAIN_DIR}."
   if ! cp ${LETSENCRYPT_DOMAIN_DIR}/* ${NGINX_SSL_DOMAIN_DIR}/ ; then
      MESSAGE="Failed to backup old certificate folder"
      exit 1
   fi
}

renew_certificates() {
   # Renew certificates
   log "Executing automated renewal of certificates."
   if ! letsencrypt renew -nvv --standalone > ${LETSENCRYPT_LOG_DIR}/renew.log 2>&1 ; then
      MESSAGE="Automated renewal of domain certificates failed. Check ${LETSENCRYPT_LOG_DIR}/renew.log for details."
      exit 1
   fi

   ALL_SKIPPED_LINE="No renewals were attempted"
   if ! tail ${LETSENCRYPT_LOG_DIR}/renew.log | grep "${ALL_SKIPPED_LINE}" > /dev/null 2>&1 ; then
      log "One or more certificates needs to be renewed"
      for DOMAIN in ${LETSENCRYPT_DOMAINS}; do
         SKIPPED_LINE="${DOMAIN}/fullchain.pem (skipped)"
         if ! tail ${LETSENCRYPT_LOG_DIR}/renew.log | grep "${SKIPPED_LINE}" > /dev/null 2>&1 ; then
            log "Certificate for domain ${DOMAIN} needes to be renewed"
            backup_old_and_activate_new_certificate "${DOMAIN}"
         else
            log "Certificate for domain ${DOMAIN} does not needed renewal"
         fi
      done
      MESSAGE="One or more certificates renewed successfully"
   else
      log "No certificates needed renewal"
      EMAIL_ACTIVE=false
   fi
}

echo "###  Starting certificate renewal process at $(date +'%F %T.%3N %Z')  ###"

trap handle_error ERR
trap handle_exit EXIT

check_nginx_container_running

stop_nginx_container

renew_certificates

start_nginx_container

exit 0;
