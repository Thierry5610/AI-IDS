FROM alpine:3.20

# Plain openssh server listening on the canonical port 22 (so passive topology
# mapping stays meaningful). Throwaway lab: password auth is fine. No em dashes.
#
# MaxAuthTries 1 forces each brute-force password attempt into its own TCP connection
# (sshd otherwise packs ~6 attempts per connection, collapsing them into one flow and
# starving the bruteforce class). patator, medusa and ncrack tolerate this; hydra hangs on
# the per-attempt disconnect, so the driver does not use hydra. MaxStartups is raised so the
# high-concurrency brute tools are not throttled. These only affect failed-auth behavior;
# benign gen_ssh logs in successfully on the first attempt and is unaffected.
RUN apk add --no-cache openssh openssh-sftp-server \
 && ssh-keygen -A \
 && adduser -D labuser \
 && echo "labuser:labpass" | chpasswd \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 1/' /etc/ssh/sshd_config \
 && ( grep -q '^MaxAuthTries' /etc/ssh/sshd_config || echo 'MaxAuthTries 1' >> /etc/ssh/sshd_config ) \
 && sed -i 's/^#\?MaxStartups.*/MaxStartups 200:30:400/' /etc/ssh/sshd_config \
 && ( grep -q '^MaxStartups' /etc/ssh/sshd_config || echo 'MaxStartups 200:30:400' >> /etc/ssh/sshd_config )

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
