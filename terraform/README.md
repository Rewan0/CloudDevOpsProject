# Step 3: Infrastructure Provisioning with Terraform

## Overview

This step provisions the complete AWS infrastructure for the CloudDevOpsProject platform as code. The infrastructure is split into four reusable Terraform modules (network, server, EKS, ECR) and uses a remote S3 backend with state locking.

The project does not use a real AWS account. All resources are provisioned and validated against **Floci**, a local AWS emulator that exposes the real AWS API on `http://localhost:4566`. The Terraform code uses the standard `hashicorp/aws` provider and a single variable (`use_floci`) that switches between the emulator and real AWS, so the same code base targets both environments.

### Objectives

- Provision a multi-AZ network with public and private subnets, Internet Gateway, NAT Gateway and Network ACLs.
- Provision an EC2 instance with a Security Group to host Jenkins.
- Provision an EKS cluster with a managed node group of two worker nodes in private subnets across two Availability Zones.
- Provision an ECR repository for each microservice.
- Store the Terraform state remotely in S3 with locking in DynamoDB.

### Requirement Mapping

| Requirement | Implementation |
|---|---|
| Network module (VPC, public and private subnets, IGW, NAT, Network ACL) | `modules/network` |
| Server module (EC2 for Jenkins with Security Groups) | `modules/server` |
| EKS module (2 worker nodes in different private subnets and AZs) | `modules/eks` |
| ECR module | `modules/ecr` |
| S3 Terraform backend | `backend.tf` and `backend-floci.hcl` |

## Tools and Technologies

| Tool | Version | Purpose |
|---|---|---|
| Terraform | 1.17.2 | Infrastructure as code |
| AWS provider (`hashicorp/aws`) | 6.73.0 | AWS resources |
| Floci | 2.1.0 | Local AWS emulator |
| AWS CLI | 2.31.35 | Backend bootstrap and verification |
| Docker | n/a | Runs Floci and the emulated EC2, ECR and EKS resources |

## Architecture

```
                         VPC 10.0.0.0/16
 +-----------------------------------------------------------------+
 |                                                                 |
 |   us-east-1a                          us-east-1b                |
 |  +-------------------------+         +-------------------------+|
 |  | Public  10.0.1.0/24     |         | Public  10.0.2.0/24     ||
 |  |  - Jenkins EC2          |         |                         ||
 |  |  - NAT Gateway          |         |                         ||
 |  +------------+------------+         +-------------------------+|
 |               | Route: 0.0.0.0/0 -> Internet Gateway            |
 |  +------------+------------+         +-------------------------+|
 |  | Private 10.0.11.0/24    |         | Private 10.0.12.0/24    ||
 |  |  - EKS worker node      |         |  - EKS worker node      ||
 |  +-------------------------+         +-------------------------+|
 |               Route: 0.0.0.0/0 -> NAT Gateway                   |
 +-----------------------------------------------------------------+

 ECR: ivolve/frontend, ivolve/auth-service, ivolve/roadmap-service
 State: S3 bucket ivolve-tfstate + DynamoDB table tflock
```

## Repository Structure

```
terraform/
├── backend.tf              # Partial S3 backend configuration
├── backend-floci.hcl       # Backend values for Floci
├── versions.tf             # Terraform and provider versions
├── providers.tf            # AWS provider with Floci toggle
├── variables.tf            # Core variables
├── network_variables.tf    # Network CIDR variables
├── main.tf                 # Network module call
├── ecr.tf                  # ECR module call
├── server.tf               # Server module call
├── eks.tf                  # EKS module call
├── outputs.tf
└── modules/
    ├── network/
    ├── server/
    ├── eks/
    └── ecr/
```

## Prerequisites

- Docker with Floci running and healthy.
- Terraform 1.6 or later.
- AWS CLI.
- An SSH key pair for the Jenkins server.

Environment variables used for every AWS CLI command (stored in `~/floci.env`):

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_PAGER=""
```

Verify that Floci is running:

```bash
curl -s http://localhost:4566/_floci/health
```

<img width="1692" height="298" alt="image" src="https://github.com/user-attachments/assets/cceb2bd1-9794-4683-a4e3-a9e44c32f0db" />

## Step 1: Bootstrap the Remote Backend

The state bucket and the lock table are created before Terraform runs, because Terraform cannot create the backend that stores its own state.

```bash
source ~/floci.env
aws s3 mb s3://ivolve-tfstate
aws dynamodb create-table --table-name tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

The backend block is intentionally empty (`backend "s3" {}`). Environment-specific values live in `backend-floci.hcl`, so the same configuration can point to real AWS with a different file.

<img width="1018" height="960" alt="image" src="https://github.com/user-attachments/assets/9acfb549-b3f6-42d1-9c65-f7615dc9aded" />

## Step 2: Configure the Provider

`providers.tf` defines one AWS provider. When `use_floci = true` it uses dummy credentials, skips account and credential validation, enables path-style S3 addressing and points the service endpoints (EC2, EKS, ECR, IAM, STS, S3, DynamoDB, ELBv2) to Floci. When `use_floci = false` none of these overrides apply and the provider uses normal AWS authentication.

Initialize the working directory:

```bash
cd terraform
terraform init -backend-config=backend-floci.hcl
terraform validate
```

<img width="976" height="712" alt="image" src="https://github.com/user-attachments/assets/41622e07-a192-4f8a-bc8f-6d7a20c7ed45" />

## Step 3: Network Module

Location: `modules/network`

| Resource | Details |
|---|---|
| VPC | `10.0.0.0/16`, DNS support and hostnames enabled |
| Public subnets | `10.0.1.0/24` (us-east-1a), `10.0.2.0/24` (us-east-1b) |
| Private subnets | `10.0.11.0/24` (us-east-1a), `10.0.12.0/24` (us-east-1b) |
| Internet Gateway | Attached to the VPC |
| NAT Gateway | One gateway with an Elastic IP in the first public subnet |
| Route tables | Public route to the Internet Gateway, private route to the NAT Gateway |
| Network ACLs | Separate stateless ACLs for public and private subnets |

Design notes:

- Public subnets are tagged `kubernetes.io/role/elb` and private subnets `kubernetes.io/role/internal-elb`, which EKS uses to place load balancers.
- The public Network ACL allows HTTP and HTTPS from anywhere, and SSH and port 8080 only from the `admin_cidr` variable. Because Network ACLs are stateless, ephemeral ports 1024 to 65535 are allowed for return traffic.
- A single NAT Gateway is used to limit cost. A production deployment would use one NAT Gateway per Availability Zone to remove the single point of failure.

The module creates 18 resources.

<img width="1706" height="416" alt="image" src="https://github.com/user-attachments/assets/7dbabca3-3380-4fab-9f77-311d9fcfd76b" />
<img width="1701" height="914" alt="image" src="https://github.com/user-attachments/assets/bae4a89a-211e-4b71-9d76-9061cb44e546" />
<img width="1698" height="917" alt="image" src="https://github.com/user-attachments/assets/e4b546b5-1b5f-4aea-911f-2fe5314e4ec3" />

## Step 4: ECR Module

Location: `modules/ecr`

One repository is created per microservice with `for_each`: `ivolve/frontend`, `ivolve/auth-service` and `ivolve/roadmap-service`.

- Scan on push is enabled.
- Encryption uses AES256.
- A lifecycle policy keeps the last 10 images.
- `force_delete` allows `terraform destroy` to remove repositories that still contain images.

The module creates 6 resources (3 repositories and 3 lifecycle policies).

<img width="1706" height="173" alt="image" src="https://github.com/user-attachments/assets/46d093e2-da53-4503-885c-e3874a9843f5" />

## Step 5: Server Module

Location: `modules/server`

| Resource | Details |
|---|---|
| EC2 instance | Ubuntu 22.04, `t3.medium`, public subnet, tagged `Role=jenkins` |
| Security Group | Inbound SSH (22) and Jenkins UI (8080) only from `admin_cidr`, all outbound allowed |
| Key pair | Imports the public key only; no private key is stored in the repository |

Hardening applied in the instance definition:

- IMDSv2 is required (`http_tokens = required`).
- The root volume is defined as 30 GB `gp3` and encrypted.
- Access is limited to a single administrator address through `admin_cidr`.

Set `admin_cidr` in `terraform.tfvars` (not committed):

```hcl
admin_cidr = "<your-public-ip>/32"
ami_id     = "ami-ubuntu2204"   # Floci image; leave unset on AWS
```

When `ami_id` is not set, the module looks up the latest Canonical Ubuntu 22.04 AMI, which is the behavior intended for real AWS.

The module creates 3 resources.


## Step 6: EKS Module

Location: `modules/eks`

| Resource | Details |
|---|---|
| Cluster IAM role | Trusted by `eks.amazonaws.com`, `AmazonEKSClusterPolicy` attached |
| Node IAM role | Trusted by `ec2.amazonaws.com`, with `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` and `AmazonEC2ContainerRegistryReadOnly` |
| EKS cluster | Name `ivolve-eks`, Kubernetes 1.33, subnets are the two private subnets |
| API endpoint | Private access enabled, public access restricted to `admin_cidr` |
| Managed node group | Desired 2, minimum 2, maximum 3, instance type `t3.medium`, private subnets in two Availability Zones |

The ECR read-only policy on the node role lets the worker nodes pull images from the ECR repositories created in Step 4.

The module creates 8 resources. Before using the Kubernetes version on real AWS, confirm that it is currently supported by EKS.


## Step 7: Plan and Apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Saving the plan to a file guarantees that `apply` runs exactly the reviewed actions. The plan file is excluded from version control.

Total resources created by the configuration: 35 (network 18, ECR 6, server 3, EKS 8).

![terraform apply](../docs/screenshots/step3-08-apply.png)

## Validation

```bash
source ~/floci.env

# Network
aws ec2 describe-vpcs --filters Name=tag:Project,Values=ivolve \
  --query "Vpcs[].[VpcId,CidrBlock]" --output table
aws ec2 describe-subnets --filters Name=tag:Project,Values=ivolve \
  --query "Subnets[].[Tags[?Key=='Name']|[0].Value,CidrBlock,AvailabilityZone]" --output table
aws ec2 describe-nat-gateways --query "NatGateways[].[NatGatewayId,State]" --output table

# ECR
aws ecr describe-repositories \
  --query "repositories[].[repositoryName,imageScanningConfiguration.scanOnPush]" --output table

# Server
aws ec2 describe-instances \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,SubnetId]" --output table
aws ec2 describe-security-groups --filters Name=group-name,Values=ivolve-jenkins-sg \
  --query "SecurityGroups[].IpPermissions[].[FromPort,IpRanges[].CidrIp]" --output json

# EKS
aws eks describe-cluster --name ivolve-eks \
  --query "cluster.[name,status,version,endpoint]" --output table
aws eks describe-nodegroup --cluster-name ivolve-eks --nodegroup-name ivolve-eks-nodes \
  --query "nodegroup.[status,scalingConfig,subnets]" --output json

# Remote state
aws s3 ls s3://ivolve-tfstate/cloud-devops/

# Idempotency
terraform plan
```

Expected results:

| Check | Expected result |
|---|---|
| VPC | `10.0.0.0/16` |
| Subnets | Two public and two private, in `us-east-1a` and `us-east-1b` |
| NAT Gateway | State `available` |
| ECR | Three repositories with scan on push enabled |
| Security Group | Ports 22 and 8080 restricted to the administrator address |
| EKS cluster | Status `ACTIVE`, version `1.33` |
| Node group | Status `ACTIVE`, desired size 2, both private subnets |
| State file | `terraform.tfstate` present in the S3 bucket |
| `terraform plan` | `No changes. Your infrastructure matches the configuration.` |

![Validation results](../docs/screenshots/step3-09-validation.png)

## Floci Compatibility Notes

The configuration was validated against Floci 2.1.0. The following behaviors of the emulator differ from AWS and are reflected in the code:

| Area | Behavior on Floci | Handling |
|---|---|---|
| Network ACL tags | Tags passed at creation are not stored; they are stored on the next update | A second `apply` converges; no code change required |
| Root volume | Size and encryption settings are not reported back | `lifecycle { ignore_changes = [root_block_device] }` on the instance; the settings still apply on AWS at creation |
| SSH access | The key pair is installed for the `root` user and the instance is reachable through a forwarded port (2200) | The Ansible inventory uses a configurable user (`root` on Floci, `ubuntu` on AWS) |
| EKS | Cluster runs as a single k3s container (API at `https://localhost:6500`); the node group is recorded as metadata | The Terraform definition (2 nodes across 2 AZs) is validated; real worker nodes require AWS |
| EC2 public address | The instance is reported with `127.0.0.1` | Use the forwarded ports locally |

These items affect only the emulator. The module code is written for AWS.

## Switching to Real AWS

1. Set `use_floci = false` (for example in `terraform.tfvars`).
2. Create a backend file for the real bucket, for example `backend-aws.hcl`:

   ```hcl
   bucket         = "<your-state-bucket>"
   key            = "cloud-devops/terraform.tfstate"
   region         = "us-east-1"
   dynamodb_table = "<your-lock-table>"
   encrypt        = true
   ```
3. Authenticate with AWS credentials and run `terraform init -reconfigure -backend-config=backend-aws.hcl`.

This path has not been executed against a real account in this project. Review costs first: the NAT Gateway and the EKS control plane are billed hourly.

## Cleanup

```bash
terraform destroy
```

The state bucket and the lock table are created outside Terraform and are removed separately.

## Conclusion

The infrastructure layer is fully defined as code: a multi-AZ network, a hardened Jenkins server, an EKS cluster with two worker nodes in private subnets, and an ECR registry for each microservice, all stored in a remote, locked state. The configuration is idempotent (`terraform plan` reports no changes after `apply`) and reusable through modules and variables. The outputs of this step (ECR repository URLs, the Jenkins instance and the EKS endpoint) are the inputs for the next stages: server configuration with Ansible, the CI pipeline with Jenkins and the deployment with ArgoCD.
