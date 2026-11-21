// Replaces the image reference of one service in its manifest.
// cfg: manifest, repo, image
def call(Map cfg) {
    sh """
        sed -i 's#image: .*${cfg.repo}:.*#image: ${cfg.image}#' ${cfg.manifest}
        echo 'Updated image reference:'
        grep -n 'image:' ${cfg.manifest}
    """
}
