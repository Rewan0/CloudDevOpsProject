# Step 4: Configuration Management with Ansible

## Overview

This step configures the Jenkins EC2 instance created by Terraform in Step 3. Ansible installs and configures Java, Docker, Jenkins and Trivy using one role per component, and discovers the target server through a dynamic inventory instead of a hardcoded address.

Terraform builds the server; Ansible prepares what runs inside it. Both tools are driven from the same repository, and the only link between them is the set of tags on the EC2 instance (`Role=jenkins`).

### Objectives

- Install Java, Jenkins, Docker and Trivy on the Jenkins server.
- Organize the configuration into reusable Ansible roles.
- Discover the server through a dynamic inventory based on EC2 tags.
- Keep every run idempotent, so a second run changes nothing.
- Support both the Floci emulator and real AWS with separate inventories.

### Requirement Mapping

| Requirement | Implementation |
|---|---|
| Install Java | Role `java` |
| Install Jenkins | Role `jenkins` |
| Install the required packages (Docker, Trivy) | Roles `docker` and `trivy` |
| Use Ansible roles | Five roles: `common`, `java`, `docker`, `jenkins`, `trivy` |
| Use Dynamic Inventory | `amazon.aws.aws_ec2` inventory plugin, filtered by the `Role=jenkins` tag |

## Tools and Technologies

| Tool | Purpose |
|---|---|
| Ansible core 2.20.1 | Configuration management |
| `amazon.aws` collection | Dynamic inventory plugin `aws_ec2` |
| boto3 / botocore | AWS API client used by the inventory plugin |
| Floci | Local AWS emulator that hosts the EC2 instance |
| Terraform (Step 3) | Creates the instance and its tags |

## Architecture

```
  Terraform (Step 3)                     Ansible (Step 4)
 +--------------------+            +------------------------------+
 | EC2 instance       |  tags      | Dynamic inventory            |
 | Name = ivolve-     | ---------> | plugin: amazon.aws.aws_ec2   |
 |        jenkins     |  Role=     | filter: tag:Role=jenkins     |
 | Role = jenkins     |  jenkins   | group:  role_jenkins         |
 +--------------------+            +--------------+---------------+
                                                  |
                                   site.yml       v
                                  common -> java -> docker -> jenkins -> trivy
```

The `docker` role runs before `jenkins` so that the `jenkins` user can be added to the `docker` group during installation. The `jenkins` pipeline built in the next steps uses Docker and Trivy.

## Repository Structure

```
ansible/
├── ansible.cfg
├── requirements.yml
├── site.yml                    # Main playbook
├── verify.yml                  # Post-configuration checks
├── inventories/
│   ├── floci/
│   │   ├── aws_ec2.yml         # Dynamic inventory (emulator)
│   │   └── group_vars/all.yml  # Connection settings for the emulator
│   └── aws/
│       ├── aws_ec2.yml         # Dynamic inventory (real AWS)
│       └── group_vars/all.yml  # Connection settings for AWS
└── roles/
    ├── common/
    ├── java/
    ├── docker/
    ├── jenkins/
    └── trivy/
```

## Prerequisites

- The Terraform stack from Step 3 applied, with the Jenkins instance running.
- Ansible, `boto3` and `botocore` installed on the control machine.
- The SSH private key matching the key pair created by Terraform (`~/.ssh/ivolve-jenkins`).
- The Floci environment variables loaded:

```bash
source ~/floci.env
ansible-galaxy collection install -r requirements.yml
```

## Step 1: Dynamic Inventory

The inventory file `inventories/floci/aws_ec2.yml` queries the EC2 API for running instances tagged `Role=jenkins`:

```yaml
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
filters:
  tag:Role: jenkins
  instance-state-name: running
hostnames:
  - tag:Name
compose:
  ansible_host: public_ip_address
keyed_groups:
  - key: tags.Role
    prefix: role
    separator: "_"
```

The `keyed_groups` block creates the group `role_jenkins` from the tag value, and the playbook targets that group. If the instance is replaced and receives a new address, the inventory follows it without any edit.

```bash
ansible-inventory --graph
ansible-inventory --host ivolve-jenkins
ansible role_jenkins -m ping
```

<img width="1707" height="1019" alt="image" src="https://github.com/user-attachments/assets/9e62eed0-07be-455b-9520-e978a0be399e" />
<img width="1707" height="1019" alt="image" src="https://github.com/user-attachments/assets/71cff978-4c8e-4ccb-8908-ba489a75bb9b" />

## Step 2: Roles

| Role | What it does |
|---|---|
| `common` | Installs base packages (`curl`, `gnupg`, `ca-certificates`, `unzip`) and creates the apt keyrings directory |
| `java` | Installs the OpenJDK headless runtime and `fontconfig` |
| `docker` | Adds the official Docker apt repository with its signing key and installs Docker Engine, the CLI, containerd, Buildx and Compose |
| `jenkins` | Adds the Jenkins stable apt repository with the current signing key, installs Jenkins, adds the `jenkins` user to the `docker` group and starts the service |
| `trivy` | Adds the Aqua Security apt repository and installs Trivy |

Design notes:

- Every download task uses `retries` and `until`, so a temporary network failure does not fail the run.
- Repository keys are stored under `/etc/apt/keyrings` and referenced with `signed-by`, so each key only authorizes its own repository.
- The Jenkins role uses the 2026 repository signing key published by the Jenkins project and removes the retired key and repository entry if they exist.
- The Jenkins role does not print the initial administrator password. It only reports where the file is located on the server.
- Service handling depends on the host: on a systemd host the roles use the `systemd` module; on a host without systemd the Docker role reports that the daemon is not started and the Jenkins role starts the Jenkins process directly.

## Step 3: Playbook

`site.yml` targets the `role_jenkins` group. Because the first task must work before Python is guaranteed to exist on the host, it uses the `raw` module to install Python, then gathers facts and applies the roles in order:

```
common -> java -> docker -> jenkins -> trivy
```

Each role carries a tag, so a single component can be applied alone, for example `ansible-playbook site.yml --tags trivy`.

## Step 4: Run the Playbook

```bash
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml
```

<img width="1706" height="122" alt="image" src="https://github.com/user-attachments/assets/7f6766d6-8c79-4ba7-85aa-8eb38d315571" />
<img width="1707" height="1019" alt="image" src="https://github.com/user-attachments/assets/5c0da5ae-6055-4eea-96da-a8c1325f45d8" />

## Step 5: Idempotency

Running the playbook a second time must not change anything:

```bash
ansible-playbook site.yml
```

Expected recap:

```
ivolve-jenkins : ok=22  changed=0  unreachable=0  failed=0  skipped=3
```

The three skipped tasks are the systemd-only tasks, which do not apply to the emulated host.

<img width="1707" height="1019" alt="image" src="https://github.com/user-attachments/assets/856a2f10-bbeb-44ee-8815-690e7f8f703d" />

## Validation

`verify.yml` collects the installed versions, checks the group membership of the `jenkins` user and confirms that Jenkins answers over HTTP:

```bash
ansible-playbook verify.yml
```

Observed results:

| Check | Result |
|---|---|
| Java | OpenJDK 21 |
| Docker | Docker 29.10.0 |
| Trivy | 0.71.2 |
| `jenkins` user | Member of the `docker` group |
| Jenkins HTTP check | Responds on port 8080 |

Jenkins is reachable through the port that the emulator forwards to the instance. List it with:

```bash
docker ps --format '{{.Names}}  {{.Ports}}' | grep 8080
```

Open the forwarded local port in a browser to reach the Unlock Jenkins page. The initial administrator password is stored on the server at `/var/lib/jenkins/secrets/initialAdminPassword`.

<img width="1663" height="545" alt="image" src="https://github.com/user-attachments/assets/727bdaa6-53bd-466d-94a4-d7c927fa6a7f" />
<img width="1545" height="139" alt="image" src="https://github.com/user-attachments/assets/19a86897-e16e-49d1-8433-fb21e78ca6ef" />

## Environment Notes

The configuration targets AWS. The emulator differs in the following points, and the repository handles them with a separate inventory per environment.

| Area | Floci | AWS |
|---|---|---|
| SSH user | `root` | `ubuntu` |
| SSH port | Forwarded local port (2200) | 22 |
| Privilege escalation | Not needed (already root) | `sudo` |
| Host key checking | Disabled for the local emulator only | Enabled |
| Service manager | No systemd in the instance container | systemd |
| Jenkins service | Process started directly by the role | systemd service |
| Docker daemon | Installed, not started | Started and enabled |

On Floci the Docker daemon cannot run inside the instance container, so image builds in the pipeline stage are executed on a host that has a running Docker daemon. On AWS the instance runs systemd and the Docker daemon starts normally.

## Using Real AWS

```bash
ansible-playbook -i inventories/aws site.yml
```

The AWS inventory connects as `ubuntu` on port 22 with `sudo`. Load valid AWS credentials in the environment (without the `AWS_ENDPOINT_URL` override) before running the inventory plugin. This path has not been executed against a real account in this project.

## Conclusion

The Jenkins server is configured entirely from code: Java, Docker, Jenkins and Trivy are installed through five roles, the target is discovered through a dynamic inventory based on EC2 tags, and a second run reports no changes. The result is a Jenkins server with Docker and Trivy available to the `jenkins` user, ready for the continuous integration pipeline, while the Kubernetes manifests in the next step describe how the application runs on the cluster.
