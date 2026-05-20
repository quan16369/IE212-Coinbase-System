pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    COMPOSE_PROJECT_NAME = 'coinbase_streaming'
    COMPOSE_PROFILES = 'ops'
    ENV_FILE = '.env'
  }

  stages {
    stage('Prepare') {
      steps {
        sh '''
          if [ ! -f "$ENV_FILE" ]; then
            cp .env.example "$ENV_FILE"
          fi
        '''
      }
    }

    stage('CI Checks') {
      steps {
        sh 'bash scripts/ci_check.sh'
      }
    }

    stage('Build Images') {
      steps {
        sh 'docker compose --env-file "$ENV_FILE" build'
      }
    }

    stage('Deploy') {
      when {
        anyOf {
          branch 'main'
          branch 'master'
        }
      }
      steps {
        sh 'bash scripts/deploy_compose.sh'
      }
    }
  }

  post {
    always {
      sh 'docker compose --env-file "$ENV_FILE" ps || true'
    }
  }
}
