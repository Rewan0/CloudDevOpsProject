// Scans a local image with Trivy (run as a container).
// cfg: image, failOnCritical (boolean), trivyImage (optional)
def call(Map cfg) {
    def trivy = "docker run --rm " +
        "-v /var/run/docker.sock:/var/run/docker.sock " +
        "-v trivy-cache:/root/.cache/ " +
        "${cfg.trivyImage ?: 'aquasec/trivy:0.71.2'}"

    // Full report for the build log
    sh "${trivy} image --no-progress --severity HIGH,CRITICAL --ignore-unfixed ${cfg.image}"

    // Quality gate: fail on fixable CRITICAL vulnerabilities
    if (cfg.failOnCritical) {
        sh "${trivy} image --no-progress --severity CRITICAL --ignore-unfixed --exit-code 1 ${cfg.image}"
    }
}
