FROM alpine:3.4

RUN apk upgrade --no-cache && apk add --no-cache bash curl
RUN adduser -h /vault -D vault

WORKDIR /vault
EXPOSE 8200

ENV VAULT_VERSION 0.6.0
ENV KUBECTL_VERSION 1.3.7

RUN curl -s -o /tmp/vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && unzip /tmp/vault.zip -d /usr/bin; rm -f /tmp/vault.zip; chmod +x /usr/bin/vault
RUN curl -s -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl; chmod +x /usr/bin/kubectl

COPY config/vault.hcl /vault/vault.hcl
COPY bin/env.sh /vault/bin/env.sh
COPY bin/run.sh /vault/bin/run.sh
COPY bin/overlord.sh /vault/bin/overlord.sh

USER vault
ENTRYPOINT [ "/vault/bin/run.sh" ]
