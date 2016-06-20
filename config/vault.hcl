backend "%%VAULT_BACKEND%%" {
}

listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = %%TLS_DISABLE%%
  tls_cert_file = "%%TLS_CERT_FILE%%"
  tls_key_file = "%%TLS_KEY_FILE%%"
}

disable_mlock = true
