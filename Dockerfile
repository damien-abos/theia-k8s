FROM node:24-trixie AS build

SHELL ["/bin/bash", "-c"]

# TARGETARCH est fourni automatiquement par buildx (amd64, arm64, ...)
ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y make gcc pkg-config libx11-dev libxkbfile-dev libsecret-1-dev python3 curl

# On part directement du package.json officiel des examples Theia
#RUN mkdir /home/theia && \
#    curl https://raw.githubusercontent.com/eclipse-theia/theia/refs/tags/v1.61.0/examples/browser/package.json \
#      | egrep -v '"@theia/(api-|test)' > /home/theia/package.json

COPY package.json /home/theia/package.json

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1 \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    NODE_OPTIONS="--max-old-space-size=8192" \
    DISABLE_V8_COMPILE_CACHE=1

WORKDIR /home/theia

COPY patch-ripgrep.js /tmp/patch-ripgrep.js

# Mapping arch Docker -> arch ripgrep
# - amd64 -> linux-x64
# - arm64 -> linux-arm64
RUN case "${TARGETARCH}" in \
      amd64) RG_ARCH="linux-x64" ;; \
      arm64) RG_ARCH="linux-arm64" ;; \
      *) echo "Architecture ${TARGETARCH} non supportée" && exit 1 ;; \
    esac && \
    echo "Building for ${TARGETARCH} (ripgrep: ${RG_ARCH})" && \
    npm install && \
    ln -sf ../ripgrep-${RG_ARCH}/bin node_modules/@vscode/ripgrep/bin && \
    ls -la node_modules/@vscode/ripgrep/bin/rg && \
    echo "module.exports = { install: function() {} };" > node_modules/v8-compile-cache/v8-compile-cache.js && \
    node /tmp/patch-ripgrep.js

# On bundle Theia, les dépendances de production sont installées et les plugins sont téléchargés. Les node_modules de développement sont ensuite supprimés pour réduire la taille de l'image finale.
RUN npm run bundle:production && \
    npx theia download:plugins && \
    rm -rf node_modules && \
    npm install --omit=dev --ignore-scripts && \
    ln -sf ../ripgrep-linux-x64/bin node_modules/@vscode/ripgrep/bin

# Stage 2 : image finale
FROM node:24-trixie-slim

RUN apt-get update && apt-get install -y \
    libsecret-1-0 \
    curl \
    git \
    openssh-client \
    bash \
    ca-certificates \
    apt-transport-https \
    gnupg \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update && apt-get install -y kubectl \
    && curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor -o /etc/apt/keyrings/helm.gpg > /dev/null \
    && echo "deb [signed-by=/etc/apt/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" > /etc/apt/sources.list.d/helm-stable-debian.list \
    && apt-get update && apt-get install -y helm \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --system --group --uid 1001 --home /home/theia theia && \
    mkdir -p /home/project && \
    chown -R theia:theia /home/project

ENV HOME=/home/theia \
    SHELL=/bin/bash \
    THEIA_DEFAULT_PLUGINS=local-dir:/home/theia/plugins \
    USE_LOCAL_GIT=true

WORKDIR /home/theia
COPY --from=build --chown=theia:theia /home/theia/lib /home/theia/lib
COPY --from=build --chown=theia:theia /home/theia/src-gen /home/theia/src-gen
COPY --from=build --chown=theia:theia /home/theia/plugins /home/theia/plugins
COPY --from=build --chown=theia:theia /home/theia/node_modules /home/theia/node_modules
COPY --from=build --chown=theia:theia /home/theia/package.json /home/theia/package.json
COPY product.json /home/theia/product.json

EXPOSE 3000
USER theia

RUN ( \
        set -x; cd "$(mktemp -d)" && \
        OS="$(uname | tr '[:upper:]' '[:lower:]')" && \
        ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" && \
        KREW="krew-${OS}_${ARCH}" && \
        curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" && \
        tar zxvf "${KREW}.tar.gz" && \
        ./"${KREW}" install krew \
    ) && \
    echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> /home/theia/.bashrc && \
    kubectl krew install oidc-login

WORKDIR /home/project

ENTRYPOINT ["node", "/home/theia/lib/backend/main.js", "/home/project", "--hostname=0.0.0.0"]