# Proxmox Ansible Automation

Ansible playbooks and roles for managing a Proxmox VE cluster — LXC container provisioning, GitLab Runner deployment, system updates, and monitoring.

## Prerequisites

- **Ansible** 2.9+
- **Collections:** `community.proxmox` (for `proxmox_pct_remote` connection plugin)
- **SSH access** to Proxmox nodes via the `ansible` service account
- **Vault password** in `.vault_pass` (or use `--ask-vault-pass`) for GitLab Runner secrets

## Quick Start

```bash
# 1. Clone and enter the repo
git clone <repo-url> && cd ansible

# 2. Install required collections
ansible-galaxy collection install community.proxmox

# 3. Create the vault password file
echo 'your-vault-password' > .vault_pass

# 4. Bootstrap the ansible service account on new hosts
ansible-playbook playbooks/bootstrap_ansible.yml --limit pve01 --ask-pass

# 5. Run a playbook
ansible-playbook playbooks/apt_upgrade.yml
```

## Project Structure

```
.
├── ansible.cfg                  # Ansible config (inventory, SSH key, vault, roles_path)
├── inventory/
│   ├── hosts.yml                # Host inventory and group definitions
│   └── group_vars/
│       ├── all/vars.yml         # Global variables (glances, SSH pubkey)
│       ├── GitLab_runners/
│       │   ├── vars.yml         # Runner config (URL, tags, concurrency)
│       │   └── vault.yml        # Encrypted GitLab API token
│       └── pve99_containers/
│           ├── vars.yml         # Grafana OIDC, Authentik config
│           └── vault.yml        # Encrypted OIDC secrets
├── playbooks/                   # Thin orchestrators that compose roles
├── roles/
│   ├── lxc/                     # LXC provisioning, lifecycle, community scripts
│   ├── docker/                  # Docker CE install + TCP socket config
│   ├── gitlab_runner/           # GitLab Runner install + registration
│   ├── glances/                 # Glances monitoring install
│   ├── grafana/                 # Grafana install + OIDC via Authentik
│   └── prometheus/              # Prometheus config via git repo
├── validate.sh                  # Syntax check + validation runner
└── validation-checklist.md      # Manual test tracking (gitignored)
```

## Roles

| Role | Purpose | Key tasks |
|------|---------|-----------|
| `lxc` | LXC container lifecycle | `main.yml` (provision/reconcile), `delete.yml`, `start_stopped.yml`, `stop_restored.yml`, `community_scripts_update.yml` |
| `docker` | Docker CE installation | `main.yml` (install), `tcp.yml` (TCP socket config) |
| `gitlab_runner` | GitLab Runner | Install, register via API (glrt- token workflow) |
| `glances` | Glances monitoring | Install into virtualenv with systemd service |
| `grafana` | Grafana configuration | Install + OIDC/Authentik via systemd drop-in + env file |
| `prometheus` | Prometheus configuration | Deploy key, git clone config repo, restart service |

## Inventory

### Infrastructure Hosts

| Group | Hosts | Connection |
|-------|-------|------------|
| `ProxmoxVirtualEnvironments` | pve01, pve02, pve82, pve99 | SSH |
| `ProxmoxBackupServers` | ProxmoxBackupServer | SSH |
| `pve01_containers` | netRicks, netRicks-tools | `proxmox_pct_remote` |
| `pve99_containers` | grafana, prometheus | `proxmox_pct_remote` |
| `GitLab_runners` | gitlab-runner-01, -02, -82, -99 | `proxmox_pct_remote` |

### Capability Groups

Playbooks target these groups to scope operations:

| Group | Members | Used by |
|-------|---------|---------|
| `ssh_capable` | PVE nodes, PBS | `bootstrap_ansible.yml` |
| `apt_capable` | PVE, PBS, runners, plex | `apt_upgrade.yml` |
| `docker_capable` | GitLab runners | `configure_docker_tcp.yml` |
| `glances_capable` | PVE nodes, PBS | `install_glances.yml` |
| `ubuntu_servers` | plex servers | `do_release_upgrade.yml` |
| `communityScriptUpdate_capable` | plex servers | `update_community_scipts.yml` |

## Playbooks

### System Management

| Playbook | Description | Usage |
|----------|-------------|-------|
| `apt_upgrade.yml` | APT update, dist-upgrade, autoremove, conditional reboot | `ansible-playbook playbooks/apt_upgrade.yml` |
| `do_release_upgrade.yml` | Ubuntu LTS release upgrade (one hop at a time) | `ansible-playbook playbooks/do_release_upgrade.yml` |
| `install_glances.yml` | Install Glances monitoring (glances role) | `ansible-playbook playbooks/install_glances.yml` |
| `bootstrap_ansible.yml` | Create `ansible` service account (run once per host) | `ansible-playbook playbooks/bootstrap_ansible.yml --ask-pass` |

### GitLab Runners

| Playbook | Description | Usage |
|----------|-------------|-------|
| `setup_gitlab_runners.yml` | Full pipeline: provision LXC → Docker → Runner → TCP | `ansible-playbook playbooks/setup_gitlab_runners.yml --limit gitlab-runner-82` |
| `provision_gitlab_runner_lxc.yml` | Create Debian LXC for a runner (lxc role) | `ansible-playbook playbooks/provision_gitlab_runner_lxc.yml --limit gitlab-runner-82` |
| `deploy_gitlab_runner.yml` | Install Docker + register runner (docker + gitlab_runner roles) | `ansible-playbook playbooks/deploy_gitlab_runner.yml` |
| `configure_docker_tcp.yml` | Enable Docker TCP socket (docker role) | `ansible-playbook playbooks/configure_docker_tcp.yml` |

### LXC Lifecycle

| Playbook | Description | Usage |
|----------|-------------|-------|
| `provision_lxc.yml` | Generic LXC provisioner (lxc role) | `ansible-playbook playbooks/provision_lxc.yml -e lxc_vmid=110 -e lxc_hostname=mycontainer --limit pve01` |
| `lxc_start_stopped.yml` | Start stopped LXCs | `ansible-playbook playbooks/lxc_start_stopped.yml` |
| `lxc_stop_restored.yml` | Restore LXCs to stopped state | `ansible-playbook playbooks/lxc_stop_restored.yml` |
| `delete_lxc.yml` | **Destructive** — destroy an LXC container | `ansible-playbook playbooks/delete_lxc.yml -e target_host=gitlab-runner-82` |
| `delete_gitlab_runner.yml` | **Destructive** — unregister runner + destroy LXC | `ansible-playbook playbooks/delete_gitlab_runner.yml -e target_host=gitlab-runner-82` |

### Application Configuration

| Playbook | Description | Usage |
|----------|-------------|-------|
| `configure_grafana.yml` | Grafana install + OIDC via Authentik (grafana role) | `ansible-playbook playbooks/configure_grafana.yml` |
| `configure_prometheus.yml` | Prometheus config via git + deploy key | `ansible-playbook playbooks/configure_prometheus.yml` |
| `update_community_scipts.yml` | Run Proxmox community script updates | `ansible-playbook playbooks/update_community_scipts.yml` |

### Common Options

```bash
# Limit to specific host(s)
ansible-playbook playbooks/apt_upgrade.yml --limit pve01

# Rolling updates (one host at a time)
ansible-playbook playbooks/apt_upgrade.yml -e batch_size=1

# Skip reboots
ansible-playbook playbooks/apt_upgrade.yml --skip-tags reboot

# Dry run
ansible-playbook playbooks/apt_upgrade.yml --check
```

## Lessons Learned

See [LESSONS_LEARNED.md](LESSONS_LEARNED.md) for gotchas and insights from building and validating these playbooks against a production Proxmox cluster.

## Design Patterns

### Role-Based Organization
Reusable logic lives in `roles/` with standard Ansible structure (tasks, handlers, defaults, files, vars). Playbooks are thin orchestrators that compose roles and set host/var context.

### LXC Start/Stop Lifecycle
Playbooks that target LXC containers use pre/post tasks to ensure containers are running during execution and restored to their original state afterward. The `was_stopped` fact tracks the original state. These tasks live at `roles/lxc/tasks/start_stopped.yml` and `stop_restored.yml`.

### Delegation to PVE Nodes
Container management commands (`pct`) delegate to the PVE node hosting the container. A single `--limit gitlab-runner-82` covers both PVE-side provisioning and in-container configuration.

### Non-Interactive Community Scripts
LXC provisioning uses a `silent-whiptail` wrapper deployed to the PVE node, intercepting interactive dialogs. Environment variables control all configuration choices.

### Idempotent Provisioning
Container provisioning has two phases — **CREATE** (if container doesn't exist) and **UPDATE** (reconcile resources if it does). Safe to re-run.

## Development Workflow

### Validation

A `validation-checklist.md` (gitignored) tracks manual playbook testing. Git hooks enforce quality:

| Hook | Trigger | Action |
|------|---------|--------|
| **pre-commit** | Every commit | Runs `--syntax-check` on all playbooks. Resets checklist if `playbooks/` or `roles/` files are staged. |
| **pre-push** | Every push | Blocks push if checklist has unchecked items. |

```bash
# Quick syntax validation (no live runs)
./validate.sh

# Interactive validation — runs each playbook, prompts for human verification,
# and checks off items in validation-checklist.md as you confirm them
./validate.sh --run

# Bypass push gate (use sparingly)
git push --no-verify
```

### Adding a New Role or Playbook

1. Create the role under `roles/<name>/` with `tasks/main.yml` (and optionally `handlers/`, `defaults/`, `vars/`, `files/`)
2. Create a thin playbook in `playbooks/` that uses the role
3. Add a usage comment header (see existing playbooks for format)
4. Add an entry to `validation-checklist.md`
5. Test and check off the item
6. Update this README

### Secrets

Secrets are stored in `vault.yml` files (encrypted with Ansible Vault). The vault password is read from `.vault_pass` (gitignored).

```bash
# Edit vault
ansible-vault edit inventory/group_vars/GitLab_runners/vault.yml

# Run playbooks needing vault (if no .vault_pass file)
ansible-playbook playbooks/deploy_gitlab_runner.yml --ask-vault-pass
```
