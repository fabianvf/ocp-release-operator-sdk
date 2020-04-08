FROM openshift/origin-release:golang-1.13 AS builder

ENV GO111MODULE=on \
    GOFLAGS=-mod=vendor

COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && rm -rf vendor/github.com/operator-framework/operator-sdk \
 && make build/operator-sdk-dev VERSION=dev

FROM registry.access.redhat.com/ubi8/ubi

RUN mkdir -p /etc/ansible \
    && echo "localhost ansible_connection=local" > /etc/ansible/hosts \
    && echo '[defaults]' > /etc/ansible/ansible.cfg \
    && echo 'roles_path = /opt/ansible/roles' >> /etc/ansible/ansible.cfg

ENV OPERATOR=/usr/local/bin/ansible-operator \
    USER_UID=1001 \
    USER_NAME=ansible-operator\
    HOME=/opt/ansible

# Install python dependencies
RUN yum clean all && rm -rf /var/cache/yum/* \
 && yum -y update \
 && FEDORA=$(case $(arch) in ppc64le|s390x) echo -n fedora-secondary ;; *) echo -n fedora/linux ;; esac) \
 && yum install -y https://dl.fedoraproject.org/pub/$FEDORA/releases/30/Everything/$(arch)/os/Packages/i/inotify-tools-3.14-16.fc30.$(arch).rpm \
 && yum install -y libffi-devel openssl-devel python3 python3-devel gcc python3-pip python3-setuptools \
 && pip3 install --upgrade setuptools pip \
 && pip3 install --no-cache-dir --ignore-installed ipaddress \
      ansible-runner==1.3.4 \
      ansible-runner-http==1.0.0 \
      openshift~=0.10.0 \
      ansible~=2.9 \
      jmespath \
 && yum remove -y gcc libffi-devel openssl-devel python3-devel \
 && yum clean all \
 && rm -rf /var/cache/yum

COPY release/ansible/ansible_collections ${HOME}/.ansible/collections/ansible_collections

COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/build/operator-sdk-dev ${OPERATOR}
COPY release/ansible/bin /usr/local/bin

RUN /usr/local/bin/user_setup

# Ensure directory permissions are properly set
RUN mkdir -p ${HOME}/.ansible/tmp \
 && chown -R ${USER_UID}:0 ${HOME} \
 && chmod -R ug+rwx ${HOME}

RUN TINIARCH=$(case $(arch) in x86_64) echo -n amd64 ;; ppc64le) echo -n ppc64el ;; *) echo -n $(arch) ;; esac) \
  && curl -L -o /tini https://github.com/krallin/tini/releases/latest/download/tini-$TINIARCH \
  && chmod +x /tini

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint"]

USER ${USER_UID}
