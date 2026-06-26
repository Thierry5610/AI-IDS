FROM alpine:3.20

# Plain openssh server listening on the canonical port 22 (so passive topology
# mapping stays meaningful). Throwaway lab: password auth is fine. No em dashes.
RUN apk add --no-cache openssh openssh-sftp-server \
 && ssh-keygen -A \
 && adduser -D labuser \
 && echo "labuser:labpass" | chpasswd \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
