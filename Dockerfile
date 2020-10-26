FROM alpine:latest

RUN apk add --no-cache bash

COPY entrypoint.sh /
COPY ktools.sh /

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "wrapper" ]