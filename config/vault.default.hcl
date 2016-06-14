
backend "file" {
  path = "vault_safe"
}

listener "tcp" {
  address = "VAULT_BIND_ADDR:VAULT_BIND_PORT"
  tls_disable = 1
}

disable_mlock = true
