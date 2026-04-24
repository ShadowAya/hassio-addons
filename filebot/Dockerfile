FROM ghcr.io/home-assistant/base:latest

ARG BUILD_ARCH

RUN apk add --no-cache \
        openjdk17-jre-headless \
        inotify-tools \
        wget \
        curl \
        mediainfo \
        jq \
        ntfs-3g \
        fuse-exfat \
        exfatprogs

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
