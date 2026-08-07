# Lessons Learned

Gotchas and insights from building and validating these playbooks against a production Proxmox cluster.

## proxmox_pct_remote Connection Plugin

### Stopped containers produce misleading errors

When a container is stopped, `proxmox_pct_remote` fails with "Failed to create temporary directory" (exit 255). The error suggests a permissions or path issue, but the real cause is that `pct exec` can't attach to a stopped container. The fix is to start containers before running tasks against them — see the `lxc_start_stopped.yml` / `lxc_stop_restored.yml` lifecycle pattern.

### Zombie container state

A container can report as "running" via `pct status` while its init process has actually crashed. `lxc-attach` then fails with "Connection refused - Failed to get init pid". This can happen when HA manages the container. A force stop and restart resolves it.

## Delegation Scoping Bug

When using `delegate_to` with a host whose `ansible_host` is a Jinja template (e.g., `"{{ inventory_hostname }}.management.internal"`), Ansible evaluates the template using the *source* host's `inventory_hostname`, not the delegate's. This produces the wrong hostname. The fix is to use static `ansible_host` values for any host that will be a delegation target.

## Community Scripts (Proxmox Helper Scripts)

### CTID is only needed from the PVE host

The `update` command installed by community scripts inside a container doesn't need `CTID=` — that's only for running PHS commands from the PVE host targeting a container by ID. Inside the container, just call `update` directly.

### Non-interactive execution

Community scripts use whiptail for interactive dialogs. For automation, set environment variables (e.g., `PHS_SILENT=1`) and pipe from `/dev/null` to suppress interactive prompts.

## Ansible Syntax Checks

### mandatory() filter breaks --syntax-check

Playbooks using `{{ var | mandatory('message') }}` in the `hosts:` field will fail `--syntax-check` because the variable isn't defined at syntax-check time. The workaround is to pass a dummy value: `ansible-playbook playbook.yml -e var=syntax_check --syntax-check`.

## Git Hooks

### pre-commit hooks and tool-driven commits

When commits are made programmatically (e.g., via IDE extensions or CLI tools), pre-commit hook output may not be visible. If the hook gates on syntax checks, a failure can silently block the checklist reset that was supposed to happen after the checks pass.
