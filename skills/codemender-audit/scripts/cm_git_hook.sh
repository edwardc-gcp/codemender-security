#!/usr/bin/env bash
# Opt-in git hook that scans your changes with CodeMender diff mode before they leave your machine.
#
# Usage: cm_git_hook.sh install [--pre-push] [--fail-on SEVERITIES]
#        cm_git_hook.sh uninstall
#        cm_git_hook.sh status
#        cm_git_hook.sh run pre-commit|pre-push [--fail-on SEVERITIES]   (called by the installed hook)
#
#   install     add a pre-commit hook that scans the staged changes (cm_diff_scan.sh --scope staged), or with
#               --pre-push a pre-push hook that scans the branch being pushed (--scope branch)
#   --fail-on   severities that block (default CRITICAL,HIGH; an empty value only reports)
#   uninstall   remove the hooks that this script installed, and the copied scripts
#
# The hook runs copies of cm_git_hook.sh, cm_diff_scan.sh, and cm_exec.sh from <git dir>/codemender/, so it keeps
# working when the plugin moves or updates (run install again to refresh them). It never overwrites a hook that it
# didn't install, and when core.hooksPath is set (husky or a shared hooks directory) it prints the line to add instead.
# A pre-commit hook reuses the result of `cm_diff_scan.sh --scope staged` when HEAD and the staged content are unchanged.
# Skip the scan once with --no-verify or CM_SKIP_HOOK=1. When the scan can't run (no cm, credentials, or network), the
# hook warns and doesn't block unless CM_HOOK_STRICT=1. Anyone can skip a local hook, so keep a CI gate as well.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="# codemender-security managed hook"
DEFAULT_FAIL_ON="CRITICAL,HIGH"
RUNNER_FILES=(cm_git_hook.sh cm_diff_scan.sh cm_exec.sh)

usage() { sed -n '2,19p' "$0" | sed -E 's/^# ?//'; }
die() { echo "❌ $*" >&2; exit 2; }

require_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository."
}

# The line that runs the hook; resolved at run time, so it survives moving the repository.
run_line() {
  printf 'bash "$(git rev-parse --git-common-dir)/codemender/cm_git_hook.sh" run %s --fail-on "%s"' "$1" "$2"
}

install_hook() {
  local hook="pre-commit" fail_on="${DEFAULT_FAIL_ON}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --pre-push) hook="pre-push"; shift ;;
      --fail-on) fail_on="${2-}"; shift 2 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
  case "${fail_on}" in
    *[!A-Za-z,]*) die "--fail-on takes comma-separated severities, such as CRITICAL,HIGH." ;;
  esac
  require_repo
  local f
  for f in "${RUNNER_FILES[@]}"; do
    [ -f "${SCRIPT_DIR}/${f}" ] || die "Missing ${SCRIPT_DIR}/${f}."
  done

  # Copy the runner into the repository's private git directory (never into a shared hooks directory).
  local runner_dir
  runner_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)/codemender"
  mkdir -p "${runner_dir}" || die "Cannot create ${runner_dir}."
  for f in "${RUNNER_FILES[@]}"; do
    cp "${SCRIPT_DIR}/${f}" "${runner_dir}/${f}" && chmod +x "${runner_dir}/${f}" || die "Cannot copy ${f} to ${runner_dir}."
  done
  echo "✅ Copied the hook runner to ${runner_dir}/ (run install again after updating the plugin)."

  local line verb="commit"
  line="$(run_line "${hook}" "${fail_on}")"
  [ "${hook}" = "pre-push" ] && verb="push"

  local hooks_path
  hooks_path="$(git config --get core.hooksPath || true)"
  if [ -n "${hooks_path}" ]; then
    echo "ℹ️  core.hooksPath is set (${hooks_path}), so another tool manages the hooks and no hook file was written."
    echo "   Add this line to your ${hook} hook:"
    echo
    echo "    ${line} || exit 1"
    return 0
  fi

  local hooks_dir hook_file
  hooks_dir="$(git rev-parse --git-path hooks)"
  mkdir -p "${hooks_dir}" || die "Cannot create ${hooks_dir}."
  hook_file="$(cd "${hooks_dir}" && pwd)/${hook}"
  if [ -e "${hook_file}" ] && ! grep -qF "${MARKER}" "${hook_file}"; then
    echo "ℹ️  ${hook_file} already exists and wasn't installed by this plugin, so it was left unchanged."
    echo "   To add the CodeMender scan, add this line to it:"
    echo
    echo "    ${line} || exit 1"
    return 0
  fi
  {
    echo "#!/bin/sh"
    echo "${MARKER}"
    echo "# Scans your changes with CodeMender diff mode before each ${verb} (installed by cm_git_hook.sh)."
    echo "# Skip once: git ${verb} --no-verify, or CM_SKIP_HOOK=1. Remove: bash \"${runner_dir}/cm_git_hook.sh\" uninstall"
    echo "exec ${line}"
  } > "${hook_file}" && chmod +x "${hook_file}" || die "Cannot write ${hook_file}."
  echo "✅ Installed the CodeMender ${hook} hook: ${hook_file}"
  echo "   Each ${verb} with source changes now runs a diff scan (usually 1 to 6 minutes, and it uses tokens)."
  if [ "${hook}" = "pre-commit" ]; then
    echo "   Run cm_diff_scan.sh --scope staged before committing, and the hook reuses that result."
  fi
  echo "   Skip once with: git ${verb} --no-verify (or CM_SKIP_HOOK=1)."
}

uninstall_hook() {
  require_repo
  local hooks_dir hook file common_dir f
  hooks_dir="$(git rev-parse --git-path hooks)"
  for hook in pre-commit pre-push; do
    file="${hooks_dir}/${hook}"
    [ -f "${file}" ] || continue
    if grep -qF "${MARKER}" "${file}"; then
      rm -f "${file}" && echo "✅ Removed ${file}"
    elif grep -qF "codemender/cm_git_hook.sh" "${file}"; then
      echo "ℹ️  ${file} calls the CodeMender hook runner: remove that line yourself."
    fi
  done
  common_dir="$(git rev-parse --git-common-dir)"
  if [ -d "${common_dir}/codemender" ]; then
    for f in "${RUNNER_FILES[@]}"; do
      rm -f "${common_dir}/codemender/${f}"
    done
    rmdir "${common_dir}/codemender" 2>/dev/null || true
    echo "✅ Removed the hook runner from ${common_dir}/codemender/"
  fi
}

status_hook() {
  require_repo
  local hooks_dir hook file common_dir hooks_path
  hooks_dir="$(git rev-parse --git-path hooks)"
  hooks_path="$(git config --get core.hooksPath || true)"
  [ -n "${hooks_path}" ] && echo "ℹ️  core.hooksPath: ${hooks_path}"
  for hook in pre-commit pre-push; do
    file="${hooks_dir}/${hook}"
    if [ -f "${file}" ] && grep -qF "${MARKER}" "${file}"; then
      echo "${hook}: installed ($(sed -nE 's/.*run [a-z-]+ --fail-on "([^"]*)".*/fail on: \1/p' "${file}" | head -n 1))"
    elif [ -f "${file}" ] && grep -qF "codemender/cm_git_hook.sh" "${file}"; then
      echo "${hook}: called from your own hook (${file})"
    else
      echo "${hook}: not installed"
    fi
  done
  common_dir="$(git rev-parse --git-common-dir)"
  if [ -f "${common_dir}/codemender/cm_git_hook.sh" ]; then
    echo "runner: ${common_dir}/codemender/"
  else
    echo "runner: not installed"
  fi
}

# Reuses the last `cm_diff_scan.sh --scope staged` result when it covered the whole repository with the same HEAD,
# staged tree, and --fail-on. Sets REUSED_RC to that scan's exit code (0 or 1).
REUSED_RC=""
reuse_staged_result() {
  local root meta tree head
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  meta="${root}/.codemender/last-diff-scan.meta"
  [ -f "${meta}" ] || return 1
  tree="$(git write-tree 2>/dev/null)" || return 1
  head="$(git rev-parse HEAD 2>/dev/null)" || return 1
  grep -qxF "scope=staged" "${meta}" && grep -qxF "path=." "${meta}" && grep -qxF "head=${head}" "${meta}" \
    && grep -qxF "tree=${tree}" "${meta}" && grep -qxF "fail_on=$1" "${meta}" || return 1
  REUSED_RC="$(sed -n 's/^exit_code=//p' "${meta}" | head -n 1)"
  case "${REUSED_RC}" in
    0|1) return 0 ;;
  esac
  return 1
}

# Scans the branch being pushed. git passes "<local ref> <local sha> <remote ref> <remote sha>" lines on stdin.
scan_push() {
  local fail_on="$1" head local_ref local_sha remote_ref remote_sha rc=0 refs=0 scanned=false
  head="$(git rev-parse HEAD 2>/dev/null || true)"
  if ! git diff --quiet HEAD 2>/dev/null; then
    echo "ℹ️  CodeMender pre-push: the scan also covers your uncommitted changes (diff mode compares with the working tree)."
  fi
  if [ ! -t 0 ]; then
    while read -r local_ref local_sha remote_ref remote_sha; do
      [ -n "${local_sha:-}" ] || continue
      refs=$((refs + 1))
      case "${local_sha}" in
        *[!0]*) ;;
        *) continue ;; # deleting a remote branch
      esac
      if [ "${local_sha}" != "${head}" ]; then
        echo "ℹ️  CodeMender pre-push: ${local_ref} isn't checked out, so it wasn't scanned."
        continue
      fi
      [ "${scanned}" = true ] && continue
      scanned=true
      local base_args=()
      case "${remote_sha:-0}" in
        *[!0]*) git cat-file -e "${remote_sha}^{commit}" 2>/dev/null && base_args=(--base "${remote_sha}") ;;
      esac
      bash "${SCRIPT_DIR}/cm_diff_scan.sh" --scope branch ${base_args[@]+"${base_args[@]}"} --fail-on "${fail_on}" || rc=$?
    done
  fi
  if [ "${refs}" -eq 0 ]; then
    # No ref list (for example, another hook already read stdin): scan the branch against its upstream.
    bash "${SCRIPT_DIR}/cm_diff_scan.sh" --scope branch --fail-on "${fail_on}" || rc=$?
  fi
  return "${rc}"
}

# Called when the scan can't run: warn and let the commit through, unless CM_HOOK_STRICT=1.
cannot_scan() {
  if [ "${CM_HOOK_STRICT:-}" = "1" ]; then
    echo "❌ CodeMender ${1} hook: ${2}. Blocking because CM_HOOK_STRICT=1 (skip once with --no-verify)." >&2
    return 1
  fi
  echo "⚠️  CodeMender ${1} hook: ${2}. Not blocking (set CM_HOOK_STRICT=1 to block instead)." >&2
  return 0
}

run_hook() {
  local hook="${1:-}" fail_on="${DEFAULT_FAIL_ON}" verb rc=0
  [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --fail-on) fail_on="${2-}"; shift 2 ;;
      *) shift ;; # git passes extra arguments to some hooks (pre-push: remote name and URL)
    esac
  done
  case "${hook}" in
    pre-commit) verb="commit" ;;
    pre-push) verb="push" ;;
    *) die "Unknown hook: ${hook:-<none>} (expected pre-commit or pre-push)." ;;
  esac
  if [ "${CM_SKIP_HOOK:-}" = "1" ]; then
    echo "ℹ️  CodeMender ${hook} scan skipped (CM_SKIP_HOOK=1)." >&2
    return 0
  fi
  if ! command -v cm >/dev/null 2>&1; then
    cannot_scan "${hook}" "'cm' is not on PATH, so the security scan didn't run"
    return $?
  fi

  if [ "${hook}" = "pre-commit" ]; then
    if reuse_staged_result "${fail_on}"; then
      if [ "${REUSED_RC}" = "0" ]; then
        echo "✅ CodeMender: these staged changes already passed a diff scan, so they weren't scanned again."
        return 0
      fi
      echo "🚨 CodeMender: a diff scan of these exact staged changes reported blocking findings (report: .codemender/last-diff-scan.json)."
      rc=1
    else
      bash "${SCRIPT_DIR}/cm_diff_scan.sh" --scope staged --fail-on "${fail_on}" || rc=$?
    fi
  else
    scan_push "${fail_on}" || rc=$?
  fi

  case "${rc}" in
    0) return 0 ;;
    1)
      echo "❌ CodeMender blocked this ${verb}: fix the findings above, or skip the scan once with --no-verify." >&2
      return 1
      ;;
    *)
      cannot_scan "${hook}" "the scan couldn't run (exit ${rc}; check with: cm health)"
      return $?
      ;;
  esac
}

case "${1:-}" in
  install) shift; install_hook "$@" ;;
  uninstall) shift; uninstall_hook ;;
  status) shift; status_hook ;;
  run) shift; run_hook "$@"; exit $? ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
