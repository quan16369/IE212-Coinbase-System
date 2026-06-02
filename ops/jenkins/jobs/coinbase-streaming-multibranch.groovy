def repoUrl = System.getenv('JENKINS_GITHUB_REPOSITORY_URL') ?: 'https://github.com/quan16369/Coinbase_Streaming.git'
def credentialId = System.getenv('JENKINS_GITHUB_CREDENTIALS_ID') ?: ''

multibranchPipelineJob('coinbase-streaming') {
  displayName('Coinbase Streaming')
  description('Production-style multibranch pipeline for Coinbase Streaming.')

  branchSources {
    git {
      id('coinbase-streaming-git')
      remote(repoUrl)
      if (credentialId) {
        credentialsId(credentialId)
      }
    }
  }

  factory {
    workflowBranchProjectFactory {
      scriptPath('Jenkinsfile')
    }
  }

  orphanedItemStrategy {
    discardOldItems {
      numToKeep(10)
    }
  }

  triggers {
    periodicFolderTrigger {
      interval('1d')
    }
  }
}
