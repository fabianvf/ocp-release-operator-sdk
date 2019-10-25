FROM openshift/origin-release:golang-1.12 AS builder

ENV GO111MODULE=on \
    GOFLAGS=-mod=vendor

COPY . /go/src/github.com/operator-framework/operator-sdk
RUN cd /go/src/github.com/operator-framework/operator-sdk \
 && rm -rf vendor/github.com/operator-framework/operator-sdk \
 && make build/operator-sdk-dev-x86_64-linux-gnu VERSION=dev

FROM registry.access.redhat.com/ubi8/ubi

# Install python dependencies
# Ensure fresh metadata rather than cached metadata in the base by running
# yum clean all && rm -rf /var/yum/cache/* first
RUN yum clean all && rm -rf /var/cache/yum/* \
 && yum -y update \
 && yum install -y python36-devel gcc python3-pip python3-setuptools \
 # todo: remove inotify-tools. More info: See https://github.com/operator-framework/operator-sdk/issues/2007
 && yum install -y https://rpmfind.net/linux/fedora/linux/releases/30/Everything/x86_64/os/Packages/i/inotify-tools-3.14-16.fc30.x86_64.rpm \
 && pip3 install --no-cache-dir --ignore-installed ipaddress \
      ansible-runner==1.3.4 \
      ansible-runner-http==1.0.0 \
      openshift==0.8.9 \
      ansible~=2.8 \
 && yum remove -y gcc python36-devel \
 && yum clean all \
 && rm -rf /var/cache/yum

RUN mkdir -p /etc/ansible \
    && echo "localhost ansible_connection=local" > /etc/ansible/hosts \
    && echo '[defaults]' > /etc/ansible/ansible.cfg \
    && echo 'roles_path = /opt/ansible/roles' >> /etc/ansible/ansible.cfg \
    && echo 'library = /usr/share/ansible/openshift' >> /etc/ansible/ansible.cfg

ENV OPERATOR=/usr/local/bin/ansible-operator \
    USER_UID=1001 \
    USER_NAME=ansible-operator\
    HOME=/opt/ansible


COPY --from=builder /go/src/github.com/operator-framework/operator-sdk/build/operator-sdk-dev-x86_64-linux-gnu ${OPERATOR}
COPY bin /usr/local/bin
COPY library/k8s_status.py /usr/share/ansible/openshift/

RUN /usr/local/bin/user_setup

# Ensure directory permissions are properly set
RUN mkdir -p ${HOME}/.ansible/tmp \
 && chown -R ${USER_UID}:0 ${HOME} \
 && chmod -R ug+rwx ${HOME}

ADD https://github.com/krallin/tini/releases/latest/download/tini /tini
RUN chmod +x /tini

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint"]

USER ${USER_UID}
