FROM kong:2.3-alpine

USER root

RUN apk update && apk --no-cache --update add dumb-init

USER kong

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
