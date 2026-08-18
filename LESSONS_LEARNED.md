# Lessons Learned

Gotchas and insights from building and validating these playbooks against a production Proxmox cluster.

## proxmox_pct_remote Connection Plugin

### Stopped containers produce misleading errors

When a container is stopped, `proxmox_pct_remote` fails with "Failed to create temporary directory" (exit 255). The error suggests a permissions or path issue, but the real cause is that `pct exec` can't attach to a stopped container. The fix is to start containers before running tasks against them — see the `roles/lxc/tasks/start_stopped.yml` / `stop_restored.yml` lifecycle pattern.

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

## Jinja2 urlencode and GitLab API

### urlencode does NOT encode forward slashes

Jinja2's `urlencode` filter does not encode `/` characters. When passing a GitLab project path (e.g., `homelab/services/ops/prometheus-config`) to the API, you must use `regex_replace('/', '%2F')` instead of `urlencode`. The unencoded slashes silently change the API path, resulting in 404 errors that look like permission issues.

## pct_remote and become

### become must be false for pct_remote hosts

The `community.proxmox.proxmox_pct_remote` connection runs as root inside the container. Setting `become: true` causes "sudo: not found" errors. For playbooks targeting mixed groups (SSH hosts + pct_remote containers), use dynamic become:

```yaml
become: "{{ ansible_connection | default('ssh') != 'community.proxmox.proxmox_pct_remote' }}"
```

### Delegated tasks need explicit become

When a play has `become: false` (for pct_remote), delegated tasks to PVE hosts still need root for `pct` commands. Add `become: true` on each delegated task — it overrides the play-level setting for that task only.

### remote_tmp must be rooted in /tmp

The default `~/.ansible/tmp` fails on pct_remote containers because there's no home directory. Set `remote_tmp = /tmp/.ansible/tmp` in `ansible.cfg`.

## Check Mode and LXC Lifecycle

### Stopped containers must be skipped in --check mode

The start_stopped/stop_restored lifecycle tasks cannot work in `--check` mode — starting a container is a real side effect. Use `check_mode: false` on the read-only status check, then `meta: end_host` to cleanly skip stopped containers during dry runs.

## GitLab Fine-Grained Tokens

### Tokens cannot be edited after creation

If a fine-grained personal access token is missing a permission (e.g., `User: Read` for `POST /api/v4/user/runners`), you must create a new token — existing tokens cannot have permissions added.

### Required scopes for runner and deploy key management

- Runner registration (`POST /api/v4/user/runners`): needs `User: Read`
- Deploy key management: needs `Project: Read`, `Deploy Key: Read/Create/Delete`

## Git Hooks

### pre-commit hooks and tool-driven commits

When commits are made programmatically (e.g., via IDE extensions or CLI tools), pre-commit hook output may not be visible. If the hook gates on syntax checks, a failure can silently block the checklist reset that was supposed to happen after the checks pass.
