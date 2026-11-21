# Step 5: Container Orchestration with Kubernetes

## Overview

This step describes how the application runs on Kubernetes. Each Docker Compose service from Step 2 is translated into the matching Kubernetes object: Deployments and Services for the stateless microservices, a StatefulSet with a headless Service and a StorageClass for the database, a ConfigMap and a Secret for configuration, and an Ingress for external access to the frontend.

The manifests were applied to the EKS cluster provisioned in Step 3. On the Floci emulator, that cluster runs as a single k3s node, so every pod is scheduled on that node.

### Objectives

- Isolate the application in its own namespace.
- Run each microservice as a Deployment exposed through a Service.
- Run MySQL as a StatefulSet with stable identity and persistent storage.
- Keep configuration out of the images with a ConfigMap and a Secret.
- Expose the frontend through an Ingress.

### Requirement Mapping

| Requirement | Manifest |
|---|---|
| Create the ivolve namespace | `00-namespace.yaml` |
| ConfigMap and Secret for the environment variables | `01-configmap.yaml`, `02-secret.yaml` |
| StorageClass to store the StatefulSet data | `03-storage.yaml` |
| Headless Service for the StatefulSet | `04-mysql-headless-service.yaml` |
| StatefulSet for the database | `05-mysql-statefulset.yaml` |
| Deployment and Service for each microservice | `06-auth-service.yaml`, `07-roadmap-service.yaml`, `08-frontend.yaml` |
| Ingress for the frontend | `09-ingress.yaml` |

The namespace is named `ivolve` in lowercase, because Kubernetes only accepts lowercase DNS labels for namespace names.

## Tools and Technologies

| Tool | Version | Purpose |
|---|---|---|
| Kubernetes (k3s on Floci) | v1.34.1+k3s1 | Cluster behind the emulated EKS |
| kubectl | v1.34.1 | Cluster management |
| Helm | 4.3.2 | Installs the ingress controller |
| Traefik | v3.7.19 | Ingress controller |
| MySQL | 8.0 | Database image |

## Architecture

```
                      Ingress (traefik) ivolve.local
                                |
                         Service frontend :80
                                |
                      Deployment frontend (2 replicas)
                        |                        |
          Service auth-service :5000     Service roadmap-service :8080
                        |                        |
       Deployment auth-service (2)      Deployment roadmap-service (2)
                        |
              Headless Service mysql
                        |
              StatefulSet mysql (mysql-0)
                        |
              PVC data-mysql-0 -> StorageClass ivolve-local

 ConfigMap ivolve-config  and  Secret ivolve-secret  inject the environment
```

## Repository Structure

```
k8s/
├── 00-namespace.yaml
├── 01-configmap.yaml
├── 02-secret.yaml
├── 03-storage.yaml
├── 04-mysql-headless-service.yaml
├── 05-mysql-statefulset.yaml
├── 06-auth-service.yaml
├── 07-roadmap-service.yaml
├── 08-frontend.yaml
├── 09-ingress.yaml
└── aws/
    └── storageclass-ebs.yaml     # StorageClass for a real EKS cluster
```

The files are numbered so that `kubectl apply -f k8s/` creates the namespace, configuration and storage before the workloads that use them.

## Step 1: Cluster Access

The cluster is reached through the standard AWS workflow. An IAM user and access key are created on the emulator, then the kubeconfig is generated:

```bash
aws iam create-user --user-name ivolve-admin
aws iam create-access-key --user-name ivolve-admin
aws eks update-kubeconfig --name ivolve-eks
kubectl get nodes -o wide
```

The access key is stored outside the repository. As an alternative, the kubeconfig of the k3s container can be copied directly from the container.

<img width="1706" height="523" alt="image" src="https://github.com/user-attachments/assets/61f92c12-2f83-4636-9cf0-7ba84fa829ad" />

## Step 2: Application Images

The three images are built from the sources in `app/` and tagged with the ECR repository URIs created in Step 3:

```
000000000000.dkr.ecr.us-east-1.localhost:4566/ivolve/frontend:v1
000000000000.dkr.ecr.us-east-1.localhost:4566/ivolve/auth-service:v1
000000000000.dkr.ecr.us-east-1.localhost:4566/ivolve/roadmap-service:v1
```

They are pushed to the registry behind the emulated ECR and loaded into the k3s node, so the manifests reference the same names that a real ECR deployment would use. Docker Desktop cannot resolve `*.localhost` host names, so the push goes to the registry port published by the emulator and the node imports the images directly. On AWS, pushing to ECR is sufficient.

## Step 3: Ingress Controller

A Kubernetes cluster does not include an ingress controller by default. Traefik is installed with Helm:

```bash
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set service.spec.type=ClusterIP
kubectl get ingressclass
```

Traefik was selected instead of ingress-nginx because the Kubernetes project ended maintenance of ingress-nginx in March 2026. The Service type is `ClusterIP` because the emulated cluster has no cloud load balancer; the controller is reached with `kubectl port-forward`.

<img width="857" height="401" alt="image" src="https://github.com/user-attachments/assets/36bb65e7-29b3-48bf-b70f-1147d772170f" />

## Step 4: Namespace, Configuration and Secret

`00-namespace.yaml` creates the `ivolve` namespace.

`01-configmap.yaml` holds the non-sensitive configuration:

| Key | Value | Used by |
|---|---|---|
| `MYSQL_DATABASE` | `ivolve` | MySQL, auth-service |
| `DB_HOST` | `mysql-0.mysql` | auth-service |
| `DB_PORT` | `3306` | auth-service |
| `AUTH_SERVICE_URL` | `http://auth-service:5000` | frontend |
| `ROADMAP_SERVICE_URL` | `http://roadmap-service:8080` | frontend |

`02-secret.yaml` holds the credentials: the MySQL root password, the application user and password, and the session secret. The values in the repository are development placeholders. In a real environment they come from a secret manager such as Sealed Secrets, External Secrets or SOPS and are never committed.

## Step 5: Database

**Storage.** `03-storage.yaml` defines the StorageClass `ivolve-local`, which uses the local-path provisioner of the k3s cluster with `WaitForFirstConsumer` binding and the `Retain` reclaim policy. For a real EKS cluster, `aws/storageclass-ebs.yaml` defines the same class name on the EBS CSI driver (`gp3`, encrypted), so the StatefulSet does not change between environments.

**Headless Service.** `04-mysql-headless-service.yaml` sets `clusterIP: None`. It gives each StatefulSet pod a stable DNS name such as `mysql-0.mysql`.

**StatefulSet.** `05-mysql-statefulset.yaml` runs one MySQL replica. The credentials come from the Secret and the database name from the ConfigMap. The `volumeClaimTemplates` entry creates the claim `data-mysql-0`, which follows the pod when it is recreated. The volume is mounted with `subPath: mysql`, which avoids initialization failures caused by the `lost+found` directory on freshly formatted volumes. Readiness and liveness probes run `mysqladmin ping`.

## Step 6: Microservices

Each microservice has a Deployment and a ClusterIP Service in one file.

| Service | Port | Replicas | Notes |
|---|---|---|---|
| auth-service | 5000 | 2 | Waits for MySQL in an init container, reads database settings from the ConfigMap and the Secret |
| roadmap-service | 8080 | 2 | Java heap limited with `MaxRAMPercentage` |
| frontend | 80 to 3000 | 2 | Reads the backend URLs from the ConfigMap and the session secret from the Secret |

Common settings:

- Rolling updates with `maxUnavailable: 0` and `maxSurge: 1`, so a release never removes a ready pod before its replacement is ready.
- CPU and memory requests and a memory limit on every container.
- `allowPrivilegeEscalation: false` on the application containers.
- Labels follow the `app.kubernetes.io` convention.
- Probes use TCP checks, because the health endpoints of the applications were not confirmed. They can be replaced with HTTP probes.

The init container of auth-service replaces the start-up ordering that `depends_on` provided in Docker Compose.

<img width="1100" height="73" alt="image" src="https://github.com/user-attachments/assets/508dcda1-7da8-4c6c-bac9-a68cf029ef00" />

## Step 7: Ingress

`09-ingress.yaml` routes the host `ivolve.local` to the frontend Service through the `traefik` ingress class. The ingress class name is the only environment-specific value in the file.

<img width="719" height="40" alt="image" src="https://github.com/user-attachments/assets/bc401e2d-72ca-44e7-8a51-9f84e2a2ec8c" />

## Step 8: Apply

```bash
kubectl apply --dry-run=server -f k8s/
kubectl apply -f k8s/
kubectl -n ivolve get pods -w
```

The server-side dry run validates the manifests against the live API without creating anything. The namespace is applied first, because a dry run cannot validate objects whose namespace does not exist yet.

<img width="1386" height="905" alt="image" src="https://github.com/user-attachments/assets/181fb826-9f02-49f8-b8a2-87da0f883b08" />

## Validation

```bash
kubectl -n ivolve get all,pvc,ingress
kubectl get pv
kubectl -n ivolve get configmap,secret
```

Expected results:

| Check | Expected result |
|---|---|
| Pods | `mysql-0` and all six application pods `1/1 Running` |
| Deployments | `2/2` for each microservice |
| StatefulSet | `1/1` |
| PVC | `data-mysql-0` is `Bound` to a volume of the class `ivolve-local` |
| Ingress | Class `traefik`, host `ivolve.local` |

<img width="1451" height="679" alt="image" src="https://github.com/user-attachments/assets/ad9c5b12-6f39-4cbe-94ba-40e39912df75" />

Application test through the Service:

```bash
kubectl -n ivolve port-forward svc/frontend 8081:80
```

Open `http://localhost:8081`, create an account and log in. The user must appear in the database:

```bash
kubectl -n ivolve exec mysql-0 -- sh -c \
  'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT username FROM users;"'
```

<img width="1701" height="912" alt="Screenshot 2026-11-21 085800" src="https://github.com/user-attachments/assets/82b854d8-2862-432d-b557-4c7fe375b9b4" />
<img width="1706" height="912" alt="Screenshot 2026-11-21 085829" src="https://github.com/user-attachments/assets/0a78a69e-f2d2-4e06-b6fe-2051cc3b5583" />
<img width="1420" height="280" alt="image" src="https://github.com/user-attachments/assets/d1338038-c29c-432b-a765-66a1a8f71c6d" />

Persistence test:

```bash
kubectl -n ivolve delete pod mysql-0
kubectl -n ivolve get pods -w
kubectl -n ivolve exec mysql-0 -- sh -c \
  'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT username FROM users;"'
```

The StatefulSet recreates `mysql-0` and the previously created user is still returned, because the pod reattaches to the same claim.

<img width="621" height="200" alt="image" src="https://github.com/user-attachments/assets/335a623d-19b5-499f-8bc3-d274940312a8" />
<img width="1433" height="62" alt="image" src="https://github.com/user-attachments/assets/93c895a3-ffca-476a-b455-dad7baba0519" />

Ingress test through the controller:

```bash
kubectl -n traefik port-forward svc/traefik 8082:80
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ivolve.local" http://localhost:8082/
```

<img width="1681" height="69" alt="image" src="https://github.com/user-attachments/assets/3498d7ce-6dec-4239-af0a-b5d331b4df4d" />

## Environment Notes

| Area | Floci | AWS |
|---|---|---|
| Nodes | One k3s node; the node group is metadata | Two worker nodes in private subnets |
| Kubernetes version | Cluster is declared as 1.33; the k3s image reports v1.34.1 | As declared |
| Storage | local-path provisioner | EBS CSI driver (`aws/storageclass-ebs.yaml`) |
| Images | Loaded into the node; registry reachable on the published port | Pulled from ECR |
| Ingress | Traefik behind a port-forward | Traefik or the AWS Load Balancer Controller behind a load balancer |
| Secrets | Development values in the repository | Secret manager |

## Conclusion

The application runs on Kubernetes with stateless microservices behind Services, a database with stable identity and persistent storage, configuration separated from the images and an ingress entry point. The manifests are the deployment source for the next stages: the Jenkins pipeline updates the image tags in these files and ArgoCD synchronizes the cluster with the repository.
