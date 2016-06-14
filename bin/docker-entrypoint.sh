#!/bin/bash

# step: switch on debugging mode?
[[ "${DEBUG}" == "True" ]] && set -x

# the vault binary
VAULT="/opt/bin/vault"
# the kuberctl binary
KUBECTL="/opt/bin/kubectl"
# the vault configuration failed
VAULT_CONFIG=${VAULT_CONFIG:-""}
# the default vault configuration file
VAULT_DEFAULT_CONFIG="/etc/vault/vault.default.hcl"
# a kube configuration used to speak to the api
KUBE_CONFIG=${KUBE_CONFIG:-""}
# a kube token to use when injecting the unsealing key back into kubernetes
KUBE_TOKEN=${KUBE_TOKEN:-""}
# the namespace to inject the kubernetes secret unsealing key
KUBE_NAMESPACE=${KUBE_NAMESPACE:-"vault"}
# create a default password for user above
VAULT_DEFAULT_PASSWORD=${VAULT_DEFAULT_PASSWORD:-""}
# a file containing the default password
VAULT_DEFAULT_PASSWORD_FILE=${VAULT_DEFAULT_PASSWORD_FILE:-""}
# the vault root key
VAULT_ROOT_KEY=${VAULT_ROOT_KEY:-""}
# the vault service protocol
VAULT_PROTOCOL=${VAULT_PROTOCOL:-"https"}
# the vault binding interface
VAULT_BIND_ADDR=${VAULT_BIND_ADDR:-"127.0.0.1"}
# the vault binding port
VAULT_BIND_PORT=${VAULT_BIND_PORT:-"8200"}
# the vault address - to use it's always local
VAULT_ADDR=${VAULT_PROTOCOL}://${VAULT_BIND_ADDR}:${VAULT_BIND_PORT}
# whether to bypass tls
VAULT_SKIP_VERIFY=${VAULT_SKIP_VERIFY:-true}
# the vault unsealing key
VAULT_UNSEAL_KEY=${VAULT_UNSEAL_KEY:-""}
# the vault unsealing file
VAULT_UNSEAL_FILE=${VAULT_UNSEAL_FILE:-"/etc/secrets/vault-unseal.key"}
# indicates with the user provisioning required
VAULT_FIRST_RUN=0
# the vault hostname
VAULT_HOSTNAME=${VAULT_HOSTNAME:-""}
# whether to rollback
VAULT_ROLLBACK=${VAULT_ROLLBACK:-"0"}
# the vault pid

export VAULT_ADDR=$VAULT_ADDR

[ -n "$VAULT_SKIP_VERIFY" ] && export VAULT_SKIP_VERIFY=${VAULT_SKIP_VERIFY}

failed() {
  echo "[error] $@" && exit 1
}

annonce() {
  echo "[info] $@"
}

eternal_sleep() {
  wait ${VAULT_PID}
}

sleep_for() {
  local timer=$1
  annonce "sleeping for ${timer} seconds"
  for ((i=0; i<$timer; i++)); do
    echo -n "." && sleep 1
  done
}

inject_kubernetes() {
  [ -n "${KUBE_CONFIG}" ] && return 0
  [ -n "${KUBE_TOKEN}"  ] && return 0
  return 1
}

vault_initialized() {
  ${VAULT} init -check && return 0 || return 1
}

vault_sealed() {
  ${VAULT} status 2>&1 | grep -q "Sealed: true" && return 0 || return 1
}

provision_kubernetes_secret() {
  annonce "injecting the unsealing master key as a secret, namespace: ${KUBE_NAMESPACE}"
  _tmpfile=$(mktemp)
  cat <<EOF > ${_tmpfile}
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-unseal
  namespace: ${KUBE_NAMESPACE}
data:
  vault-unseal.key: $(echo "${VAULT_UNSEAL_KEY}" | base64 -w 0)
EOF
  # step: build the command line options
  [ -n "${KUBE_CONFIG}" ] && options="--kubeconfig=${KUBE_CONFIG}"
  [ -n "${KUBE_TOKEN}"  ] && options="--token=${KUBE_TOKEN}"
  # step: attempt to inject the secret into kubernetes
  if ${KUBECTL} -s https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT} --insecure-skip-tls-verify=true ${options} replace -f ${_tmpfile}; then
    annonce "successfully injected the unsealing key as kubernetes secret"
  else
    annonce "failed to inject the master key as kubernetes secret, sorry, but probably your fault!"
    annonce "master key: ${VAULT_UNSEAL_KEY}"
  fi
}

# provision_configuration creates the configuration file
provision_configuration() {
  # step: if a vault configuration has been supplied we use that
  if [ -n "${VAULT_CONFIG}" ]; then
    annonce "using the vault configuration file: ${VAULT_CONFIG}"
  else
    annonce "using the default vault config: ${VAULT_DEFAULT_CONFIG}"
    VAULT_CONFIG=${VAULT_DEFAULT_CONFIG}
  fi

  # step: update the advertized address in the config file
  [ -z "${VAULT_HOSTNAME}" ] && VAULT_HOSTNAME=$(hostname -i)
  sed -i "s/HOSTNAME/${VAULT_HOSTNAME}/" ${VAULT_CONFIG} || failed "unable to update the vault config hostname field"
  sed -i "s/ROLLBACK/${VAULT_ROLLBACK}/" ${VAULT_CONFIG} || failed "unable to update vault config rollback variable"
  sed -i "s/VAULT_BIND_ADDR/${VAULT_BIND_ADDR}/" ${VAULT_CONFIG} || failed "unable to update vault config bind addressk variable"
  sed -i "s/VAULT_BIND_PORT/${VAULT_BIND_PORT}/" ${VAULT_CONFIG} || failed "unable to update vault config bind port variable"

  [ "${DEBUG}" == "True" ] && cat ${VAULT_CONFIG}
}

provision_vault_initialization() {
  # step: check if the service is initialized
  if ! vault_initialized; then
    VAULT_FIRST_RUN=1
    # step: attempt to initialize the service
    _tmpfile=$(mktemp /tmp/vault.XXXXXX)
    annonce "the vault service is uninitialized, attempting to initialize now"
    $VAULT init -key-shares=1 -key-threshold=1 > $_tmpfile && sleep_for 30 || failed "unable to initialize the vault service"
    # step: check the service was initialized
    vault_initialized || failed "unable to initialize the vault service"
    # step: extract the vault root and unsealing key
    VAULT_UNSEAL_KEY=$(awk '/^Key 1/ { print $NF }' ${_tmpfile})
    VAULT_ROOT_KEY=$(awk '/^Initial Root Token/ { print $NF }' ${_tmpfile})
    # step: check we were able to extract the keys
    [ -z "${VAULT_UNSEAL_KEY}" ] && failed "unable to extract the unsealing key vault service"
    [ -z "${VAULT_ROOT_KEY}" ] && failed "unable to extract the root key vault service"
    # step: export the root key
    export VAULT_TOKEN=${VAULT_ROOT_KEY}
    # step: inject the unsealing key as a kubernetes secret?
    if inject_kubernetes; then
      provision_kubernetes_secret
    else
      # step: print out the master key
      annonce "Master Key: ${VAULT_UNSEAL_KEY}"
      annonce "NOTE: you MUST rekey the master key, do NOT use this unseal key"
      annonce "$# vault rekey -key-shares=1 -key-threshold=1 ${VAULT_UNSEAL_KEY}"
    fi
  fi
}

# provision_unsealing is responsible for unsealing the vault service
provision_unsealing() {
  # step: check the vault service is sealed
  if vault_sealed; then
    if [ -z "${VAULT_UNSEAL_KEY}" ]; then
      [ -f "${VAULT_UNSEAL_FILE}" ] || failed "neither the unseal key is set or a unsealing file exists"
      VAULT_UNSEAL_KEY=$(cat ${VAULT_UNSEAL_FILE})
    fi
    # step: attempt to unseal the service
    for ((i=0; i<5; i++)); do
      annonce "attempting to unseal the vault service, attempt: ${i}"
      $VAULT unseal ${VAULT_UNSEAL_KEY} && break
      sleep_for 5
    done
    # step: check the service was unsealed
    vault_sealed && failed "unable to unseal vault service"
    annonce "successfully unsealed the vault service"
  else
    annonce "vault service is already unsealed, skipping the unsealing process"
  fi
}

# provision_users creates users required on the first-run
provision_users() {
  if [ ${VAULT_FIRST_RUN} == 1 ]; then
    # skip if not user being provisioned
    password=""
    if [ -n "${VAULT_DEFAULT_PASSWORD_FILE}" ]; then
      password=$(cat ${VAULT_DEFAULT_PASSWORD_FILE})
    fi
    if [ -z "${password}" ]; then
      password=${VAULT_DEFAULT_PASSWORD}
    fi
    # skip: if empty generate a random one
    if [ -z "${password}" ]; then
      password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)
      annonce "creating random password: ${password}"
    fi
    for ((i=0; i<10; i++)); do
      annonce "attempting to provision the initial root users post first-run, attempt: ${i}"
      if $VAULT auth-enable userpass; then
        annonce "successfully added the userpass backend"
        break
      fi
      annonce "unable to create the userpass authentication backend"
      sleep_for 5
    done
    annonce "attempting to adding the admin user"
    $VAULT write auth/userpass/users/admin password=${password} policies=root || annonce "unable to provision user: admin"
  fi
}

# provision_vault starts the vault process in the background
provision_vault() {
  annonce "starting the vault service in the background, config: ${VAULT_CONFIG}"
  $VAULT server -config ${VAULT_CONFIG} 2>&1 &
  [ $? -ne 0 ] && failed "unable to start the vault service in the background, exitting"
  VAULT_PID=$!
  sleep_for 5
  annonce "the vault service is running on pid: ${VAULT_PID}"
}

# provision is responsible for the lifecycle of the vault service
provision() {
  annonce "starting the vault service, address: $VAULT_ADDR"
  # step: provision th configuration
  provision_configuration
  # step: start the vault service
  provision_vault
  # step: is the service initialized?
  provision_vault_initialization
  # step: unseal the service
  provision_unsealing
  # step: provision user tokens
  provision_users
  # step: step into the background
  eternal_sleep
}

provision
