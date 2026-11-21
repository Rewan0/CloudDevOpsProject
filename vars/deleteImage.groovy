// Removes the local images so the agent does not fill up.
// cfg: image, pushRegistry, repo, tag
def call(Map cfg) {
    def target = "${cfg.pushRegistry}/${cfg.repo}:${cfg.tag}"
    sh "docker rmi -f ${cfg.image} ${target} || true"
}
