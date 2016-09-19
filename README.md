# Vault in Kubernetes

[![Build Status](https://drone.digital.homeoffice.gov.uk/api/badges/UKHomeOffice/docker-vault/status.svg)](https://drone.digital.homeoffice.gov.uk/UKHomeOffice/docker-vault)

Vault in a docker image with all the necessary scripts to run vault in
kubernetes cluster.

There are two main components in this setup:
- Vault container - main vault process which listens in a tcp socket
- overlord container - bash script which takes care of unsealing vault,
  creating admin user and persisting vault unseal key


## Getting Started

First of all, you need to make sure that your kubernetes cluster supports
service accounts and that either the default or vault specific service account
has access to create kubernetes secrets. However this is only needed if you're
bootstrapping vault.

We are going assume that vault is being deployed into a namespace called vault.

In the below example we will use AWS DynamoDB as a backend. So for that, you
need to create a DynamoDB table and an IAM user with required permissions. Then
change environment variables accordingly in [vault deployment file](kube/vault-deployment.yaml).


### Configuration

* `VAULT_BACKEND` - defaults to `inmem`.
* `TLS_DISABLE` - defaults to 1.
* `VAULT_ADMIN_PASSWORD` - admin password that overlord sets when creating an
  admin user. If unset, overlord will generate a random one, which will be
  logged, so changing it is advisable.

Any other environment variables, which are supported by vault, can be set.


### Deployment

* Deploy an empty vault-unseal secret (will be updated by overlord script)
```
kubectl --namespace=vault create -f kube/vault-secrets.yaml
```

* Deploy vault pod (vault itself and overlord container)
```
kubectl --namespace=vault create -f kube/vault-deployment.yaml
```

* Deploy a kubernetes service endpoint for vault
```
kubectl --namespace=vault create -f kube/vault-svc.yaml
```


### Other

#### TLS

If you want to provide TLS certs, you can place them in `/vault/certs/cert.pem`
and `/vault/certs/key.pem`.


## Contributing

Contributions are most certainly welcome. If you want to introduce a breaking
change or any other major change, please raise an issue first to discuss.

## License

[MIT](LICENSE)
