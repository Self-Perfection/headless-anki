FROM python:3.13-slim

ARG ANKICONNECT_VERSION=25.11.9.0
# aqt/anki are published on PyPI; this is the same code the official Linux
# "launcher" installs into a venv at first run, but pinned and baked in here so
# the image is reproducible and needs no network at runtime.
ARG ANKI_VERSION=25.9.4

# Runtime shared libraries needed by PyQt6 + QtWebEngine when running headless
# under the offscreen platform plugin. The GTK/cairo/pango theme stack is
# deliberately omitted -- it is not loaded under offscreen.
RUN apt-get update && apt-get install --no-install-recommends -y \
        jq libgl1 libegl1 libglib2.0-0t64 \
        libnss3 libfontconfig1 libfreetype6 libdbus-1-3 \
        libcups2t64 libgssapi-krb5-2 libasound2t64 libatomic1 \
        libxcb-xinerama0 libxcb-cursor0 libxcb-icccm4 libxcb-keysyms1 \
        libxcb-shape0 libxcb-xkb1 \
        libxcomposite1 libxdamage1 libxtst6 libxfixes3 libxi6 libxrandr2 \
        libxrender1 libxkbcommon0 libxkbcommon-x11-0 libxkbfile1 \
    && rm -rf /var/lib/apt/lists/*

# Anki desktop (aqt pulls anki + PyQt6 + QtWebEngine). PyQt6[qt] ships the whole
# of Qt6; strip the leaf Qt modules nothing in Anki references (3D, charts, SQL,
# designer, pdf, ...). Modules imported by aqt (QtMultimedia, QtQuick, ...) and
# pulled in by QtWebEngineCore (QtPositioning, QtWebChannel, QtQml*) are kept.
RUN pip install --no-cache-dir "aqt[qt]==${ANKI_VERSION}" \
    && SP="$(python -c 'import site; print(site.getsitepackages()[0])')" \
    && L="$SP/PyQt6/Qt6/lib" \
    && for m in 3D Quick3D Pdf Designer Charts DataVisualization Graphs \
               Sensors SerialPort SerialBus Modbus Bluetooth Nfc Location \
               Sql Test Help Scxml RemoteObjects WebView TextToSpeech \
               SpatialAudio; do \
           rm -f "$L"/libQt6${m}*.so* "$SP"/PyQt6/Qt6${m}*.abi3.so; \
       done \
    && rm -rf "$SP/PyQt6/Qt6/plugins/sqldrivers" \
              "$SP/PyQt6/Qt6/plugins/sensors" \
              "$SP/PyQt6/Qt6/plugins/geoservices" \
              "$SP/PyQt6/Qt6/plugins/texttospeech"

# AnkiConnect plugin (curl is install-only and purged afterwards).
RUN apt-get update && apt-get install --no-install-recommends -y curl \
    && mkdir -p /app/anki-connect \
    && curl -fL "https://git.sr.ht/~foosoft/anki-connect/archive/${ANKICONNECT_VERSION}.tar.gz" \
        | tar -xz -C /app/anki-connect --strip-components=1 \
    && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# Anki profile + AnkiConnect wiring, listening on all interfaces with open CORS
# so the JSON API is reachable from outside the container with a plain request.
ADD data /data
RUN mkdir -p /data/addons21 \
    && ln -sf /app/anki-connect/plugin /data/addons21/AnkiConnectDev \
    && jq '.webBindAddress = "0.0.0.0" | .webCorsOriginList = ["*"]' \
        /app/anki-connect/plugin/config.json > /tmp/c \
    && mv /tmp/c /app/anki-connect/plugin/config.json \
    && useradd -m anki && chown -R anki:anki /app /data
VOLUME /data

USER anki
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    QT_QPA_PLATFORM=offscreen

CMD ["python", "-c", "import sys; sys.argv = ['anki', '-b', '/data']; import aqt; aqt.run()"]
