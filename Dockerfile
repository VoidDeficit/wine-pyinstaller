FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEARCH=win64
ENV WINEDEBUG=fixme-all
ENV WINEPREFIX=/wine

ARG PYTHON_VERSION=3.11.9
ARG PYINSTALLER_VERSION=6.11.1

# ── System deps + Wine ────────────────────────────────────────────────────────
RUN dpkg --add-architecture i386 \
 && apt-get update -qy \
 && apt-get install -y --no-install-recommends \
      ca-certificates wget gnupg2 apt-transport-https \
      xvfb cabextract winbind unzip python3-pip \
 && mkdir -pm755 /etc/apt/keyrings \
 && wget -qO /etc/apt/keyrings/winehq.key https://dl.winehq.org/wine-builds/winehq.key \
 && echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq.key] https://dl.winehq.org/wine-builds/ubuntu/ jammy main" \
      > /etc/apt/sources.list.d/winehq.list \
 && apt-get update -qy \
 && apt-get install -y winehq-stable \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── Initialise Wine prefix ────────────────────────────────────────────────────
RUN xvfb-run --server-args="-screen 0 1024x768x24" wineboot --init; \
    wineserver -k 2>/dev/null; sleep 2

# ── Install Python 3.11 (embeddable zip — no MSI/COM/RpcSs needed) ───────────
RUN wget -q "https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-embed-amd64.zip" \
      -O /tmp/py.zip \
 && unzip -q /tmp/py.zip -d "/wine/drive_c/Python311" \
 && sed -i 's/#import site/import site/' "/wine/drive_c/Python311/python311._pth" \
 && mkdir -p "/wine/drive_c/Python311/Lib/site-packages" \
 && rm /tmp/py.zip

# ── Install pip + PyInstaller via Linux pip (no Wine execution during build) ──
# pip/setuptools/wheel are pure Python — install directly into Wine's site-packages
RUN pip3 install --break-system-packages \
      --target "/wine/drive_c/Python311/Lib/site-packages" \
      pip setuptools wheel
# Download Windows wheels for PyInstaller and its deps, then extract
RUN pip3 download \
      --dest /tmp/wheels \
      --platform win_amd64 \
      --python-version 311 \
      --implementation cp \
      --only-binary :all: \
      "pyinstaller==${PYINSTALLER_VERSION}" \
 && for whl in /tmp/wheels/*.whl; do \
      unzip -q -o "$whl" -d "/wine/drive_c/Python311/Lib/site-packages"; \
    done \
 && rm -rf /tmp/wheels

# ── Wrapper scripts (rely on DISPLAY set by entrypoint) ──────────────────────
# Use -m pip / -m PyInstaller so no .exe launcher is needed
RUN set -e; \
    printf '#!/bin/sh\nexec wine "C:\\\\Python311\\\\python.exe" "$@"\n' \
      > /usr/local/bin/python; \
    printf '#!/bin/sh\nexec wine "C:\\\\Python311\\\\python.exe" -m pip "$@"\n' \
      > /usr/local/bin/pip; \
    printf '#!/bin/sh\nexec wine "C:\\\\Python311\\\\python.exe" -m PyInstaller "$@"\n' \
      > /usr/local/bin/pyinstaller; \
    chmod +x /usr/local/bin/python \
              /usr/local/bin/pip \
              /usr/local/bin/pyinstaller

# ── Working directory — Wine sees this as Z:\workspace ───────────────────────
VOLUME /workspace
WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
