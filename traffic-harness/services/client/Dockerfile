FROM debian:bookworm-slim

# Shared tools image for the client and attacker boxes. In this phase both run only
# benign generators. No em dashes anywhere.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates openssh-client sshpass default-mysql-client dnsutils coreutils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /gen
