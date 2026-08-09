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

AUTO_MOUNT="$TEST_ROOT/auto-mount"
AUTO_HOME="$TEST_ROOT/auto-home"
AUTO_CACHE_DIR="$TEST_ROOT/auto-cache"
AUTO_TMP_DIR="$TEST_ROOT/auto-tmp"
mkdir -m 700 -p "$AUTO_MOUNT" "$AUTO_HOME/project" "$AUTO_CACHE_DIR" "$AUTO_TMP_DIR"
mkdir -m 700 -p "$AUTO_HOME/RubymineProjects/c2s-crm.worktrees/c2s-crm-cc-997-erros-logs/storage"
printf 'auto-password\n' >"$TEST_ROOT/auto-password"
chmod 600 "$TEST_ROOT/auto-password"
printf 'first backup\n' >"$AUTO_HOME/project/file.txt"
printf 'temporary application state\n' >"$AUTO_HOME/RubymineProjects/c2s-crm.worktrees/c2s-crm-cc-997-erros-logs/storage/cache.db"
LOCKED_PATHS+=("$AUTO_HOME/RubymineProjects/c2s-crm.worktrees/c2s-crm-cc-997-erros-logs/storage")
chmod 000 "${LOCKED_PATHS[@]}"

run_auto_backup() {
  local output_file="$1"

  printf 'auto-password\n' | \
    HOME="$AUTO_HOME" \
    USER="${USER:-$(id -un)}" \
    OMARCHY_RESTIC_MOUNT="$AUTO_MOUNT" \
    RESTIC_CACHE_DIR="$AUTO_CACHE_DIR" \
    TMPDIR="$AUTO_TMP_DIR" \
    DOCKER_HOST="unix:///tmp/omarchy-restic-backup-test-no-docker.sock" \
    bash "$ROOT_DIR/omarchy-restic-backup" >"$output_file" 2>&1
}

AUTO_FIRST_OUTPUT="$TEST_ROOT/auto-first.txt"
set +e
run_auto_backup "$AUTO_FIRST_OUTPUT"
auto_first_status=$?
set -e
assert_status 0 "$auto_first_status" 'backup cria o repositório padrão ausente'
assert_contains "$AUTO_FIRST_OUTPUT" 'omarchy-restic-v2' 'primeiro backup usa v2'
[[ -d "$AUTO_MOUNT/omarchy-restic-v2" ]] || fail 'v2 não foi criado automaticamente'

AUTO_FIRST_LISTING="$TEST_ROOT/auto-first-listing.txt"
RESTIC_PASSWORD_FILE="$TEST_ROOT/auto-password" \
  RESTIC_CACHE_DIR="$AUTO_CACHE_DIR" \
  restic -r "$AUTO_MOUNT/omarchy-restic-v2" ls latest >"$AUTO_FIRST_LISTING"
assert_contains "$AUTO_FIRST_LISTING" 'project/file.txt' 'arquivo normal foi salvo no primeiro backup'
assert_not_contains "$AUTO_FIRST_LISTING" 'c2s-crm-cc-997-erros-logs/storage' 'storage temporário ficou fora do primeiro backup'

AUTO_SECOND_OUTPUT="$TEST_ROOT/auto-second.txt"
set +e
run_auto_backup "$AUTO_SECOND_OUTPUT"
auto_second_status=$?
set -e
assert_status 0 "$auto_second_status" 'backup cria a próxima versão quando v2 existe'
assert_contains "$AUTO_SECOND_OUTPUT" 'omarchy-restic-v3' 'segundo backup usa v3'
[[ -d "$AUTO_MOUNT/omarchy-restic-v3" ]] || fail 'v3 não foi criado automaticamente'

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
