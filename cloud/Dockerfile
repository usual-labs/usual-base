# Usual Base on Node, to run yourself: a SQLite file and the Bases' git repositories, all under /data.
# Build from the repository root, since the server also serves ../cli and ../skills:
#   docker build -f cloud/Dockerfile -t usual-base .
# Settings and a run command are in cloud/README.md.

FROM node:22-slim AS build
WORKDIR /src/cloud
COPY cloud/package.json cloud/package-lock.json ./
RUN npm ci
COPY cli/ /src/cli/
COPY skills/ /src/skills/
COPY cloud/ ./
RUN npm run build:node && npm prune --omit=dev

FROM node:22-slim
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir /data && chown node:node /data
WORKDIR /app
COPY --from=build /src/cloud/package.json ./
COPY --from=build /src/cloud/node_modules node_modules/
COPY --from=build /src/cloud/dist dist/
COPY --from=build /src/cloud/migrations migrations/
ENV NODE_ENV=production DATA_DIR=/data PORT=8080
USER node
VOLUME /data
EXPOSE 8080
CMD ["node", "dist/server.mjs"]
