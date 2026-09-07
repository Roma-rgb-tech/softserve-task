# Ansible Collection - oilscope.platform

Documentation for the collection.

## Validate configuration

Before deploying, validate your project configuration file against the schema:

​```bash
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
​```

## Running it from the working tree

`ANSIBLE_COLLECTIONS_PATH=.ansible/collections` in the repository root points at
a symlink to this directory, so edits to a role take effect on the next run.
Without it Ansible uses whatever `ansible-galaxy collection install` last copied
into `~/.ansible`, and a changed role appears to do nothing until it is
reinstalled. `.envrc.example` sets it.

## Deploy everything

`site.yml` is the whole deployment in one command: it fills the secret
containers Terraform created, moves the bastion onto its final SSH port,
deploys the workloads in dependency order, and installs the monitoring agents
last, once there are container logs for them to ship.

```bash
terraform -chdir=infrastructure/terraform apply \
  -var=project_config_path="$OILSCOPE_PROJECT_CONFIG"

ansible-playbook oilscope.platform.site \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"
```

One path drives all of it - the same file Terraform reads.

Nothing else has to be exported for a routine run. The bastion's SSH port is
worked out by probing it rather than announced; host keys go into a
known_hosts file of this project's own, so a rebuilt environment does not
poison the personal one; and a secret container that already holds a value is
left alone, so only a brand new environment needs the two credentials that come
from outside the deployment. `.envrc.example` in the repository root shows how
to keep even those out of the shell history. See
[docs/secrets.md](../../../../docs/secrets.md).

The steps below are the same plays run on their own.

## Deploy all workloads

Deploy the application workloads in dependency order:

1. Database
2. History
3. Fetcher
4. UI

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

## Install the monitoring agents

Alerts, dashboards and budgets are created by Terraform; the agent that reports
memory, disk and container logs is installed by Ansible:

```bash
ansible-playbook oilscope.platform.monitoring \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

See [docs/monitoring.md](../../../../docs/monitoring.md).
