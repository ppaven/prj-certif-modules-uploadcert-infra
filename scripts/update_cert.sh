#!/bin/bash
#
if [ $# -ne 2 ]
then
  echo 
  echo "Usage : $0 <Cert_name> <Thumbprint>"
  echo 
  exit 1
fi
CERT_NAME=$1
THUMBPRINT=$2
SRC_DIR=/var/lib/waagent
CERTS_DIR=/etc/ssl/certs
PRV_DIR=/etc/ssl/private
#

cp -p ${CERTS_DIR}/${CERT_NAME}.crt ${CERTS_DIR}/${CERT_NAME}.crt.old
cp -p ${PRV_DIR}/${CERT_NAME}.key ${PRV_DIR}/${CERT_NAME}.key.old

if [ -f ${SRC_DIR}/${THUMBPRINT}.crt ]
then
  cat  ${SRC_DIR}/${THUMBPRINT}.crt > ${CERTS_DIR}/${CERT_NAME}.crt
  curl https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt 2>/dev/null >>${CERTS_DIR}/${CERT_NAME}.crt
fi
if [ -f ${SRC_DIR}/${THUMBPRINT}.prv ]
then
  chmod u+w ${PRV_DIR}/${CERT_NAME}.key
  cat  ${SRC_DIR}/${THUMBPRINT}.prv > ${PRV_DIR}/${CERT_NAME}.key
  chmod u-w ${PRV_DIR}/${CERT_NAME}.key
fi

if [ -d /etc/apache2 ]
then
  apachectl graceful
fi
if [ -d /etc/nginx ]
then
  /bin/systemctl reload nginx
fi
