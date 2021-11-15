FROM alpine:latest

RUN echo "http://dl-cdn.alpinelinux.org/alpine/v3.13/main" > /etc/apk/repositories && \
	echo "http://dl-cdn.alpinelinux.org/alpine/v3.13/community" >> /etc/apk/repositories

RUN apk add --no-cache \
	bash \
	gettext \
	apache2-utils \
	certbot \
	openssl \
	nginx~=1.18

COPY ./scripts/bash/split-to-lines.sh /root/
COPY ./scripts/bash/envsubst-files.sh /root/

COPY ./nginx-*.template /root/

COPY ./entrypoint.sh /root/

RUN chmod 755 /root/*.sh

ENTRYPOINT ["/root/entrypoint.sh"]
