# Secret versions role

Fills every secret container declared in the project configuration. A value
either comes from the environment of the operator running the play, or — for
the containers the configuration marks as generated — is made up here on the
first run and left alone afterwards. It runs on `localhost`: this is an
operator task against a cloud API, not host configuration.

It covers both providers. A container is written in the cloud its readers run
in, taken from `default_cloud` and the per-VM `cloud` key, so nothing has to be
passed on the command line — and a container read from both clouds, which
Terraform creates on both sides, is written on both sides.

Terraform creates the containers and grants access to them, and never carries a
payload — see [docs/secrets.md](../../../../../../docs/secrets.md). This role is
the other half: the payload, and nothing else.

## What it guarantees

- Values are read from the process environment or made here, and from nowhere
  else. Nothing is written to disk.
- The payload reaches the provider on stdin — `--data-file=-` for `gcloud`,
  `--secret-string file:///dev/stdin` for the AWS CLI — so it never becomes a
  command argument and cannot appear in `ps` output or a shell history.
  `stdin_add_newline` is off, because a trailing newline would become part of
  the stored value.
- The upload task is marked `no_log`, so the value stays out of the Ansible
  output and out of any callback log, at every verbosity. So is the generation
  task.
- Every value and every container is checked before the first version is added.
  A run either writes all of them or none: half-rotated is the state that
  leaves one workload on the new credential and the rest on the old one.

Run it with `--check` first. In check mode the role performs every check and
adds nothing.

## What gets written, and what does not

The role asks the provider what each container already holds, and writes only
where writing is the point:

| environment | container | what happens |
| --- | --- | --- |
| holds a value | anything | uploaded — an explicit value is a rotation and always wins |
| empty | already filled | left alone; re-running a deployment is not a reason to rotate a live credential |
| empty | empty, in `generated_secrets` | a 40-character alphanumeric value is generated and uploaded |
| empty | empty, not listed | the play fails, naming the variable, before anything is written |

`generated_secrets` lists the containers that have no source outside the
deployment — a database password is the usual case. Credentials that do exist
outside it, a registry token or a third-party API key, are not on that list and
have to be supplied the first time.

Two things follow. A brand new environment needs only the credentials that come
from elsewhere, because the rest are invented here. And a routine re-run needs
nothing exported at all, because every container is already filled — which is
what makes `terraform apply` followed by one `ansible-playbook` the whole
deployment.

Generation happens here and not in Terraform on purpose. `random_password`
would write the value into the state file, and the state is not a place for a
payload.

The alphabet is deliberately alphanumeric. Punctuation is fine in a secret and
not fine in a value something downstream concatenates into a URL — a `/` in a
password once turned a `postgres://` DSN into a different host.

The decision is printed before anything is written, so a run that leaves a
container alone says so rather than being silent about it.

## Requirements

For GCP: `gcloud`, authenticated as a principal holding
`roles/secretmanager.secretVersionAdder` on the containers. That role permits
adding a version and not reading one, so rotation does not require access to
the current value. Terraform grants it from the `secret_version_managers`
variable. Listing existing versions additionally needs
`roles/secretmanager.viewer`; without it the role treats the container as empty
and writes a new version, which is safe but not idempotent.

For AWS: the AWS CLI, authenticated as a principal allowed
`secretsmanager:PutSecretValue` and `secretsmanager:ListSecretVersionIds` on
the containers — the same split, granted by Terraform from
`secret_version_manager_arns`.

Only the providers actually in use are contacted, so a GCP-only configuration
needs no AWS credentials.

The containers must already exist: `terraform apply` creates them from the same
configuration file this role reads.

## Required variables

- `secret_versions_config_file`: path to the project configuration JSON — the
  same file `project_config_path` points at in Terraform. The `site.yml`
  playbook sets it from `project_config_path`, so a full deployment needs only
  that one path.

## Optional variables

- `secret_versions_project_id`: target GCP project. Falls back to
  `$GOOGLE_PROJECT`, then to `gcp.project_id` in the configuration.
- `secret_versions_region`: target AWS region. Falls back to `$AWS_REGION`, then
  to `$AWS_DEFAULT_REGION`, then to the first entry of `aws.regions` in the
  configuration.
- `secret_versions_only`: list of container IDs or variable names to upload.
  Defaults to all of them; use it to rotate one credential.
- `secret_versions_generate`: extra containers the role may invent a value for,
  on top of `generated_secrets` in the configuration.
- `secret_versions_gcloud`: path to the `gcloud` executable.
- `secret_versions_aws`: path to the `aws` executable.

## Which variable holds which value

The variable name is derived from the container ID, with the
`<name_prefix>-<environment>-` prefix dropped while that stays unambiguous:

```
oilscope-dev-db-password     ->  DB_PASSWORD
oilscope-dev-oilpriceapi-key ->  OILPRICEAPI_KEY
```

It is deliberately not the key side of `secret_mappings`. That key is the
variable the application reads *inside one VM*, so the same name can mean a
different container on two workloads and one shell cannot hold both. If
dropping the prefix would make two containers collide, every container keeps
the fully qualified name (`OILSCOPE_DEV_DB_PASSWORD`) instead.

The role prints the mapping before it uploads anything, and marks the
containers it is allowed to generate, so there is nothing to guess.

## Example

Only the credentials that come from outside are exported. The database password
is in `generated_secrets`, so it is left to the role:

```bash
 export GHCR_TOKEN="..."
 export OILPRICEAPI_KEY="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json
```

The leading space keeps the export out of the shell history, in a shell
configured to honour it.

Rotating one credential, generated or not:

```bash
 export DB_PASSWORD="$(openssl rand -hex 32)"

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json \
  -e '{"secret_versions_only": ["DB_PASSWORD"]}'
```

Older versions stay until they are destroyed, so an upload is reversible until
then.

## License

GPL-2.0-or-later
