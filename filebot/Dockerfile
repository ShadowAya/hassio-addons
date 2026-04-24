ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG BUILD_ARCH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
        inotify-tools \
        wget \
        curl \
        mediainfo \
        jq \
        ntfs-3g \
        exfat-fuse \
        exfatprogs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
