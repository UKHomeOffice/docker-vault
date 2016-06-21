#!/usr/bin/bash

[[ ${DEBUG} == 'true' ]] && set -x

source /vault/bin/env.sh

sed -i ${VAULT_CONFIG} \
  -e "s/%%VAULT_BACKEND%%/${VAULT_BACKEND}/" \
  -e "s/%%VAULT_BIND_ADDR%%/${VAULT_BIND_ADDR}/" \
  -e "s/%%TLS_DISABLE%%/${TLS_DISABLE}/" \
  -e "s|%%TLS_CERT_FILE%%|${TLS_CERT_FILE}|" \
  -e "s|%%TLS_KEY_FILE%%|${TLS_KEY_FILE}|"

vault server -config=${VAULT_CONFIG}
