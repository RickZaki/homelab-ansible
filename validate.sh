#!/usr/bin/env bash
# validate.sh — Playbook validation with auto and human-verified modes.
#
# Runs each playbook in dependency order and updates validation-checklist.md.
# Auto-verified playbooks pass on clean exit code (prompt only on failure).
# Human-verified playbooks always prompt the operator to confirm external state.
#
# Usage:
#   ./validate.sh              # syntax-check only (fast, safe)
#   ./validate.sh --run        # interactive: run + human verify + checklist update

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
FAILED_LIST=()
CHECKLIST="validation-checklist.md"
TEST_HOST="gitlab-runner-82"

run_mode="${1:-}"

log_pass() { echo -e "  ${GREEN}PASS${NC}  $1"; ((PASS++)) || true; }
log_fail() { echo -e "  ${RED}FAIL${NC}  $1"; ((FAIL++)) || true; FAILED_LIST+=("$1"); }
log_skip() { echo -e "  ${YELLOW}SKIP${NC}  $1 — $2"; ((SKIP++)) || true; }

# ── Checklist helpers ─────────────────────────────────────────────────────────

# Mark a checklist line as [x] by matching a unique substring of the command.
# Uses the full command string to match the correct line.
check_off() {
  local pattern="$1"
  if [[ -f "$CHECKLIST" ]]; then
    sed -i '' "s|^\([ ]*\)- \[ \] \(.*${pattern}.*\)$|\1- [x] \2|" "$CHECKLIST"
  fi
}

# ── Interactive confirmation ──────────────────────────────────────────────────

# Ask the operator to verify the result. Returns 0 if confirmed, 1 if not.
confirm() {
  local prompt="${1:-Verified?}"
  while true; do
    echo -en "  ${CYAN}${prompt} [y/n]: ${NC}"
    read -r answer
    case "$answer" in
      [yY]) return 0 ;;
      [nN]) return 1 ;;
      *) echo "  Please answer y or n." ;;
    esac
  done
}

# ── Run helpers ──────────────────────────────────────────────────────────────

# Run a playbook and capture output. Sets RUN_OUTPUT and RUN_OK.
_run_playbook() {
  local playbook="$1"
  shift

  echo ""
  echo -e "  ${CYAN}Running: ansible-playbook $playbook $*${NC}"
  echo ""

  RUN_OUTPUT=$(ansible-playbook "$playbook" "$@" 2>&1) || true
  echo "$RUN_OUTPUT"

  # Check for failures
  if echo "$RUN_OUTPUT" | grep -qE 'failed=[1-9]|unreachable=[1-9]'; then
    RUN_OK=false
  else
    RUN_OK=true
  fi
}

# Auto-verified: run playbook, auto-pass on success, prompt only on failure.
# Args: <checklist_pattern> <playbook> [extra ansible args...]
run_auto() {
  local pattern="$1"
  local playbook="$2"
  shift 2

  if [[ ! -f "$playbook" ]]; then
    log_skip "$playbook" "file not found"
    return
  fi

  _run_playbook "$playbook" "$@"

  if $RUN_OK; then
    log_pass "$playbook"
    check_off "$pattern"
  else
    echo ""
    if confirm "Playbook reported errors. Mark as verified anyway?"; then
      log_pass "$playbook (operator override)"
      check_off "$pattern"
    else
      log_fail "$playbook"
    fi
  fi
}

# Human-verified: run playbook, always prompt operator to confirm.
# Args: <verify_hint> <checklist_pattern> <playbook> [extra ansible args...]
run_verify() {
  local hint="$1"
  local pattern="$2"
  local playbook="$3"
  shift 3

  if [[ ! -f "$playbook" ]]; then
    log_skip "$playbook" "file not found"
    return
  fi

  _run_playbook "$playbook" "$@"

  echo ""
  if ! $RUN_OK; then
    echo -e "  ${RED}Playbook reported errors.${NC}"
  fi
  echo -e "  ${YELLOW}Verify: ${hint}${NC}"
  if confirm "Verified correct?"; then
    log_pass "$playbook"
    check_off "$pattern"
  else
    log_fail "$playbook (operator rejected)"
  fi
}

# ── Phase 1: Syntax check all playbooks ───────────────────────────────────────
echo ""
echo "=== Phase 1: Syntax check ==="
echo ""

for playbook in playbooks/*.yml; do
  EXTRA_ARGS=()
  [[ "$playbook" == *"delete_"* ]] && EXTRA_ARGS=(-e target_host=syntax_check)
  if ansible-playbook "$playbook" "${EXTRA_ARGS[@]}" --syntax-check > /dev/null 2>&1; then
    log_pass "$playbook (syntax)"
  else
    log_fail "$playbook (syntax)"
  fi
done

if [[ "$run_mode" != "--run" ]]; then
  echo ""
  echo "=== Summary (syntax only) ==="
  echo -e "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Skipped: $SKIP${NC}"
  if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo -e "\n  ${RED}Failures:${NC}"
    for f in "${FAILED_LIST[@]}"; do echo "    - $f"; done
  fi
  echo ""
  echo "Run with --run to execute interactive validation."
  exit $FAIL
fi

# ── Phase 2: Interactive live validation ──────────────────────────────────────
# Order matters: provision before deploy, deploy before delete, etc.

# Reset checklist before starting
if [[ -f "$CHECKLIST" ]]; then
  sed -i '' 's/- \[x\]/- [ ]/g' "$CHECKLIST"
fi

echo ""
echo "=== Phase 2: Interactive validation ==="
echo "Each playbook will run, then you'll be asked to verify the result."
echo ""

# --- System management (auto-verified) ---
echo -e "\n${YELLOW}── System Management (auto-verified) ──${NC}"

run_auto "apt_upgrade" \
  "playbooks/apt_upgrade.yml"

run_auto "install_glances" \
  "playbooks/install_glances.yml"

run_auto "do_release_upgrade" \
  "playbooks/do_release_upgrade.yml"

run_auto "update_community_scipts" \
  "playbooks/update_community_scipts.yml"

# --- GitLab Runner lifecycle (human-verified, order: delete → setup → verify) ---
echo -e "\n${YELLOW}── GitLab Runner Lifecycle — ${TEST_HOST} (human-verified) ──${NC}"

# Tear down first so setup is tested from scratch
run_verify "Confirm runner is removed from GitLab UI" \
  "delete_gitlab_runner" \
  "playbooks/delete_gitlab_runner.yml" -e "target_host=$TEST_HOST"

run_verify "Confirm LXC is gone from Proxmox" \
  "delete_lxc" \
  "playbooks/delete_lxc.yml" -e "target_host=$TEST_HOST"

# Build from scratch
run_verify "Confirm runner LXC exists in Proxmox and runner is registered in GitLab UI" \
  "setup_gitlab_runners" \
  "playbooks/setup_gitlab_runners.yml" --limit "$TEST_HOST"

# Sub-playbooks validated by setup above — ask operator to confirm
echo ""
echo -e "  ${CYAN}setup_gitlab_runners.yml calls these sub-playbooks:${NC}"
echo -e "  ${CYAN}  - provision_gitlab_runner_lxc.yml${NC}"
echo -e "  ${CYAN}  - deploy_gitlab_runner.yml${NC}"
echo -e "  ${CYAN}  - configure_docker_tcp.yml${NC}"
if confirm "Were provision, deploy, and configure sub-playbooks also verified?"; then
  check_off "provision_gitlab_runner_lxc"
  check_off "deploy_gitlab_runner"
  check_off "configure_docker_tcp"
  log_pass "sub-playbooks (provision + deploy + configure)"
else
  log_fail "sub-playbooks (operator rejected)"
fi

# --- Bootstrap (interactive, can't automate) ---
echo -e "\n${YELLOW}── Manual ──${NC}"
log_skip "playbooks/bootstrap_ansible.yml" "requires --ask-pass (run manually)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Final Summary ==="
echo -e "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Skipped: $SKIP${NC}"
if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
  echo -e "\n  ${RED}Failures:${NC}"
  for f in "${FAILED_LIST[@]}"; do echo "    - $f"; done
fi
echo ""

if [[ -f "$CHECKLIST" ]]; then
  REMAINING=$(grep -c '^\s*- \[ \]' "$CHECKLIST" || true)
  if [[ $REMAINING -gt 0 ]]; then
    echo -e "${YELLOW}$REMAINING checklist items still unchecked.${NC}"
  else
    echo -e "${GREEN}All checklist items verified!${NC}"
  fi
fi
echo ""
exit $FAIL
