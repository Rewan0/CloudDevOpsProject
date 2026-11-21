// Tags the image for the push registry and pushes it.
// cfg: image, pushRegistry, repo, tag
def call(Map cfg) {
    def target = "${cfg.pushRegistry}/${cfg.repo}:${cfg.tag}"
    sh """
        docker tag ${cfg.image} ${target}
        docker push ${target}
    """
    return target
}
