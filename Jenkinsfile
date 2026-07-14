// n8n 취업 자동화 스택 CI/CD (A1 자체호스팅 Jenkins, GitOps)
// CI: 6검사 병렬 게이트 → CD(main): 배포·워크플로우 import·restart·스모크 → Discord 알림
pipeline {
  agent any
  options { disableConcurrentBuilds() }
  triggers { pollSCM('H/3 * * * *') }
  environment { DEPLOY_DIR = '/home/ubuntu/n8n-pjt' }

  stages {
    stage('CI') {
      parallel {
        stage('workflow-json') {
          steps { sh 'bash ci/validate-workflows.sh workflows' }
        }
        stage('shellcheck') {
          steps { sh 'shellcheck scripts/*.sh ci/*.sh' }
        }
        stage('python') {
          steps { sh 'for f in scripts/*.py; do python3 -m py_compile "$f"; done' }
        }
        stage('compose-config') {
          steps { sh 'docker compose -f docker-compose.yml -f deploy/a1/docker-compose.override.yml --env-file ${DEPLOY_DIR}/.env config -q' }
        }
        stage('caddy-validate') {
          steps { sh 'caddy validate --adapter caddyfile --config deploy/a1/Caddyfile' }
        }
        stage('secret-scan') {
          steps { sh 'gitleaks detect --no-banner --redact -v || (echo "secret 탐지!"; exit 1)' }
        }
      }
    }

    stage('CD: deploy infra') {
      steps {
        sh '''
          cd ${DEPLOY_DIR}
          git fetch -q origin main && git reset --hard origin/main
          cp deploy/a1/docker-compose.override.yml docker-compose.override.yml
          cp deploy/a1/Caddyfile caddy/Caddyfile
          docker compose up -d
        '''
      }
    }

    stage('CD: import workflows') {
      steps {
        // import는 활성 워크플로우를 비활성화함 → JSON의 active 값 기준으로 재설정 후 restart 1회.
        sh '''
          cd ${DEPLOY_DIR}
          docker compose exec -T n8n n8n import:workflow --separate --input=/workflows
          for f in workflows/*.json; do
            id=$(jq -r .id "$f"); act=$(jq -r .active "$f")
            docker compose exec -T n8n n8n update:workflow --id="$id" --active="$act"
          done
          docker compose restart n8n
        '''
      }
    }

    stage('smoke test') {
      steps {
        // ★ localhost는 n8n '컨테이너 안'에서 검사(Jenkins 컨테이너 localhost 아님)
        sh '''
          cd ${DEPLOY_DIR}
          sleep 15
          docker compose exec -T n8n node -e 'fetch("http://localhost:5678/healthz").then(r=>{if(!r.ok)process.exit(1);console.log("n8n ok")}).catch(()=>process.exit(1))'
          docker compose exec -T n8n node -e 'fetch("http://host.docker.internal:1234/v1/models").then(r=>{if(!r.ok)process.exit(1);return r.json()}).then(d=>console.log("llm ok",d.data.length)).catch(()=>process.exit(1))'
          docker compose exec -T postgres psql -U n8n -d jobs -tAc "select 'jobs='||count(*) from jobs" | grep -qE 'jobs=[1-9]'
        '''
      }
    }
  }

  post {
    always {
      script {
        def result = currentBuild.currentResult
        withEnv(["BUILD_RESULT=${result}"]) {
          sh '''
            cd ${DEPLOY_DIR}
            WEBHOOK=$(grep -E "^DISCORD_WEBHOOK_URL=" .env | cut -d= -f2-)
            [ -z "$WEBHOOK" ] && exit 0
            if [ "$BUILD_RESULT" = "SUCCESS" ]; then MSG="✅ 배포 성공 #${BUILD_NUMBER}"; else MSG="❌ 배포 실패 #${BUILD_NUMBER}"; fi
            curl -s -m 15 -H "Content-Type: application/json" -H "User-Agent: Mozilla/5.0" \
              -d "{\\"content\\":\\"$MSG (${JOB_NAME})\\"}" "$WEBHOOK" >/dev/null
          '''
        }
      }
    }
  }
}
