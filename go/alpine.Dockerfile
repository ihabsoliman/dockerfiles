ARG ALPINE_VERSION=3.18

ARG DOCKER_VERSION=v24.0.5
ARG COMPOSE_VERSION=v2.20.3
ARG BUILDX_VERSION=v0.11.2
ARG LOGOLS_VERSION=v1.3.7
ARG BIT_VERSION=v1.1.2
ARG GH_VERSION=v2.32.1

ARG GO_VERSION=1.21
ARG GOMODIFYTAGS_VERSION=v1.16.0
ARG GOPLAY_VERSION=v1.0.0
ARG GOTESTS_VERSION=v1.6.0
ARG DLV_VERSION=v1.21.0
ARG MOCKERY_VERSION=v2.32.4
ARG GOMOCK_VERSION=v1.6.0
ARG GOPLS_VERSION=v0.13.2
ARG GOLANGCILINT_VERSION=v1.54.1
ARG IMPL_VERSION=v1.2.0
ARG GOPKGS_VERSION=v2.1.2

# https://github.com/qdm12/binpot
FROM qmcgaw/binpot:docker-${DOCKER_VERSION} AS docker
FROM qmcgaw/binpot:compose-${COMPOSE_VERSION} AS compose
FROM qmcgaw/binpot:buildx-${BUILDX_VERSION} AS buildx
FROM qmcgaw/binpot:logo-ls-${LOGOLS_VERSION} AS logo-ls
FROM qmcgaw/binpot:bit-${BIT_VERSION} AS bit
FROM qmcgaw/binpot:gh-${GH_VERSION} AS gh
FROM golang:${GO_VERSION}-${DEBIAN_VERSION} AS go

FROM qmcgaw/binpot:gomodifytags-${GOMODIFYTAGS_VERSION} AS gomodifytags
FROM qmcgaw/binpot:goplay-${GOPLAY_VERSION} AS goplay
FROM qmcgaw/binpot:gotests-${GOTESTS_VERSION} AS gotests
FROM qmcgaw/binpot:dlv-${DLV_VERSION} AS dlv
FROM qmcgaw/binpot:mockery-${MOCKERY_VERSION} AS mockery
FROM qmcgaw/binpot:gomock-${GOMOCK_VERSION} AS gomock
FROM qmcgaw/binpot:gopls-${GOPLS_VERSION} AS gopls
FROM qmcgaw/binpot:golangci-lint-${GOLANGCILINT_VERSION} AS golangci-lint
FROM qmcgaw/binpot:impl-${IMPL_VERSION} AS impl
FROM qmcgaw/binpot:gopkgs-${GOPKGS_VERSION} AS gopkgs

FROM alpine:${ALPINE_VERSION}
ARG CREATED
ARG COMMIT
ARG VERSION=local
ENV BASE_VERSION="${VERSION}-${CREATED}-${COMMIT}"

COPY --from=go /usr/local/go /usr/local/go
ENV GOPATH=/go
ENV PATH=$GOPATH/bin:/usr/local/go/bin:$PATH \
    CGO_ENABLED=0 \
    GO111MODULE=on
WORKDIR $GOPATH

# CA certificates
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -r /var/cache/* /var/lib/apt/lists/*

# Timezone
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends tzdata && \
    rm -r /var/cache/* /var/lib/apt/lists/*
ENV TZ=

# Setup Git and SSH
# Workaround for older Debian in order to be able to sign commits
RUN echo "deb https://deb.debian.org/debian bookworm main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends -t bookworm git git-man && \
    rm -r /var/cache/* /var/lib/apt/lists/*
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends man openssh-client less && \
    rm -r /var/cache/* /var/lib/apt/lists/*
COPY shell/.ssh.sh /root/
RUN chmod +x /root/.ssh.sh
# Retro-compatibility symlink
RUN  ln -s /root/.ssh.sh /root/.windows.sh

# Setup shell
ENTRYPOINT [ "/bin/zsh" ]
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends zsh nano locales wget && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -r /var/cache/* /var/lib/apt/lists/*
ENV EDITOR=nano \
    LANG=en_US.UTF-8 \
    # MacOS compatibility
    TERM=xterm
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8
RUN usermod --shell /bin/zsh root

ADD https://raw.githubusercontent.com/qdm12/basedevcontainer/8cdffe886e48f4ade080e40e1fc6d433aae0eccb/shell/.zshrc /root/
RUN git clone --single-branch --depth 1 https://github.com/robbyrussell/oh-my-zsh.git ~/.oh-my-zsh

# Shell setup
COPY shell/.zshrc-specific shell/.welcome.sh /root/

ARG POWERLEVEL10K_VERSION=v1.16.1
ADD https://raw.githubusercontent.com/qdm12/basedevcontainer/8cdffe886e48f4ade080e40e1fc6d433aae0eccb/shell/.p10k.zsh /root
RUN git clone --branch ${POWERLEVEL10K_VERSION} --single-branch --depth 1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k && \
    rm -rf ~/.oh-my-zsh/custom/themes/powerlevel10k/.git

# Docker CLI
COPY --from=docker /bin /usr/local/bin/docker
ENV DOCKER_BUILDKIT=1

# Docker compose
COPY --from=compose /bin /usr/libexec/docker/cli-plugins/docker-compose
ENV COMPOSE_DOCKER_CLI_BUILD=1
RUN echo "alias docker-compose='docker compose'" >> /root/.zshrc

# Buildx plugin
COPY --from=buildx /bin /usr/libexec/docker/cli-plugins/docker-buildx

# Logo ls
COPY --from=logo-ls /bin /usr/local/bin/logo-ls
RUN echo "alias ls='logo-ls'" >> /root/.zshrc

# Bit
COPY --from=bit /bin /usr/local/bin/bit
ARG TARGETPLATFORM
RUN if [ "${TARGETPLATFORM}" != "linux/s390x" ]; then echo "y" | bit complete; fi

COPY --from=gh /bin /usr/local/bin/gh

# Go stuff
COPY --from=gomodifytags /bin /go/bin/gomodifytags
COPY --from=goplay  /bin /go/bin/goplay
COPY --from=gotests /bin /go/bin/gotests
COPY --from=dlv /bin /go/bin/dlv
COPY --from=mockery /bin /go/bin/mockery
COPY --from=gomock /bin /go/bin/gomock
COPY --from=gopls /bin /go/bin/gopls
COPY --from=golangci-lint /bin /go/bin/golangci-lint
COPY --from=impl /bin /go/bin/impl
COPY --from=gopkgs /bin /go/bin/gopkgs