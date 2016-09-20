#!/bin/bash

[[ ${DEBUG} == 'true' ]] && set -x

: ${OVERLORD_DAEMON:=true}
: ${KUBERNETES_NAMESPACE:=$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)}
: ${VAULT_CONFIG:=/vault/vault.hcl}
: ${VAULT_BACKEND:=inmem}
: ${VAULT_SKIP_VERIFY:=false}
: ${TLS_DISABLE:=1}
: ${TLS_CERT_FILE:=/vault/certs/cert.pem}
: ${TLS_KEY_FILE:=/vault/certs/key.pem}
: ${RECOVERY_MODE:=1}
: ${VAULT_ADMIN_PASSWORD:=""}
: ${VAULT_UNSEAL_KEY:-""}

if [[ ${TLS_DISABLE} == '0' ]]; then
  export VAULT_ADDR='https://127.0.0.1:8200'
else
  export VAULT_ADDR='http://127.0.0.1:8200'
fi
