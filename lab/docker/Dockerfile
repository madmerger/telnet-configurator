# SSH lab with password and public key auth (needs a root sshd, hence a container).
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server perl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd \
 && useradd -m -s /bin/sh cbtadmin \
 && echo 'cbtadmin:cbt-pass' | chpasswd
COPY sim /opt/sim
COPY lab/docker/entrypoint.sh /entrypoint.sh
EXPOSE 2401 2402 2403
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
