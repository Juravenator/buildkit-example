
pipeline {
    agent any

    environment {
        IMAGE_REGISTRY = 'artifactory.myorg.com:9002'
        IMAGE_NAME     = 'myteam/myapp'
        IMAGE_TAG      = '0.0.1'
    }

    options {
        ansiColor('xterm')
        disableConcurrentBuilds()
    }

    stages {

        stage('Test') {
            steps {
                sh """
                docker version
                make test
                """
            }
        }

        stage('Build') {
            steps {
                sh """
                docker version
                make build.container
                """
            }
        }

        stage('Publish') {
            steps {
                sh """
                    docker push https://${env.IMAGE_REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}
                """
            }
        }
    }
}