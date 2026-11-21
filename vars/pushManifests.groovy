// Commits the manifest change and pushes it so ArgoCD can sync it.
// cfg: manifest, service, tag, repoUrl, branch, credentialsId
def call(Map cfg) {
    def host = cfg.repoUrl.replaceFirst('^https://', '')
    withCredentials([usernamePassword(credentialsId: cfg.credentialsId,
                                      usernameVariable: 'GIT_USER',
                                      passwordVariable: 'GIT_TOKEN')]) {
        sh """
            git config user.name 'jenkins-ci'
            git config user.email 'jenkins-ci@ivolve.local'
            git add ${cfg.manifest}
            if git diff --cached --quiet; then
                echo 'No manifest change to push'
            else
                git commit -m 'ci(${cfg.service}): deploy image ${cfg.tag}'
                git fetch https://\$GIT_USER:\$GIT_TOKEN@${host} ${cfg.branch}
                git rebase FETCH_HEAD
                git push https://\$GIT_USER:\$GIT_TOKEN@${host} HEAD:${cfg.branch}
            fi
        """
    }
}
