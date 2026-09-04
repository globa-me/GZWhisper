#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

report_failure() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

report_ok() {
  echo "OK: $1"
}

tracked_build_files="$(git ls-files 'build/**' || true)"
if [[ -n "$tracked_build_files" ]]; then
  report_failure "tracked build artifacts found under build/"
  echo "$tracked_build_files" >&2
else
  report_ok "no tracked build artifacts"
fi

secret_pattern="([A-Za-z0-9_]*(api[_-]?key|secret|token|password)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]|Authorization[[:space:]]*:|Bearer[[:space:]]+[A-Za-z0-9._-]+|PRIVATE KEY|ssh-rsa|AIza|sk-[A-Za-z0-9])"
secret_hits="$(
  git grep -n -I -E "$secret_pattern" -- . \
    ':(exclude)scripts/check_repo_security.sh' \
    ':(exclude)README.md' \
    ':(exclude)docs/**' || true
)"
if [[ -n "$secret_hits" ]]; then
  report_failure "possible secrets found"
  echo "$secret_hits" >&2
else
  report_ok "no obvious secrets in tracked source files"
fi

spctl_hits_file="$(mktemp)"
if git grep -n -E 'spctl[[:space:]].*--add' -- . >"$spctl_hits_file" 2>/dev/null; then
  report_failure "Gatekeeper allow-list mutation found"
  cat "$spctl_hits_file" >&2
else
  report_ok "no Gatekeeper allow-list mutation"
fi
rm -f "$spctl_hits_file"

bash_scripts=()
while IFS= read -r path; do
  bash_scripts+=("$path")
done < <(git ls-files '*.sh' '*.command')

if ((${#bash_scripts[@]} > 0)); then
  bash -n "${bash_scripts[@]}"
  report_ok "shell scripts parse"
fi

if command -v pwsh >/dev/null 2>&1; then
  while IFS= read -r path; do
    pwsh -NoProfile -Command "\$null = [System.Management.Automation.Language.Parser]::ParseFile('$path', [ref]\$null, [ref]\$errors); if (\$errors.Count) { \$errors | ForEach-Object { Write-Error \$_.Message }; exit 1 }"
  done < <(git ls-files '*.ps1')
  report_ok "PowerShell scripts parse"
else
  echo "SKIP: PowerShell parse check (pwsh not installed)"
fi

if ((failures > 0)); then
  echo "Security check failed with $failures issue(s)." >&2
  exit 1
fi

echo "Security check passed."
