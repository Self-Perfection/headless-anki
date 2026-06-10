FROM debian:13-slim

ARG ANKICONNECT_VERSION=25.11.9.0
ARG ANKI_VERSION=25.02.7
ARG QT_VERSION=6

# Runtime dependencies. Same set as before, but the five lib*-dev packages are
# replaced by their runtime shared-library equivalents (no headers needed at
# runtime), and wget/zstd/curl/git are dropped here -- they are install-time only
# and handled in the build layer below, so they never ship in the final image.
RUN apt-get update && apt-get install --no-install-recommends -y \
        ca-certificates jq mpv \
        libnss3 libxcb-xinerama0 libxcb-cursor0 \
        libxcomposite1 libxdamage1 libxtst6 libxkbcommon0 libxkbfile1 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN useradd -m anki && mkdir /app && chown anki /app
WORKDIR /app

# Download + install Anki and AnkiConnect in a single layer. The install-only
# tools (curl, zstd) are purged at the end of the layer, and the extracted Anki
# source tree is removed after install.sh copies it into /usr/local, so the
# ~490 MB bundle is no longer duplicated in the image.
RUN set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends -y curl zstd; \
    # Anki desktop bundle
    curl -fL -o /tmp/anki.tar.zst \
        "https://github.com/ankitects/anki/releases/download/${ANKI_VERSION}/anki-${ANKI_VERSION}-linux-qt${QT_VERSION}.tar.zst"; \
    mkdir -p /tmp/anki; \
    tar -x --zstd -f /tmp/anki.tar.zst -C /tmp/anki --strip-components=1; \
    ( cd /tmp/anki && sed 's/xdg-mime/#/' install.sh | sh - ); \
    rm -rf /tmp/anki /tmp/anki.tar.zst; \
    # AnkiConnect plugin
    mkdir -p /app/anki-connect; \
    curl -fL "https://git.sr.ht/~foosoft/anki-connect/archive/${ANKICONNECT_VERSION}.tar.gz" \
        | tar -xz -C /app/anki-connect --strip-components=1; \
    # drop install-only tooling
    apt-get purge -y curl zstd; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

COPY startup.sh /app/startup.sh

# Anki profile + AnkiConnect wiring (built ahead of time, no interactive setup).
ADD data /data
RUN mkdir -p /data/addons21 /export \
    && ln -sf /app/anki-connect/plugin /data/addons21/AnkiConnectDev \
    && jq '.webBindAddress = "0.0.0.0"' /app/anki-connect/plugin/config.json > /tmp/c \
    && mv /tmp/c /app/anki-connect/plugin/config.json \
    && chown -R anki:anki /app /data /export
VOLUME /data
VOLUME /export

USER anki

ENV ANKICONNECT_WILDCARD_ORIGIN="0"
ENV QMLSCENE_DEVICE=softwarecontext
ENV FONTCONFIG_PATH=/etc/fonts
ENV QT_XKB_CONFIG_ROOT=/usr/share/X11/xkb
ENV QT_QPA_PLATFORM="vnc"
# Could also use "offscreen"

CMD ["/bin/bash", "/app/startup.sh"]
