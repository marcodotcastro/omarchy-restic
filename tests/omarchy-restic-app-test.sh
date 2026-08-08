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

PASSWORD_FILE="$TEST_ROOT/password"
REPOSITORY="$TEST_ROOT/repository"
FIXTURE_HOME="$TEST_ROOT/home"
RESTIC_CACHE_DIR="$TEST_ROOT/restic-cache"
WORKDIR="$TEST_ROOT/workdir"
mkdir -m 700 -p "$FIXTURE_HOME" "$WORKDIR" "$RESTIC_CACHE_DIR"
printf 'test-password\n' >"$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

create_fixture() {
  local app_id="$1"

  mkdir -p \
    "$FIXTURE_HOME/.config/$app_id" \
    "$FIXTURE_HOME/.local/share/$app_id/bin" \
    "$FIXTURE_HOME/.local/share/applications"
  printf '{"app":"%s","recent":"project-%s"}\n' "$app_id" "$app_id" >"$FIXTURE_HOME/.config/$app_id/settings.json"
  printf '#!/usr/bin/env bash\nprintf "fixture-%s\\n"\n' "$app_id" >"$FIXTURE_HOME/.local/share/$app_id/bin/$app_id"
  chmod 700 "$FIXTURE_HOME/.local/share/$app_id/bin/$app_id"
  printf '[Desktop Entry]\nName=%s\nType=Application\nExec=%s\n' "$app_id" "$FIXTURE_HOME/.local/share/$app_id/bin/$app_id" >"$FIXTURE_HOME/.local/share/applications/$app_id.desktop"
}

create_fixture fixture-one
create_fixture fixture-two
create_fixture fixture-three
RESTIC_PASSWORD_FILE="$PASSWORD_FILE" RESTIC_CACHE_DIR="$RESTIC_CACHE_DIR" restic -r "$REPOSITORY" init >/dev/null

run_app_test() {
  HOME="$FIXTURE_HOME" \
    USER="${USER:-$(id -un)}" \
    RESTIC_REPOSITORY="$REPOSITORY" \
    RESTIC_PASSWORD_FILE="$PASSWORD_FILE" \
    OMARCHY_RESTIC_PASSWORD_FILE="$PASSWORD_FILE" \
    RESTIC_CACHE_DIR="$RESTIC_CACHE_DIR" \
    "$ROOT_DIR/omarchy-restic-app-test" "$@"
}

capture_output="$TEST_ROOT/capture.txt"
set +e
run_app_test capture --catalog "$catalog" --app fixture-one --app fixture-two --app fixture-three --workdir "$WORKDIR" >"$capture_output" 2>&1
capture_status=$?
set -e
assert_status 0 "$capture_status" 'capture do snapshot de teste'
assert_contains "$capture_output" 'omarchy-app-test' 'capture informa a tag do snapshot'

snapshot_output="$(RESTIC_PASSWORD_FILE="$PASSWORD_FILE" RESTIC_CACHE_DIR="$RESTIC_CACHE_DIR" restic -r "$REPOSITORY" snapshots --tag omarchy-app-test --latest 1)"
grep -Fq 'omarchy-app-test' <<<"$snapshot_output" || fail 'snapshot de teste não encontrado'

manifest_stage="$TEST_ROOT/manifest-stage"
mkdir -m 700 "$manifest_stage"
RESTIC_PASSWORD_FILE="$PASSWORD_FILE" RESTIC_CACHE_DIR="$RESTIC_CACHE_DIR" restic -r "$REPOSITORY" restore latest --tag omarchy-app-test --target "$manifest_stage" --verify >/dev/null
manifest_path="$(find "$manifest_stage" -type f -name omarchy-app-test-manifest.txt -print -quit)"
[[ -n "$manifest_path" ]] || fail 'manifest de teste não encontrado no snapshot'
assert_contains "$manifest_path" 'format=omarchy-app-test-v1' 'manifest informa o formato'
assert_contains "$manifest_path" 'app.1.id=fixture-one' 'manifest contém fixture-one'
assert_contains "$manifest_path" 'app.2.id=fixture-two' 'manifest contém fixture-two'
assert_contains "$manifest_path" 'app.3.id=fixture-three' 'manifest contém fixture-three'
assert_contains "$manifest_path" $'\tsha256=' 'manifest contém SHA-256'
assert_contains "$manifest_path" $'\trole=installation\t' 'manifest contém caminhos de instalação'

verify_output="$TEST_ROOT/verify-capture.txt"
set +e
run_app_test verify-capture --catalog "$catalog" --workdir "$WORKDIR" >"$verify_output" 2>&1
verify_status=$?
set -e
assert_status 0 "$verify_status" 'verify-capture'
assert_contains "$verify_output" 'PASS' 'verify-capture informa sucesso'

rm -f \
  "$FIXTURE_HOME/.local/share/fixture-one/bin/fixture-one" \
  "$FIXTURE_HOME/.local/share/fixture-two/bin/fixture-two" \
  "$FIXTURE_HOME/.local/share/fixture-three/bin/fixture-three"

removed_output="$TEST_ROOT/assert-removed.txt"
set +e
run_app_test assert-removed --catalog "$catalog" --workdir "$WORKDIR" >"$removed_output" 2>&1
removed_status=$?
set -e
assert_status 0 "$removed_status" 'assert-removed sem artefatos'
assert_contains "$removed_output" 'PASS' 'assert-removed informa sucesso'

printf '#!/usr/bin/env bash\n' >"$FIXTURE_HOME/.local/share/fixture-two/bin/fixture-two"
chmod 700 "$FIXTURE_HOME/.local/share/fixture-two/bin/fixture-two"
expect_failure_contains \
  'assert-removed com artefato restante' \
  'fixture-two' \
  run_app_test assert-removed --catalog "$catalog" --workdir "$WORKDIR"
rm -f "$FIXTURE_HOME/.local/share/fixture-two/bin/fixture-two"

printf 'arquivo fora do conjunto selecionado\n' >"$FIXTURE_HOME/unrelated.txt"
printf 'sentinela anterior\n' >"$FIXTURE_HOME/.local/share/fixture-one/bin/fixture-one"
chmod 700 "$FIXTURE_HOME/.local/share/fixture-one/bin/fixture-one"

restore_output="$TEST_ROOT/restore.txt"
set +e
run_app_test restore --catalog "$catalog" --yes --workdir "$WORKDIR" >"$restore_output" 2>&1
restore_status=$?
set -e
assert_status 0 "$restore_status" 'restore dos caminhos de usuário'
assert_contains "$restore_output" 'PASS' 'restore informa sucesso'
[[ -f "$FIXTURE_HOME/.config/fixture-one/settings.json" ]] || fail 'configuração do fixture-one não foi restaurada'
[[ -x "$FIXTURE_HOME/.local/share/fixture-one/bin/fixture-one" ]] || fail 'executável do fixture-one não foi restaurado'
[[ -f "$FIXTURE_HOME/.local/share/fixture-two/bin/fixture-two" ]] || fail 'executável do fixture-two não foi restaurado'
[[ -f "$FIXTURE_HOME/.local/share/fixture-three/bin/fixture-three" ]] || fail 'executável do fixture-three não foi restaurado'
[[ -f "$FIXTURE_HOME/unrelated.txt" ]] || fail 'arquivo não selecionado foi removido'
pre_restore_dir="$(find "$FIXTURE_HOME" -maxdepth 1 -type d -name '.omarchy-restic-app-test-pre-restore-*' -print -quit)"
[[ -n "$pre_restore_dir" ]] || fail 'diretório de segurança do restore não foi criado'

validate_output="$TEST_ROOT/validate.txt"
set +e
run_app_test validate --catalog "$catalog" --workdir "$WORKDIR" >"$validate_output" 2>&1
validate_status=$?
set -e
assert_status 0 "$validate_status" 'validate após restore'
assert_contains "$validate_output" 'PASS' 'validate informa sucesso'

printf '\nconteúdo alterado depois do restore\n' >>"$FIXTURE_HOME/.config/fixture-one/settings.json"
expect_failure_contains \
  'validate com hash alterado' \
  'fixture-one' \
  run_app_test validate --catalog "$catalog" --workdir "$WORKDIR"

app_help="$TEST_ROOT/app-help.txt"
"$ROOT_DIR/omarchy-restic-app-test" --help >"$app_help"
assert_contains "$app_help" 'assert-removed' 'ajuda lista assert-removed'
assert_contains "$ROOT_DIR/README.md" 'omarchy-restic-app-test capture' 'README documenta a captura de aplicativos'
assert_contains "$ROOT_DIR/README.md" 'não remove aplicativos automaticamente' 'README documenta a remoção manual'
assert_contains "$ROOT_DIR/README.md" 'STAGED ONLY' 'README documenta caminhos de sistema em staging'

printf 'PASS: harness inicial\n'
