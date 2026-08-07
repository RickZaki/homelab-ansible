# Proxmox Ansible Automation

Ansible playbooks for managing a Proxmox VE cluster — LXC container provisioning, GitLab Runner deployment, system updates, and monitoring.

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
├── ansible.cfg                  # Ansible config (inventory, SSH key, vault)
├── inventory/
│   ├── hosts.yml                # Host inventory and group definitions
│   └── group_vars/
│       ├── all/vars.yml         # Global variables (glances, SSH pubkey)
│       └── GitLab_runners/
│           ├── vars.yml         # Runner config (URL, tags, concurrency)
│           └── vault.yml        # Encrypted GitLab API token
├── playbooks/                   # Runnable playbooks
├── tasks/                       # Reusable task files (included by playbooks)
├── handlers/                    # Service restart handlers
├── files/                       # Static files deployed to hosts
├── validate.sh                  # Syntax check + validation runner
└── validation-checklist.md      # Manual test tracking (gitignored)
```

## Inventory

### Infrastructure Hosts

| Group | Hosts | Connection |
|-------|-------|------------|
| `ProxmoxVirtualEnvironments` | pve01, pve02, pve82, pve99 | SSH |
| `ProxmoxBackupServers` | ProxmoxBackupServer | SSH |
| `pve01_containers` | netRicks, netRicks-tools | `proxmox_pct_remote` |
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
| `install_glances.yml` | Install Glances monitoring with web UI | `ansible-playbook playbooks/install_glances.yml` |
| `bootstrap_ansible.yml` | Create `ansible` service account (run once per host) | `ansible-playbook playbooks/bootstrap_ansible.yml --ask-pass` |

### GitLab Runners

| Playbook | Description | Usage |
|----------|-------------|-------|
| `setup_gitlab_runners.yml` | Full pipeline: provision LXC → Docker → Runner → TCP | `ansible-playbook playbooks/setup_gitlab_runners.yml --limit gitlab-runner-82` |
| `provision_gitlab_runner_lxc.yml` | Create Debian LXC for a runner | `ansible-playbook playbooks/provision_gitlab_runner_lxc.yml --limit gitlab-runner-82` |
| `deploy_gitlab_runner.yml` | Install Docker + register GitLab Runner | `ansible-playbook playbooks/deploy_gitlab_runner.yml` |
| `configure_docker_tcp.yml` | Enable Docker TCP socket | `ansible-playbook playbooks/configure_docker_tcp.yml` |

### LXC Lifecycle

| Playbook | Description | Usage |
|----------|-------------|-------|
| `provision_lxc.yml` | Generic LXC provisioner (community scripts) | `ansible-playbook playbooks/provision_lxc.yml -e lxc_vmid=110 -e lxc_hostname=mycontainer --limit pve01` |
| `lxc_start_stopped.yml` | Start stopped LXCs | `ansible-playbook playbooks/lxc_start_stopped.yml` |
| `lxc_stop_restored.yml` | Restore LXCs to stopped state | `ansible-playbook playbooks/lxc_stop_restored.yml` |
| `delete_lxc.yml` | **Destructive** — destroy an LXC container | `ansible-playbook playbooks/delete_lxc.yml -e target_host=gitlab-runner-82` |
| `delete_gitlab_runner.yml` | **Destructive** — unregister runner from GitLab and destroy LXC | `ansible-playbook playbooks/delete_gitlab_runner.yml -e target_host=gitlab-runner-82` |

### Application Updates

| Playbook | Description | Usage |
|----------|-------------|-------|
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

## Shared Tasks

Reusable task files included by multiple playbooks via `include_tasks`:

| Task | Purpose | Used by |
|------|---------|---------|
| `tasks/lxc_start_stopped.yml` | Start stopped LXCs, record original state | `apt_upgrade`, `deploy_gitlab_runner`, `do_release_upgrade` |
| `tasks/lxc_stop_restored.yml` | Restore LXCs to original stopped state | Same as above (post-task) |
| `tasks/provision_lxc.yml` | Create or reconcile LXC containers | `provision_lxc`, `provision_gitlab_runner_lxc` |
| `tasks/community_scripts_update.yml` | Run community script update command | `update_community_scipts` |

## Design Patterns

### LXC Start/Stop Lifecycle
Playbooks that target LXC containers use pre/post tasks to ensure containers are running during execution and restored to their original state afterward. The `was_stopped` fact tracks the original state.

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
| **pre-commit** | Every commit | Runs `--syntax-check` on all playbooks. Resets checklist if `playbooks/` or `tasks/` files are staged. |
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

The interactive validator runs playbooks in dependency order (e.g., `setup_gitlab_runners` before `delete_gitlab_runner`), shows output, then asks the operator to confirm the result before marking it verified. Sub-playbooks called by an orchestrator (like `setup_gitlab_runners.yml`) are confirmed together after the parent runs.

### Adding a New Playbook

1. Create the playbook in `playbooks/`
2. Add a usage comment header (see existing playbooks for format)
3. Add an entry to `validation-checklist.md`
4. Test and check off the item
5. Update this README's playbook table

### Secrets

GitLab API tokens are stored in `inventory/group_vars/GitLab_runners/vault.yml` (encrypted with Ansible Vault). The vault password is read from `.vault_pass` (gitignored).

```bash
# Edit vault
ansible-vault edit inventory/group_vars/GitLab_runners/vault.yml

# Run playbooks needing vault (if no .vault_pass file)
ansible-playbook playbooks/deploy_gitlab_runner.yml --ask-vault-pass
```
