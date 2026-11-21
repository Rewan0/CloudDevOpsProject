// Builds a Docker image from a build context.
// cfg: image (full tag), context (directory with the Dockerfile)
def call(Map cfg) {
    sh "docker build -t ${cfg.image} ${cfg.context}"
}
