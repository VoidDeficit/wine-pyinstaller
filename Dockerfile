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
      xvfb cabextract winbind \
 && mkdir -pm755 /etc/apt/keyrings \
 && wget -qO /etc/apt/keyrings/winehq.key https://dl.winehq.org/wine-builds/winehq.key \
 && echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq.key] https://dl.winehq.org/wine-builds/ubuntu/ jammy main" \
      > /etc/apt/sources.list.d/winehq.list \
 && apt-get update -qy \
 && apt-get install -y winehq-stable \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# ── Initialise Wine prefix ────────────────────────────────────────────────────
# timeout kills xvfb-run+wineboot if they hang on RpcSs (normal in headless containers)
RUN timeout 20 xvfb-run --server-args="-screen 0 1024x768x24" wineboot --init || true; \
    wineserver -k 2>/dev/null || true; sleep 2

# ── Install Python 3.11 inside Wine ──────────────────────────────────────────
RUN wget -q "https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-amd64.exe" \
      -O /tmp/py.exe \
 && timeout 300 xvfb-run --server-args="-screen 0 1024x768x24" \
      wine /tmp/py.exe /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 || true; \
    wineserver -k 2>/dev/null || true; sleep 2; \
    test -f "/wine/drive_c/Program Files/Python311/python.exe"; \
    rm -f /tmp/py.exe

# ── Upgrade pip + install PyInstaller ────────────────────────────────────────
RUN timeout 300 xvfb-run --server-args="-screen 0 1024x768x24" \
      wine "C:\\Program Files\\Python311\\python.exe" -m pip install \
        --upgrade pip "pyinstaller==${PYINSTALLER_VERSION}" || true; \
    wineserver -k 2>/dev/null || true; sleep 2; \
    test -f "/wine/drive_c/Program Files/Python311/Scripts/pyinstaller.exe"

# ── Wrapper scripts (rely on DISPLAY set by entrypoint) ──────────────────────
RUN set -e; \
    PY='C:\Program Files\Python311\python.exe'; \
    printf '#!/bin/sh\nexec wine "%s" "$@"\n' "$PY" \
      > /usr/local/bin/python; \
    printf '#!/bin/sh\nexec wine "C:\\Program Files\\Python311\\Scripts\\pip.exe" "$@"\n' \
      > /usr/local/bin/pip; \
    printf '#!/bin/sh\nexec wine "C:\\Program Files\\Python311\\Scripts\\pyinstaller.exe" "$@"\n' \
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
