#!/usr/bin/env groovy
pipeline {
    agent { label 'pod-default' }
    stages {
        stage('Check Environment') {
            steps {
                sh 'java -version'
                container('maven') {
                    sh '''
                        java -version
                        mvn -version
                        pwd
                    '''
                }
            }
        }
    }
}
