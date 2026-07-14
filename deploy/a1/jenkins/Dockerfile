FROM jenkins/jenkins:lts-jdk17
USER root
# CI 도구(Debian 패키지): jq, shellcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
      jq shellcheck curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# docker CLI (정적 바이너리, arm64 — 데몬은 host docker.sock 사용하므로 CLI만 필요)
RUN curl -fsSL https://download.docker.com/linux/static/stable/aarch64/docker-27.3.1.tgz | tar xz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker && rm -rf /tmp/docker
# docker compose v2 플러그인 (arm64)
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-aarch64 \
       -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
# gitleaks (arm64)
RUN curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_arm64.tar.gz \
      | tar xz -C /usr/local/bin gitleaks
# caddy (validate용, arm64 정적 바이너리)
RUN curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=arm64" -o /usr/local/bin/caddy \
    && chmod +x /usr/local/bin/caddy
# 플러그인 설치
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
USER jenkins
