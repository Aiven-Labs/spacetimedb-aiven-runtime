# SpacetimeDB server + your module, as one container for Aiven's application runtime.
#
#   docker build -t my-spacetimedb .
#   docker run -p 3000:3000 -e DB_NAME=my-game my-spacetimedb
#
# Build context is the repo root. Your TypeScript module goes in ./module (see README
# for Rust / C# modules, which are built outside and dropped in as a .wasm).

ARG SPACETIME_VERSION=v2.10.2

# The official image supplies both the server for the final stage and the CLI that
# builds the module, so the two always match.
FROM clockworklabs/spacetime:${SPACETIME_VERSION} AS spacetime-bin

# ---- build the module bundle ------------------------------------------------
FROM node:22-slim AS module-builder
COPY --from=spacetime-bin /usr/local/bin/spacetime /usr/local/bin/spacetime
WORKDIR /build
COPY module/ ./module/
RUN set -eu; \
    mkdir -p /out; \
    if [ -f module/module.wasm ]; then \
      echo "Using prebuilt module/module.wasm"; cp module/module.wasm /out/module.wasm; \
    else \
      cd module; \
      if [ -f package-lock.json ]; then npm ci; else npm install; fi; \
      spacetime build -p .; \
      cp dist/bundle.js /out/bundle.js; \
    fi

# ---- runtime ----------------------------------------------------------------
FROM spacetime-bin
COPY --from=module-builder /out/ /opt/app/
COPY entrypoint.sh /opt/app/entrypoint.sh

# Everything the server keeps - database, server keys, and the CLI identity that owns
# the database - lives under /data, so a mounted volume (if you have one) carries all of it.
USER root
RUN mkdir -p /data && chown spacetime:spacetime /data
USER spacetime

ENV HOME=/data/home \
    PORT=3000 \
    DB_NAME=app
VOLUME /data
EXPOSE 3000
ENTRYPOINT ["sh", "/opt/app/entrypoint.sh"]
