# Dockerfile to build the matrixdotorg/synapse docker images.
#
# To build the image, run `docker build` command from the root of the
# synapse repository:
#
#    docker build -f docker/Dockerfile .
#
# There is an optional PYTHON_VERSION build argument which sets the
# version of python to build against: for example:
#
#    docker build -f docker/Dockerfile --build-arg PYTHON_VERSION=3.6 .
#

ARG PYTHON_VERSION=3.8

###
### Stage 0: builder
###
FROM docker.io/python:${PYTHON_VERSION}-slim as builder

# install the OS build deps
RUN apt-get update && apt-get install -y \
    build-essential \
    libffi-dev \
    libjpeg-dev \
    libpq-dev \
    libssl-dev \
    libwebp-dev \
    libxml++2.6-dev \
    libxslt1-dev \
    openssl \
    rustc \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy just what we need to pip install
COPY synapse/scripts /synapse/scripts/
COPY synapse/MANIFEST.in synapse/README.rst synapse/setup.py synapse/synctl /synapse/
COPY synapse/synapse/__init__.py /synapse/synapse/__init__.py
COPY synapse/synapse/python_dependencies.py /synapse/synapse/python_dependencies.py

# To speed up rebuilds, install all of the dependencies before we copy over
# the whole synapse project so that we this layer in the Docker cache can be
# used while you develop on the source
#
# This is aiming at installing the `install_requires` and `extras_require` from `setup.py`
RUN pip install --prefix="/install" --no-warn-script-location \
    /synapse[all]

# Copy over the rest of the project
COPY synapse/synapse /synapse/synapse/

# Install the synapse package itself and all of its children packages.
#
# This is aiming at installing only the `packages=find_packages(...)` from `setup.py
RUN pip install --prefix="/install" --no-deps --no-warn-script-location /synapse

###
### Stage 1: runtime
###

FROM docker.io/python:${PYTHON_VERSION}-slim as base-image

LABEL org.opencontainers.image.url='https://matrix.org/docs/projects/server/synapse'
LABEL org.opencontainers.image.documentation='https://github.com/matrix-org/synapse/blob/master/docker/README.md'
LABEL org.opencontainers.image.source='https://github.com/matrix-org/synapse.git'
LABEL org.opencontainers.image.licenses='Apache-2.0'

RUN apt-get update && apt-get install -y \
    curl \
    gosu \
    libjpeg62-turbo \
    libpq5 \
    libwebp6 \
    xmlsec1 \
    libjemalloc2 \
    libssl-dev \
    openssl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local
COPY synapse/docker/start.py /start.py
COPY synapse/docker/conf /conf

VOLUME ["/data"]

EXPOSE 8008/tcp 8009/tcp 8448/tcp

ENTRYPOINT ["/start.py"]

HEALTHCHECK --start-period=5s --interval=15s --timeout=5s \
    CMD curl -fSs http://localhost:8008/health || exit 1

FROM base-image

RUN apt-get update \
    && apt-get install -y \
    tini \
    ca-certificates \
    nginx \
    curl \
    jq \
    openssl \
    privoxy \
    iproute2 \
    wget \
    sqlite3

RUN wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.12.2/yq_linux_arm \
    && chmod a+x /usr/local/bin/yq
RUN pip install --prefix="/install" --no-warn-script-location pyyaml

ADD ./www /var/www
ADD ./cert.conf /etc/ssl/cert.conf
ADD ./priv-config-forward-onion /root
ADD ./priv-config-forward-all /root
ADD ./docker_entrypoint.sh /usr/local/bin/docker_entrypoint.sh
RUN chmod a+x /usr/local/bin/docker_entrypoint.sh
ADD ./check-federation.sh /usr/local/bin/check-federation.sh
RUN chmod a+x /usr/local/bin/check-federation.sh
ADD ./user-signups-off.sh /usr/local/bin/user-signups-off.sh
RUN chmod a+x /usr/local/bin/user-signups-off.sh
ADD ./configurator.py /configurator.py
RUN chmod a+x /configurator.py

WORKDIR /data

RUN mkdir /run/nginx

EXPOSE 8448 443 80

ENTRYPOINT ["/usr/local/bin/docker_entrypoint.sh"]
