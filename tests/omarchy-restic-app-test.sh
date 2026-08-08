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

expect_failure_contains() {
  local description="$1"
  local expected_text="$2"
  shift 2
  local output
  local status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "$description: comando deveria falhar"
  grep -Fq -- "$expected_text" <<<"$output" || fail "$description: texto ausente: $expected_text"
}

output="$TEST_ROOT/help.txt"
set +e
bash "$ROOT_DIR/omarchy-restic-app-test" --help >"$output" 2>&1
status=$?
set -e

assert_status 0 "$status" '--help'
assert_contains "$output" 'capture' 'ajuda lista capture'

catalog="$TEST_ROOT/catalog.conf"
printf '%s\n' \
  '# id|name|command|preserve_home|installation_paths|launcher_paths|installer_path|restore_mode' \
  'fixture-one|Fixture One||$HOME/.config/fixture-one;$HOME/.local/share/fixture-one|$HOME/.local/share/fixture-one/bin/fixture-one|$HOME/.local/share/applications/fixture-one.desktop|none|home' \
  'fixture-two|Fixture Two||$HOME/.config/fixture-two;$HOME/.local/share/fixture-two|$HOME/.local/share/fixture-two/bin/fixture-two|$HOME/.local/share/applications/fixture-two.desktop|none|home' \
  'fixture-three|Fixture Three||$HOME/.config/fixture-three;$HOME/.local/share/fixture-three|$HOME/.local/share/fixture-three/bin/fixture-three|$HOME/.local/share/applications/fixture-three.desktop|none|home' \
  >"$catalog"

expect_failure_contains \
  'quantidade de aplicativos' \
  'exatamente três' \
  bash "$ROOT_DIR/omarchy-restic-app-test" capture --catalog "$catalog" --app fixture-one --app fixture-two

expect_failure_contains \
  'IDs duplicados' \
  'duplicado' \
  bash "$ROOT_DIR/omarchy-restic-app-test" capture --catalog "$catalog" --app fixture-one --app fixture-one --app fixture-three

expect_failure_contains \
  'aplicativo desconhecido' \
  'não encontrado' \
  bash "$ROOT_DIR/omarchy-restic-app-test" capture --catalog "$catalog" --app fixture-one --app fixture-two --app missing

outside_catalog="$TEST_ROOT/outside-catalog.conf"
printf '%s\n' \
  'fixture-one|Fixture One||/tmp/unsafe-preserve|$HOME/.local/share/fixture-one/bin/fixture-one||none|home' \
  'fixture-two|Fixture Two||$HOME/.config/fixture-two|$HOME/.local/share/fixture-two/bin/fixture-two||none|home' \
  'fixture-three|Fixture Three||$HOME/.config/fixture-three|$HOME/.local/share/fixture-three/bin/fixture-three||none|home' \
  >"$outside_catalog"

expect_failure_contains \
  'caminho fora do HOME' \
  'fora do HOME' \
  bash "$ROOT_DIR/omarchy-restic-app-test" capture --catalog "$outside_catalog" --app fixture-one --app fixture-two --app fixture-three

printf 'PASS: harness inicial\n'
