FROM alpine:latest

RUN    apk update \
    && apk add bash \
    && apk add nginx \
    && apk add certbot \
    && rm -rf /var/cache/apk/*

COPY ./scripts/bash/split-to-lines.sh /root/
COPY ./scripts/bash/envsubst-files.sh /root/

COPY ./entrypoint.sh /root/

RUN chmod 755 /root/*.sh

ENTRYPOINT ["/root/entrypoint.sh"]
