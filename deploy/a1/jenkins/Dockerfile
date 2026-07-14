FROM jenkins/jenkins:lts-jdk17
USER root
# CD/CI 도구: docker CLI+compose, jq, shellcheck, curl
RUN apt-get update && apt-get install -y --no-install-recommends \
      docker.io docker-compose-v2 jq shellcheck curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
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
