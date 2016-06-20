#!/usr/bin/bash

[[ ${DEBUG} == 'true' ]] && set -x

set -o errexit

source /vault/bin/env.sh
VAULT_UNSEAL_FILE='/vault/secrets/vault-unseal.key'


function failed() {
  (>&2 echo "[error] $@") && exit 1
}


function announce() {
  (>&2 echo "[info] $@")
}


function retry() {
  local counter=0
  until [[ ${counter} -ge 3 ]]
  do
    ${1} && break
    counter=$[${counter}+1]
    announce 'retrying again in 3 seconds.'
    sleep 1
  done
}


function vault_alive() {
  if ! curl -k -s ${VAULT_ADDR} > /dev/null; then
    announce "vault is not ready."
    return 1
  fi
  return 0
}


function vault_initialized() {
  vault init -check > /dev/null && return 0 || return 1
}


function vault_sealed() {
  vault status 2>&1 | grep -q 'Sealed: true' && return 0 || return 1
}


function create_kubernetes_secret() {
  announce 'writing unseal key to kubernetes secret.'

  cat <<EOF | kubectl --namespace=${KUBERNETES_NAMESPACE} replace -f - > /dev/null
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-unseal
data:
  vault-unseal.key: $(echo -n ${VAULT_UNSEAL_KEY} | base64 -w 0)
EOF

  if [[ ${?} -ne 0 ]]; then
    failed 'failed to write unseal key as kubernetes secret. You will need to start over.'
  else
    announce 'unseal key has been recorded as kubernetes secret.'
  fi
}


function initialize_vault() {
  announce 'initializing vault.'
  _tmpfile=$(mktemp /tmp/vault.XXXX)
  vault init -key-shares=1 -key-threshold=1 > ${_tmpfile}
  vault_initialized || failed 'failed to initialize vault.'

  VAULT_UNSEAL_KEY=$(awk -F': ' '/^Unseal Key 1/{e=0; print $2; exit} {e=1} END{exit e}' ${_tmpfile} || failed 'failed to read unseal key.')
  VAULT_ROOT_KEY=$(awk -F': ' '/^Initial Root Token/{e=0; print $2; exit} {e=1} END{exit e}' ${_tmpfile} || failed 'failed to read root key.')

  export VAULT_TOKEN=${VAULT_ROOT_KEY}
  announce 'vault has been initialized.'
}


function unseal_vault() {
  if [[ ! -n ${VAULT_UNSEAL_KEY} ]]; then
    [[ -f ${VAULT_UNSEAL_FILE} ]] || failed 'unable to find unseal key. Please specify vault unseal key.'
    VAULT_UNSEAL_KEY=$(cat ${VAULT_UNSEAL_FILE})
  fi

  announce 'unsealing vault.'
  if vault unseal ${VAULT_UNSEAL_KEY} 1> /dev/null; then
    announce 'vault has been unsealed.'
  else
    failed 'failed to unseal vault'
  fi
}


function create_admin_user() {
  announce 'creating an admin user.'
  local _p
  if [[ ! -n ${VAULT_ADMIN_PASSWORD} ]]; then
    _p=$(head -c18 < /dev/urandom | base64 | tr -d '\n')
    announce "no admin password specified. Generating random one (please change it): ${_p}"
  else
    _p=${VAULT_ADMIN_PASSWORD}
  fi

  if vault auth-enable userpass > /dev/null; then
    announce 'successfully enabled userpass auth backend.'
    vault write auth/userpass/users/admin password=${_p} policies=root || (announce 'unable to create admin user.'; return 1)
    return 0
  else
    announce 'unable to enable userpass auth backend.'
    return 1
  fi
}


while true; do
  if vault_alive; then
    if vault_initialized; then
      vault_sealed && unseal_vault
    else
      initialize_vault
      vault_sealed && unseal_vault
      retry create_admin_user
      create_kubernetes_secret
    fi
    sleep 30
  else
    announce 'sleeping for 10s.'
    sleep 10
  fi
done
