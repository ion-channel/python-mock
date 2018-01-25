#!/usr/bin/env groovy
VERSION = ''
props = {}

def defaults = [
  threadfix_key_cred: 'threadfix-sonar-key',
  threadfix_url: '',
  threadfix_id: '7',
  nexus_cred: 'nexus-user-pass',
  oauth_client_cred: 'sonar-oauth-client',
  pcf_service_owner: 'devops@nga',
  syslog_drain: 'gs_syslog',
  exec_label: 'Linux&&!gpu&&!restricted-master',
  aws_ca: '',
  aws_region: 'us-east-1',
  s3_read_credentials: 'ion_s3_poc_bucket',
  containerPath: '/app',
  dep_check: 'yes',
  aws_region: 'us-east-1',
  deploy_repo: 'https://nexus.gs.mil/content/repositories/fade_devops-release',
  source_url_orig: 'https://s3.amazonaws.com/repo.geointservices.io/artifacts/stage/misc/pinry.zip',
  source_url: 's3://ion-dirty.geointservices.io/pinry.zip',
  dest_url: 's3://ion-clean.geointservices.io/',
  pypi_url: ''
]

try {
  node(defaults.exec_label) {
    stage('Download Pinry') {
      def file = sh(script: "basename ${props.source_url}", returnStdout: true).trim()
      withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: defaults.s3_read_credentials, secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
        sh """
          docker pull solidyn/cli
          docker run --rm -v /tmp:${props.containerPath}:Z -w ${props.containerPath} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} solidyn/cli aws s3 cp ${defaults.source_url} .
        """
        sh "mv /tmp/${file} . || true"
      }
      unzip zipFile: file


      // withEnv(["HOME=${pwd()}"]) {
      //   sh "wget ${defaults.source_url}"
      //   def file = 'pinry.zip'
      //   unzip zipFile: file
      // }
    }

    stage('Build Pinry') {
      dir('pinry') {
        sh 'virtualenv .pinry'
        sh '. .pinry/bin/activate'
        // stash includes: 'sonarqube/', name: 'build'
        sh 'pip install -r requirements.txt'
      }
    }

    stage('Unit Test Pinry') {
      dir('pinry') {
        sh 'python manage.py test > ./report.log'
      }
    }

    stage('Artifact Push to Nexus') {
      node(defaults.exec_label) {
        deleteDir()
        dir('build') {
          unstash 'code'
          unstash 'build'
        }
        zip dir: 'build', glob: '', zipFile: "sonar-${VERSION}-${env.BUILD_NUMBER}.zip"
        sh "cp pinry.zip pinry-${VERSION}-${env.BUILD_NUMBER}.zip"
        // publishZip("sonar-${VERSION}-${env.BUILD_NUMBER}.zip", 'test', "${VERSION}-${env.BUILD_NUMBER}")
        publishZip("pinry-${VERSION}-${env.BUILD_NUMBER}.zip", 'stage', "${VERSION}-${env.BUILD_NUMBER}")
        currentBuild.setDescription("Pinry Unit Test")
      }
    }
  }
} catch(e) {
  node() {
    echo "${e}"
    if(currentBuild.result || currentBuild.result != 'FAILURE') {
      currentBuild.result = 'FAILURE'
    }
    def body = """
      The build for ${env.JOB_NAME} is in status ${currentBuild.result}.
      See ${env.BUILD_URL}

      Error: ${e.message}
    """
    emailext body: body, recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'RequesterRecipientProvider']], subject: "[PCF SonarQube] build ${env.BUILD_NUMBER} - ${currentBuild.result}"
  }
}

def getVersion() {
  return sh(script: 'make version', returnStdout: true).trim()
}

def setManifestParams(manifest, paramMap) {
  fileExists manifest
  for( p in mapToList(paramMap) ) {
    def key = p[0]
    def value = p[1]
    echo "replacing ${key} with ${value}"
    sh "sed -i ${manifest} -e '/${key}/ s/:.*\$/: ${value}/'"
  }
}

@NonCPS
def mapToList(depmap) {
    def dlist = []
    for (entry in depmap) {
        dlist.add([entry.key, entry.value])
    }
    dlist
}

def publishZip(file, artifactId, fVer) {
  def mvn = tool 'M3'
  wrap([$class: 'AnsiColorBuildWrapper', 'colorMapName': 'XTerm']) {
    dir('.m2') {
      sh '[[ -f ~/.m2/settings.xml ]] && cp ~/.m2/settings.xml .'
    }
    withEnv(["PATH+MVN=${mvn}/bin", "HOME=${pwd()}", "_JAVA_OPTIONS=-Duser.home=${pwd()}"]) {
      sh "mvn -U --batch-mode deploy:deploy-file -DgroupId=sonar -DartifactId=${artifactId} -Dversion=${fVer} -Dpackaging=zip -Dfile=${file} -DrepositoryId=nexus -Durl=${defaults.deploy_repo}"
    }
  }
}

def uploadToThreadfix(file) {
  fileExists file
  if( defaults.threadfix_url == '' ) {
    return true
  }
  if(defaults.threadfix_id == null) {
    throw new Exception("threadfix_id not set. Cannot upload ${file} to threadfix server")
  }
  withCredentials([string(credentialsId: defaults.threadfix_key_cred, variable: 'THREADFIX_KEY')]) {
    sh "/bin/curl -v --insecure -H 'Accept: application/json' -X POST --form file=@${file} ${defaults.threadfix_url}/rest/applications/${defaults.threadfix_id}/upload?apiKey=${THREADFIX_KEY}"
  }
}

def createPipConf(url) {
  def host = url.split('/')[2]
  if( host == null || host == '' ) {
    return ''
  }

  dir('.pip') {
    witeFile file: 'pip.conf', text:"""[global]
index-url = ${url}
trusted-host = ${host}
    """
  }
}
