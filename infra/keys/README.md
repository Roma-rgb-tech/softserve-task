# Authorized keys

Every `*.pub` file here becomes a login on all five VMs. **The filename is the
username** — `roman.pub` creates the user `roman` with that key in
`~/.ssh/authorized_keys`.

Each account gets passwordless sudo and membership in the `docker` group, so
whoever logs in can inspect containers without another privilege hop.

## Adding yourself

```bash
cp ~/.ssh/id_ed25519.pub infra/keys/roman.pub   # or id_rsa.pub
```

If you don't have a key yet:

```bash
ssh-keygen -t ed25519 -C "roman@example.com"
```

## Adding someone else

Ask for their **public** key — the `.pub` half, never the private one — and
save it under their name:

```bash
infra/keys/dmytro.pub
infra/keys/pavlo.pub
```

A file may hold several keys, one per line, if the same person logs in from
more than one machine.

## Applying

```bash
sudo -E vagrant provision
```

The script is idempotent: re-running only adds what's missing, so provisioning
repeatedly never duplicates users or key lines.

## Logging in

```bash
ssh roman@192.168.88.202
```

No `vagrant ssh`, no sudo on the host — these are ordinary SSH logins over the
LAN, which is the whole point.

## A note on committing these

Public keys are safe to share; that is what makes them public. What must never
end up here is a private key — anything without the `.pub` extension, or any
file starting with `-----BEGIN OPENSSH PRIVATE KEY-----`.
