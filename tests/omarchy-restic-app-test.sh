#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-restic-app-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  [[ "$expected" == "$actual" ]] || fail "$description: esperado status $expected, recebido $actual"
}

assert_contains() {
  local file="$1"
  local text="$2"
  local description="$3"

  grep -Fq -- "$text" "$file" || fail "$description: texto ausente: $text"
}

output="$TEST_ROOT/help.txt"
set +e
bash "$ROOT_DIR/omarchy-restic-app-test" --help >"$output" 2>&1
status=$?
set -e

assert_status 0 "$status" '--help'
assert_contains "$output" 'capture' 'ajuda lista capture'
printf 'PASS: harness inicial\n'
