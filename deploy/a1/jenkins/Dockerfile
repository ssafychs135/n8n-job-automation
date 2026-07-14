FROM jenkins/jenkins:lts-jdk17
USER root
# CI 도구(Debian 패키지, GPG 서명): jq, shellcheck, python3
RUN apt-get update && apt-get install -y --no-install-recommends \
      jq shellcheck python3 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# docker CLI (정적 바이너리, arm64, sha256 검증 — 데몬은 host docker.sock 사용, CLI만 필요)
RUN curl -fsSL https://download.docker.com/linux/static/stable/aarch64/docker-27.3.1.tgz -o /tmp/d.tgz \
    && echo "4da6a6c7502b7ab561675a5ff5ac192d9b49d76d0b8847cf17ade246122279f4  /tmp/d.tgz" | sha256sum -c - \
    && tar xzf /tmp/d.tgz -C /tmp && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/d.tgz /tmp/docker
# docker compose v2 플러그인 (arm64, sha256 검증)
RUN curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-aarch64 -o /tmp/dc \
    && echo "6e9fbd5daa20dca5d7d89145081ae8155d68ef2928b497d9f85b54fe0f9dbb2c  /tmp/dc" | sha256sum -c - \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && mv /tmp/dc /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
# gitleaks (arm64, sha256 검증)
RUN curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_arm64.tar.gz -o /tmp/gl.tgz \
    && echo "bf5f7f466ebfade1296c8bd32cf7d3f592c2aa78836aa9980ffbe2cadca7a861  /tmp/gl.tgz" | sha256sum -c - \
    && tar xzf /tmp/gl.tgz -C /usr/local/bin gitleaks && rm /tmp/gl.tgz
# caddy (arm64 릴리스 버전 고정 + sha512 검증 — 동적 다운로드 URL 제거)
RUN curl -fsSL https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_linux_arm64.tar.gz -o /tmp/caddy.tgz \
    && echo "5466234be3e988071cef937aedbdd94c15b6f75cf7307397e67c2641219ac9bfe2c2bb3b31fc05bc68d3b6398bbe50abfa16ccf3b127318ccac31115ad26507c  /tmp/caddy.tgz" | sha512sum -c - \
    && tar xzf /tmp/caddy.tgz -C /usr/local/bin caddy && rm /tmp/caddy.tgz
# 플러그인 설치
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
USER jenkins
