FROM fedora:23
MAINTAINER Rohith <gambol99@gmail.com>

ENV VAULT_VERSION 0.5.3
ENV KUBECTL_VERSION 1.2.4

RUN dnf install -y wget && mkdir -p /opt/bin
RUN wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip -O /tmp/vault_${VAULT_VERSION}_linux_amd64.zip
# I'd like to use alpine linux but the kubectl is not statically linked
RUN wget https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl -O /opt/bin/kubectl

RUN dnf install -y unzip hostname && \
    cd /tmp && \
    unzip /tmp/vault_${VAULT_VERSION}_linux_amd64.zip && \
    rm -f /tmp/vault_${VAULT_VERSION}_linux_amd64.zip && \
    mv /tmp/vault /opt/bin/vault && \
    chmod +x /opt/bin/kubectl /opt/bin/vault

ADD config/vault.default.hcl /etc/vault/vault.default.hcl
ADD bin/docker-entrypoint.sh /docker-entrypoint.sh

EXPOSE 8200

ENTRYPOINT [ "/docker-entrypoint.sh" ]
