FROM node:20-bookworm AS build

SHELL ["/bin/bash", "-c"]

RUN apt-get update && \
    apt-get install -y make gcc pkg-config libx11-dev libxkbfile-dev libsecret-1-dev python3 curl

# On part directement du package.json officiel des examples Theia
RUN mkdir /home/theia && \
    curl https://raw.githubusercontent.com/eclipse-theia/theia/refs/tags/v1.61.0/examples/browser/package.json \
      | egrep -v '"@theia/(api-|test)' > /home/theia/package.json

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1 \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    NODE_OPTIONS="--max-old-space-size=8192" \
    DISABLE_V8_COMPILE_CACHE=1

WORKDIR /home/theia

# Ajout des plugins Kubernetes par-dessus le package.json officiel
RUN node -e "const p=require('./package.json'); \
    p.theiaPluginsDir='plugins'; \
    p.dependencies = Object.assign({}, p.dependencies, { 'lodash': '^4.17.21' }); \
    p.theiaPlugins={ \
      'vscode-builtin-extensions-pack':'https://open-vsx.org/api/eclipse-theia/builtin-extension-pack/1.95.3/file/eclipse-theia.builtin-extension-pack-1.95.3.vsix', \
      'vscode.kubernetes-tools':'https://open-vsx.org/api/ms-kubernetes-tools/vscode-kubernetes-tools/1.3.18/file/ms-kubernetes-tools.vscode-kubernetes-tools-1.3.18.vsix', \
      'redhat.vscode-yaml':'https://open-vsx.org/api/redhat/vscode-yaml/1.15.0/file/redhat.vscode-yaml-1.15.0.vsix' \
    }; \
    require('fs').writeFileSync('./package.json', JSON.stringify(p,null,2));"

COPY patch-ripgrep.js /tmp/patch-ripgrep.js

RUN npm install && \
    ln -sf ../ripgrep-linux-x64/bin node_modules/@vscode/ripgrep/bin && \
    ls -la node_modules/@vscode/ripgrep/bin/rg && \
    echo "module.exports = { install: function() {} };" > node_modules/v8-compile-cache/v8-compile-cache.js && \
    node /tmp/patch-ripgrep.js

RUN npm run bundle
RUN npx theia download:plugins

# Stage 2 : image finale
FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y \
    libsecret-1-0 \
    curl \
    git \
    openssh-client \
    bash \
    ca-certificates \
    apt-transport-https \
    gnupg \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list \
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
COPY --from=build --chown=theia:theia /home/theia /home/theia

EXPOSE 3000
USER theia
WORKDIR /home/project

ENTRYPOINT ["node", "/home/theia/lib/backend/main.js", "/home/project", "--hostname=0.0.0.0"]