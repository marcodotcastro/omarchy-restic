#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-restic-backup-test.XXXXXX")"
LOCKED_PATHS=()

cleanup() {
  local path

  for path in "${LOCKED_PATHS[@]}"; do
    chmod 700 "$path" 2>/dev/null || true
  done
  chmod -R u+rwX "$TEST_ROOT" 2>/dev/null || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

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

assert_not_contains() {
  local file="$1"
  local text="$2"
  local description="$3"

  ! grep -Fq -- "$text" "$file" || fail "$description: texto indevido: $text"
}

FIXTURE_HOME="$TEST_ROOT/home"
REPOSITORY="$TEST_ROOT/backup/repository"
PASSWORD_FILE="$TEST_ROOT/password"
CACHE_DIR="$TEST_ROOT/cache"
TMP_DIR="$TEST_ROOT/tmp"

mkdir -m 700 -p \
  "$FIXTURE_HOME/project/docker/volumes/db/data" \
  "$FIXTURE_HOME/project/src" \
  "$FIXTURE_HOME/.config/c2s-crm-worktree-proxy/config/caddy" \
  "$FIXTURE_HOME/.config/c2s-crm-worktree-proxy/data/caddy" \
  "$REPOSITORY" \
  "$CACHE_DIR" \
  "$TMP_DIR"

printf 'must survive\n' >"$FIXTURE_HOME/project/src/application.rb"
printf 'database content\n' >"$FIXTURE_HOME/project/docker/volumes/db/data/pgdata"
printf 'caddy config volume\n' >"$FIXTURE_HOME/.config/c2s-crm-worktree-proxy/config/caddy/state"
printf 'caddy data volume\n' >"$FIXTURE_HOME/.config/c2s-crm-worktree-proxy/data/caddy/state"

LOCKED_PATHS+=(
  "$FIXTURE_HOME/project/docker/volumes/db/data"
  "$FIXTURE_HOME/.config/c2s-crm-worktree-proxy/config/caddy"
  "$FIXTURE_HOME/.config/c2s-crm-worktree-proxy/data/caddy"
)
chmod 000 "${LOCKED_PATHS[@]}"

printf 'test-password\n' >"$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"
RESTIC_PASSWORD_FILE="$PASSWORD_FILE" \
  RESTIC_CACHE_DIR="$CACHE_DIR" \
  restic -r "$REPOSITORY" init >/dev/null

output="$TEST_ROOT/backup-output.txt"
set +e
printf 'test-password\n' | \
  HOME="$FIXTURE_HOME" \
  USER="${USER:-$(id -un)}" \
  RESTIC_REPOSITORY="$REPOSITORY" \
  RESTIC_CACHE_DIR="$CACHE_DIR" \
  TMPDIR="$TMP_DIR" \
  DOCKER_HOST="unix:///tmp/omarchy-restic-backup-test-no-docker.sock" \
  bash "$ROOT_DIR/omarchy-restic-backup" >"$output" 2>&1
status=$?
set -e

assert_status 0 "$status" 'backup ignora volumes sem permissão'
assert_not_contains "$output" 'permission denied' 'backup não relata erro de permissão'

listing="$TEST_ROOT/listing.txt"
RESTIC_PASSWORD_FILE="$PASSWORD_FILE" \
  RESTIC_CACHE_DIR="$CACHE_DIR" \
  restic -r "$REPOSITORY" ls latest >"$listing"
assert_contains "$listing" 'application.rb' 'arquivo normal do projeto foi salvo'
assert_not_contains "$listing" 'docker/volumes/db/data' 'volume Docker do projeto ficou fora'
assert_not_contains "$listing" 'c2s-crm-worktree-proxy/config/caddy' 'volume Caddy de configuração ficou fora'
assert_not_contains "$listing" 'c2s-crm-worktree-proxy/data/caddy' 'volume Caddy de dados ficou fora'

printf 'PASS: backup exclui volumes Docker e preserva arquivos de projeto\n'
