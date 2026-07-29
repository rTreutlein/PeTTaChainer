FROM swipl:9.3.33

ARG DEBIAN_FRONTEND=noninteractive
ARG UV_VERSION=0.8.22

RUN sed -i \
        -e 's|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/20251103T204410Z|g' \
        -e 's|http://deb.debian.org/debian|http://snapshot.debian.org/archive/debian/20251103T204410Z|g' \
        /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends --no-upgrade \
        build-essential \
        ca-certificates \
        git \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/tmp/myclaw-home \
    UV_CACHE_DIR=/opt/myclaw/uv-cache

COPY .myclaw/pydistutils.cfg /tmp/myclaw-home/.pydistutils.cfg

RUN mkdir -p "$HOME" "$UV_CACHE_DIR" /tmp/myclaw-egg-info \
    && chmod 1777 "$HOME" "$UV_CACHE_DIR" /tmp/myclaw-egg-info \
    && python3 -m pip install --break-system-packages --no-cache-dir "uv==$UV_VERSION" \
    && python3 --version \
    && swipl --version \
    && uv --version

ENTRYPOINT []
CMD ["bash"]
