FROM node:18.3.0-buster as builder

# Fix for JS heap limit allocation issue
ENV NODE_OPTIONS="--max-old-space-size=4096"

RUN npm i -g npm@7.20.0
RUN npm install -g @nestjs/cli

RUN mkdir -p /app
WORKDIR /app

COPY ./package.json ./package.json

# Building ToolJet plugins
COPY ./plugins/package.json ./plugins/package-lock.json ./plugins/
RUN npm --prefix plugins install
COPY ./plugins/ ./plugins/
ENV NODE_ENV=production
RUN npm --prefix plugins run build
RUN npm --prefix plugins prune --production

# Building ToolJet server
COPY ./server/package.json ./server/package-lock.json ./server/
RUN npm --prefix server install --only=production
COPY ./server/ ./server/
RUN npm --prefix server run build

FROM debian:11

RUN apt-get update -yq \
    && apt-get install curl gnupg zip -yq \
    && curl -fsSL https://deb.nodesource.com/setup_18.3.0 | bash \
    && apt-get install nodejs npm -yq \
    && apt-get clean -y

ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN apt-get update && apt-get install -y postgresql-client freetds-dev libaio1 wget

# Install Instantclient Basic Light Oracle and Dependencies
WORKDIR /opt/oracle
RUN wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linuxx64.zip && \
    unzip instantclient-basiclite-linuxx64.zip && rm -f instantclient-basiclite-linuxx64.zip && \
    cd /opt/oracle/instantclient* && rm -f *jdbc* *occi* *mysql* *mql1* *ipc1* *jar uidrvci genezi adrci && \
    echo /opt/oracle/instantclient* > /etc/ld.so.conf.d/oracle-instantclient.conf && ldconfig
WORKDIR /

RUN mkdir -p /app

# copy npm scripts
COPY --from=builder /app/package.json ./app/package.json

# copy plugins dependencies
COPY --from=builder /app/plugins/dist ./app/plugins/dist
COPY --from=builder /app/plugins/client.js ./app/plugins/client.js
COPY --from=builder /app/plugins/node_modules ./app/plugins/node_modules
COPY --from=builder /app/plugins/packages/common ./app/plugins/packages/common
COPY --from=builder /app/plugins/package.json ./app/plugins/package.json

# copy server build
COPY --from=builder /app/server/package.json ./app/server/package.json
COPY --from=builder /app/server/.version ./app/server/.version
COPY --from=builder /app/server/entrypoint.sh ./app/server/entrypoint.sh
COPY --from=builder /app/server/node_modules ./app/server/node_modules
COPY --from=builder /app/server/templates ./app/server/templates
COPY --from=builder /app/server/scripts ./app/server/scripts
COPY --from=builder /app/server/dist ./app/server/dist

RUN chgrp -R 0 /app && chmod -R g=u /app
WORKDIR /app
# Dependencies for scripts outside nestjs
RUN npm install dotenv@10.0.0 joi@17.4.1

ENTRYPOINT ["./server/entrypoint.sh"]
