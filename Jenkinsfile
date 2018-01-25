#!/usr/bin/env groovy
VERSION = ''
props = {}

def defaults = [
  threadfix_key_cred: 'threadfix-sonar-key',
  threadfix_url: '',
  threadfix_id: '7',
  oauth_client_cred: 'sonar-oauth-client',
  exec_label: 'Linux&&!gpu&&!restricted-master',
  aws_ca: '',
  dep_check: 'yes'
]

try {
  node(defaults.exec_label) {
    stage('Fetch code') {
      checkout scm
      sh 'git clean -ffdx'
      VERSION = getVersion()
      stash name: 'code', useDefaultExcludes: false

      if( env.JENKINS_URL =~ 'ic.gov' ) {
        echo 'Reading TC properties file'
        props = readProperties defaults: defaults, file: 'tc.properties'
      } else if ( env.JENKINS_URL =~ 'gs.mil' ){
        echo 'Reading UC properties file'
        props = readProperties defaults: defaults, file: 'uc.properties'
      } else {
        echo 'Reading default properties file'
        props = readProperties defaults: defaults, file: 'io.properties'
      }
    }


    stage('Download Pinry') {
      def file = sh(script: "basename ${props.source_url}", returnStdout: true).trim()
      withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: props.s3_read_credentials, secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
        sh """
          docker pull solidyn/cli
          docker run --rm -v /tmp:${props.containerPath}:Z -w ${props.containerPath} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} solidyn/cli aws s3 cp ${props.source_url} .
        """
        sh "mv /tmp/${file} . || true"
      }
      unzip zipFile: file


      // withEnv(["HOME=${pwd()}"]) {
      //   sh "wget ${props.source_url}"
      //   def file = 'pinry.zip'
      //   unzip zipFile: file
      // }
    }

    stage('Download ion-connect') {
      sh """
      wget --quiet https://s3.amazonaws.com/public.ionchannel.io/files/ionize/linux/bin/ionize
      chmod +x ionize
      """
    }

    stage('Download Ionize') {
      sh """
      wget https://s3.amazonaws.com/public.ionchannel.io/files/ion-connect/linux/bin/ion-connect
      chmod +x ion-connect
      """
    }

    stage('Build Pinry') {
      dir('pinry') {
        if (fileExists('requirements.txt')) {
          sh """
          virtualenv .pinry
          . .pinry/bin/activate
          pip install -r requirements.txt > report.txt
          cat report.txt
          """
        }
      }
    }

    stage('Unit Test Pinry') {
      dir('pinry') {
        sh """
        . .pinry/bin/activate
        echo Would run python manage.py test
        """
      }
    }

    stage('Ionize') {
      withCredentials([string(credentialsId: props.ionchannel_secret_key, variable: 'IONIZE_TOKEN')]) {
        sh """
        export IONCHANNEL_SECRET_KEY=${IONIZE_TOKEN}
        ./ionize analyze
        """
      }
    }

    stage('Artifact S3 Clean') {
      // deleteDir()
      sh 'ls -lart'
      echo "Show .ionize-artifact.yaml"
      sh 'cat .ionize-artifact.yaml'

      echo "Show .ionize.yaml"
      sh 'cat .ionize.yaml'
      withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: props.s3_read_credentials, secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
        sh """
          docker pull solidyn/cli
          docker run --rm -v /tmp:${props.containerPath}:Z -w ${props.containerPath} -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} solidyn/cli aws s3 cp pinry.zip ${props.dest_url}
        """
        echo "Notify SNS"
        sh """
        aws configure set region us-east-1
        aws sns publish --topic-arn arn:aws:sns:us-east-1:846311194563:Ion-Channel-Mock --message file://.ionize.yaml
        """
      }

      // dir('build') {
      //   unstash 'code'
      //   unstash 'build'
      // }
      // zip dir: 'build', glob: '', zipFile: "sonar-${VERSION}-${env.BUILD_NUMBER}.zip"
      // sh "cp pinry.zip pinry-${VERSION}-${env.BUILD_NUMBER}.zip"
      // // publishZip("sonar-${VERSION}-${env.BUILD_NUMBER}.zip", 'test', "${VERSION}-${env.BUILD_NUMBER}")
      // publishZip("pinry-${VERSION}-${env.BUILD_NUMBER}.zip", 'stage', "${VERSION}-${env.BUILD_NUMBER}")
      // currentBuild.setDescription("Pinry Unit Test")
    }
  }
} catch(e) {
  // node() {
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
  // }
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
      sh "mvn -U --batch-mode deploy:deploy-file -DgroupId=sonar -DartifactId=${artifactId} -Dversion=${fVer} -Dpackaging=zip -Dfile=${file} -DrepositoryId=nexus -Durl=${props.deploy_repo}"
    }
  }
}

def uploadToThreadfix(file) {
  fileExists file
  if( props.threadfix_url == '' ) {
    return true
  }
  if(props.threadfix_id == null) {
    throw new Exception("threadfix_id not set. Cannot upload ${file} to threadfix server")
  }
  withCredentials([string(credentialsId: props.threadfix_key_cred, variable: 'THREADFIX_KEY')]) {
    sh "/bin/curl -v --insecure -H 'Accept: application/json' -X POST --form file=@${file} ${props.threadfix_url}/rest/applications/${props.threadfix_id}/upload?apiKey=${THREADFIX_KEY}"
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
