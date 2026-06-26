FROM nginx:1.27-alpine

# Self-signed cert for TLS variety, plus static assets of differing sizes so HTTP
# flows vary in byte count (1 KB, 50 KB, 2 MB). No em dashes anywhere.
RUN apk add --no-cache openssl \
 && mkdir -p /etc/nginx/certs \
 && openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=web" \
      -keyout /etc/nginx/certs/self.key -out /etc/nginx/certs/self.crt \
 && head -c 1024    /dev/urandom | base64 > /usr/share/nginx/html/small.txt \
 && head -c 51200   /dev/urandom > /usr/share/nginx/html/medium.bin \
 && head -c 2097152 /dev/urandom > /usr/share/nginx/html/large.bin

COPY index.html /usr/share/nginx/html/index.html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80 443
