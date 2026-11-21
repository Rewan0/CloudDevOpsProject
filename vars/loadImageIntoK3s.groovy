// Floci/k3s only: imports the image into the node so pods can start without
// pulling it. On AWS the push to ECR is enough and this step is skipped.
// cfg: image, container (optional)
def call(Map cfg) {
    def container = cfg.container ?: 'floci-eks-ivolve-eks'
    sh """
        docker save --platform linux/amd64 ${cfg.image} | \
        docker exec -i ${container} ctr --address /run/k3s/containerd/containerd.sock -n k8s.io images import -
    """
}
