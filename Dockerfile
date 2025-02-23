FROM node:18 as builder

WORKDIR /usr/src/rendertron

COPY package.json package.json
COPY package-lock.json package-lock.json
COPY tsconfig.json tsconfig.json
COPY buf.work.yaml .
COPY buf.gen.yaml .
COPY src src
COPY proto proto

ENV PUPPETEER_SKIP_DOWNLOAD=true

RUN VERSION="1.4.0" && \
    curl -sSL \
    "https://github.com/bufbuild/buf/releases/download/v${VERSION}/buf-$(uname -s)-$(uname -m)" \
    -o "/usr/local/bin/buf" && \
    chmod +x "/usr/local/bin/buf"

RUN npm install && npm run build

FROM node:18-slim

# Install latest chrome dev package and fonts to support major charsets (Chinese, Japanese, Arabic, Hebrew, Thai and a few others)
# Note: this installs the necessary libs to make the bundled version of Chromium that Puppeteer
# installs, work.
RUN apt-get update \
    && apt-get install -y wget gnupg \
    && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
    && apt-get update \
    && apt-get install -y google-chrome-stable fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg fonts-kacst fonts-freefont-ttf libxss1 \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

RUN GRPC_HEALTH_PROBE_VERSION=v0.4.11 && \
    wget -qO/bin/grpc_health_probe https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/grpc_health_probe-linux-amd64 && \
    chmod +x /bin/grpc_health_probe

WORKDIR /app

COPY --from=builder /usr/src/rendertron/package.json .
COPY --from=builder /usr/src/rendertron/node_modules node_modules
COPY --from=builder /usr/src/rendertron/build build
COPY --from=builder /usr/src/rendertron/generated generated
COPY .puppeteerrc.cjs .

# Install puppeteer so it's available in the container.
RUN groupadd -r pptruser && useradd -r -g pptruser -G audio,video pptruser \
    && mkdir -p /home/pptruser/Downloads \
    && chown -R pptruser:pptruser -R  /home/pptruser \
    && chown -R pptruser:pptruser -R /app

# Run everything after as non-privileged user.
USER pptruser

ENTRYPOINT ["node", "build/src/index.js"]
