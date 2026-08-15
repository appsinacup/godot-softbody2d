#!/usr/bin/env bash
# Format + lint the GDScript tree (gdtoolkit: gdformat/gdlint, config .gdlintrc).
#
#   ./lint.sh            format in place, then lint
#   ./lint.sh --check    CI mode: fail if formatting would change anything, then lint
#
# Exit code: non-zero if formatting failed/would change files, or if gdlint reports
# any finding. There is no accepted backlog: fix the finding, never loosen the rule.
set -uo pipefail
cd "$(dirname "$0")"

PATHS=(addons/softbody2d tests demos)
LINE_LENGTH=120

MODE="format"
if [ "${1:-}" = "--check" ]; then
	MODE="check"
fi

for tool in gdformat gdlint; do
	if ! command -v "$tool" > /dev/null; then
		echo "error: $tool not found (pip install 'gdtoolkit==4.*')" >&2
		exit 1
	fi
done

echo "== gdformat ($MODE, -l $LINE_LENGTH) =="
if [ "$MODE" = "check" ]; then
	gdformat --check -l "$LINE_LENGTH" "${PATHS[@]}" || { echo "FORMAT: files need formatting (run ./lint.sh)"; exit 1; }
else
	gdformat -l "$LINE_LENGTH" "${PATHS[@]}" || { echo "FORMAT: gdformat failed"; exit 1; }
fi

echo "== gdlint =="
lint_output="$(gdlint "${PATHS[@]}" 2>&1)"
lint_status=$?
if [ "$lint_status" -ne 0 ]; then
	printf '%s\n' "$lint_output"
	echo "LINT: findings above — fix them"
	exit 1
fi
echo "LINT: OK"
