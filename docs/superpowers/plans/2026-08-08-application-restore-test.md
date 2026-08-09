# Reversible Application Restore Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repeatable three-application Restic test that captures user state, verifies the capture, checks manual removal, restores approved paths, and validates hashes, permissions, launchers, and home-owned executables.

**Architecture:** Keep the existing full migration scripts unchanged and add `omarchy-restic-app-test` as a separate phase-oriented command. A non-executable catalog defines each application's user paths, installation paths, launcher paths, and restore mode; the command creates an isolated `omarchy-app-test` snapshot and stores a metadata manifest with it. Only paths inside the current HOME are copied automatically during restore; system paths are restored to staging and reported for explicit manual handling.

**Tech Stack:** Bash with `set -Eeuo pipefail`, Restic 0.12+, rsync, core POSIX utilities, SHA-256 via `sha256sum`, and a dependency-free Bash integration test using temporary directories and a temporary Restic repository.

---

## File map and boundaries

- Create `omarchy-restic-app-test`: phase parser, catalog reader, capture, verified temporary restore, removal assertions, home-only restore, and manifest validation.
- Create `omarchy-restic-apps.conf`: editable catalog for `rubymine`, `jetbrains-toolbox`, and `obsidian`; the user may add or replace the third selection without changing the script.
- Create `tests/omarchy-restic-app-test.sh`: executable end-to-end test with synthetic applications and a real temporary Restic repository.
- Modify `README.md`: explain the five phases, catalog editing, password/repository variables, system-path staging, and the required order around manual uninstallation.
- Do not modify `omarchy-restic-backup`, `omarchy-restic-restore`, or `omarchy-restic-verify` behavior in this feature. Add the new script to the existing “copy scripts to the external disk” instructions.

## Task 1: Add the failing integration harness

**Files:**
- Create: `tests/omarchy-restic-app-test.sh`
- Test target not yet present: `omarchy-restic-app-test`

- [ ] **Step 1: Write the failing test harness.**

Create a Bash test runner with these helpers and assertions:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-restic-app-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_status() {
  local expected="$1" actual="$2" description="$3"
  [[ "$expected" == "$actual" ]] || fail "$description: esperado status $expected, recebido $actual"
}
assert_contains() {
  local file="$1" text="$2" description="$3"
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
```

At this point the test must fail because the production entrypoint does not exist. Keep the failure as the first RED result; do not weaken the assertion to accept a missing command.

- [ ] **Step 2: Run the test and record the expected RED result.**

Run:

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: non-zero exit because `omarchy-restic-app-test` is not yet present. No Restic repository or user data is touched.

- [ ] **Step 3: Commit the failing test only.**

```bash
git add tests/omarchy-restic-app-test.sh
git commit -m "test: define application restore test harness"
```

## Task 2: Define and safely parse the application catalog

**Files:**
- Create: `omarchy-restic-apps.conf`
- Modify: `omarchy-restic-app-test`
- Test: `tests/omarchy-restic-app-test.sh`

- [ ] **Step 1: Add catalog fixture assertions before implementation.**

Extend the test to create a temporary catalog with three home-owned fixtures:

```text
# id|name|command|preserve_home|installation_paths|launcher_paths|installer_path|restore_mode
fixture-one|Fixture One||$HOME/.config/fixture-one;$HOME/.local/share/fixture-one|$HOME/.local/share/fixture-one/bin/fixture-one|$HOME/.local/share/applications/fixture-one.desktop|none|home
fixture-two|Fixture Two||$HOME/.config/fixture-two;$HOME/.local/share/fixture-two|$HOME/.local/share/fixture-two/bin/fixture-two|$HOME/.local/share/applications/fixture-two.desktop|none|home
fixture-three|Fixture Three||$HOME/.config/fixture-three;$HOME/.local/share/fixture-three|$HOME/.local/share/fixture-three/bin/fixture-three|$HOME/.local/share/applications/fixture-three.desktop|none|home
```

Add assertions that two `--app` values are rejected, duplicate IDs are rejected, an unknown ID is rejected, and a `preserve_home` path outside `$HOME` is rejected.

- [ ] **Step 2: Run the new assertions and verify they fail for the missing catalog/entrypoint behavior.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: the new assertions fail with the missing command or missing catalog behavior, while the failure identifies the first unimplemented catalog contract.

- [ ] **Step 3: Implement the catalog reader.**

Implement these internal functions in `omarchy-restic-app-test` without sourcing or evaluating the catalog:

```bash
catalog_load()                 # reads non-comment lines split into 8 fields
catalog_find_app()             # returns one record for an exact ID
expand_catalog_path()          # expands only $HOME/, ~/, absolute paths, and globs
collect_matches()              # emits sorted unique existing paths for one pattern
validate_home_path()           # rejects a preserve path outside CURRENT_HOME
```

The parser must reject empty IDs, IDs containing whitespace or `|`, fewer or more than eight fields, unknown `restore_mode` values, and duplicate IDs. It must preserve literal spaces in path values and must never execute catalog text as shell code. The accepted restore modes are `home` and `staged`.

The default catalog must contain these initial records:

```text
rubymine|RubyMine|rubymine|$HOME/.config/JetBrains/RubyMine*|$HOME/.local/share/JetBrains/Toolbox/apps/rubymine*|$HOME/.local/share/applications/rubymine*.desktop|none|home
jetbrains-toolbox|JetBrains Toolbox|jetbrains-toolbox|$HOME/.local/share/JetBrains/Toolbox|$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox|$HOME/.config/autostart/jetbrains-toolbox.desktop;$HOME/.local/share/applications/jetbrains-toolbox.desktop|none|home
obsidian|Obsidian|obsidian|$HOME/.config/obsidian;$HOME/Documents/Obsidian Vault|$HOME/.local/bin/Obsidian.AppImage;$HOME/.local/bin/obsidian|$HOME/.local/share/applications/obsidian.desktop|none|home
```

The capture phase will require at least one match for every `preserve_home` pattern and every `installation_paths` pattern. This makes the current absence of the RubyMine/Toolbox executable an explicit precondition failure instead of a false-positive configuration-only test.

- [ ] **Step 4: Run the catalog tests to verify GREEN.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: catalog validation assertions pass, and the runner reports `PASS` for the parser contract.

- [ ] **Step 5: Commit the catalog and parser.**

```bash
git add omarchy-restic-app-test omarchy-restic-apps.conf tests/omarchy-restic-app-test.sh
git commit -m "feat: add safe application catalog parsing"
```

## Task 3: Implement capture and manifest generation

**Files:**
- Modify: `omarchy-restic-app-test`
- Test: `tests/omarchy-restic-app-test.sh`

- [ ] **Step 1: Add capture assertions before the capture implementation.**

The test must create a temporary HOME with three fixtures. Each fixture needs a JSON settings file, an executable under `.local/share/<id>/bin`, and a user launcher under `.local/share/applications`. Initialize a real temporary repository:

```bash
printf 'test-password\n' >"$password_file"
chmod 600 "$password_file"
RESTIC_PASSWORD_FILE="$password_file" restic -r "$repository" init
```

Invoke:

```bash
HOME="$fixture_home" \
OMARCHY_RESTIC_REPOSITORY="$repository" \
OMARCHY_RESTIC_PASSWORD_FILE="$password_file" \
bash "$ROOT_DIR/omarchy-restic-app-test" capture \
  --catalog "$catalog" \
  --app fixture-one --app fixture-two --app fixture-three \
  --workdir "$test_root"
```

Assert that the command exits zero, prints a snapshot ID without file contents, and creates a snapshot carrying exactly the tag `omarchy-app-test`. Assert that the snapshot manifest contains the three IDs, `source_home`, and path records with mode, size, SHA-256, and symlink target fields.

- [ ] **Step 2: Run the capture test and verify the expected RED result.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: the capture assertions fail because the phase is not implemented.

- [ ] **Step 3: Implement capture with strict safety checks.**

Add phase parsing and these options:

```text
capture|verify-capture|assert-removed|restore|validate
--app ID             repeatable, required exactly three times for capture
--catalog PATH       defaults to ./omarchy-restic-apps.conf
--snapshot ID        defaults to latest snapshot with omarchy-app-test tag
--workdir PATH       existing writable temporary/staging parent
--yes                bypasses only restore confirmation
--keep-stage         preserves a successful temporary stage for inspection
```

Use the same repository variables as the existing scripts: `OMARCHY_RESTIC_REPOSITORY`, `RESTIC_REPOSITORY`, `OMARCHY_RESTIC_MOUNT`, and `OMARCHY_RESTIC_WORKDIR`. Add `OMARCHY_RESTIC_PASSWORD_FILE` for non-interactive tests; when absent, prompt once and create a mode-600 temporary password file. Never print the password or manifest contents.

Capture must:

1. reject root execution;
2. validate the repository and Restic availability;
3. require three distinct catalog IDs;
4. reject a selected process when its catalog command has a matching running process;
5. expand and validate all catalog paths, requiring installed and preserved matches;
6. reject `preserve_home` paths outside `$CURRENT_HOME`;
7. create a mode-700 staging directory;
8. write a manifest with `format=omarchy-app-test-v1`, selected app records, source HOME, repository-independent timestamps, exact matched paths, path scope (`home` or `system`), type, mode, size, SHA-256 for regular files, and symlink target;
9. write an exclude file for `.cache`, Trash, `node_modules`, `vendor/bundle`, `.bundle`, `tmp`, `log`, `coverage`, and `.terraform` below HOME;
10. run `restic backup --one-file-system --exclude-file ... --tag omarchy-app-test` with the deduplicated selected paths, the optional installer paths, and the manifest staging directory;
11. print the resulting snapshot ID and leave no staging directory after success.

Hash only regular files; record directories as type/mode entries and symlinks as type/mode/target entries. Reject paths containing tabs or newlines before writing the tab-separated manifest.

- [ ] **Step 4: Run the capture assertions to verify GREEN.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: temporary repository initialization, capture, tag lookup, and manifest assertions pass.

- [ ] **Step 5: Commit capture behavior.**

```bash
git add omarchy-restic-app-test tests/omarchy-restic-app-test.sh
git commit -m "feat: capture application restore test snapshots"
```

## Task 4: Implement verified capture and manual-removal assertions

**Files:**
- Modify: `omarchy-restic-app-test`
- Test: `tests/omarchy-restic-app-test.sh`

- [ ] **Step 1: Add RED assertions for `verify-capture` and `assert-removed`.**

After capture, run:

```bash
HOME="$fixture_home" \
OMARCHY_RESTIC_REPOSITORY="$repository" \
OMARCHY_RESTIC_PASSWORD_FILE="$password_file" \
bash "$ROOT_DIR/omarchy-restic-app-test" verify-capture --workdir "$test_root"
```

Assert that the phase uses `restic restore --verify`, exits zero, and validates all three fixture IDs. Then remove only each fixture's installation directory and run `assert-removed`; assert zero exit. Recreate one installation directory without removing it and assert that `assert-removed` exits non-zero and names the remaining path only.

- [ ] **Step 2: Run the test and observe the expected RED result.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: the first unimplemented phase fails.

- [ ] **Step 3: Implement snapshot selection and `verify-capture`.**

Restore the latest `omarchy-app-test` snapshot to a mode-700 temporary stage, using `restic restore "$SNAPSHOT_ID" --target "$STAGE" --verify`. Locate the manifest by exact basename, validate `format`, `source_home`, app count, and unique IDs, then compare every manifest record against the restored path before deleting the stage. On failure, preserve the stage path in the error message.

- [ ] **Step 4: Implement `assert-removed`.**

Load the selected app records from the verified manifest. For each `installation_paths` match captured before removal, require that the same path is now absent. For a non-empty `command`, require `command -v` to fail and, when possible, require no exact process name. Do not require `preserve_home` paths to be absent. Return non-zero on any remaining installation artifact and print only the app ID and path.

- [ ] **Step 5: Run the phases and verify GREEN.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: verified capture passes, a clean manual-removal fixture passes, and the negative remaining-artifact case fails inside the test and is correctly recognized as expected.

- [ ] **Step 6: Commit verification and removal assertions.**

```bash
git add omarchy-restic-app-test tests/omarchy-restic-app-test.sh
git commit -m "feat: verify app capture and manual removal"
```

## Task 5: Implement home-only restore and manifest validation

**Files:**
- Modify: `omarchy-restic-app-test`
- Test: `tests/omarchy-restic-app-test.sh`

- [ ] **Step 1: Add RED assertions for restore and validation.**

Before restore, create an unrelated file in the fixture HOME and remove the three installation directories. Run:

```bash
HOME="$fixture_home" \
OMARCHY_RESTIC_REPOSITORY="$repository" \
OMARCHY_RESTIC_PASSWORD_FILE="$password_file" \
bash "$ROOT_DIR/omarchy-restic-app-test" restore --yes --workdir "$test_root"
```

Assert that the three home-owned configuration and installation paths return, the unrelated file remains, and a backup directory named `.omarchy-restic-app-test-pre-restore-*` exists when a sentinel file is placed at a selected destination before restore. Then run `validate` and assert zero exit with three application `PASS` records. Assert that a deliberately changed fixture file produces non-zero validation and reports its path without printing its content.

- [ ] **Step 2: Run the test and observe the expected RED result.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: restore or validation is the first failing unimplemented phase.

- [ ] **Step 3: Implement safe home-only restore.**

Restore the snapshot to a temporary stage with `--verify`, load the manifest, and require interactive confirmation unless `--yes` is present. For every manifest path classified as `home`, compute its relative path from the captured `source_home`, map it to the current `$HOME`, and copy it with:

```bash
rsync -a --backup --backup-dir="$PRE_RESTORE_DIR" "$source_path" "$destination_path"
```

Use `rsync -a` for directories and create only destination parents inside `$CURRENT_HOME`. Never pass `--delete`, never copy a `system` path into `/opt` or `/usr/share`, and reject any destination whose lexical path is outside `$CURRENT_HOME`. Preserve existing destination files under mode-700 `.omarchy-restic-app-test-pre-restore-<timestamp>`.

For `restore_mode=staged`, keep system install paths in the temporary stage and print an explicit `STAGED ONLY` result. A home-owned executable can be restored automatically when its catalog record has `restore_mode=home` and its path is present in the manifest.

- [ ] **Step 4: Implement manifest validation.**

For every restored `home` record, compare:

```text
regular file: type, mode, byte size, sha256sum
directory:    type and mode
symlink:      type, mode, readlink target
```

Do not compare UID/GID. Validate user launchers only when their destination is under HOME; require a referenced `Exec=` path to exist when the launcher is restored. For `staged` system paths, validate the stage copy and report that installation in the live system remains manual. Return non-zero if any app has a missing or mismatched required record.

- [ ] **Step 5: Run restore and validation tests to verify GREEN.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: restore preserves the unrelated file and overwritten sentinel, restores all selected home paths, validates all hashes, and rejects the deliberately modified file.

- [ ] **Step 6: Commit restore and validation behavior.**

```bash
git add omarchy-restic-app-test tests/omarchy-restic-app-test.sh
git commit -m "feat: restore and validate selected application state"
```

## Task 6: Document the real RubyMine/Toolbox workflow

**Files:**
- Modify: `README.md`
- Modify: `omarchy-restic-apps.conf`
- Modify: `omarchy-restic-app-test`

- [ ] **Step 1: Add documentation assertions.**

The test script help and README must contain the phase order and these safety statements:

```text
capture -> verify-capture -> manual uninstall -> assert-removed -> restore -> validate
the test does not remove applications automatically
system paths are staged and are not copied with sudo automatically
the main omarchy-migration snapshot remains required
```

- [ ] **Step 2: Run the documentation assertions and observe RED if any text is missing.**

```bash
bash tests/omarchy-restic-app-test.sh
```

- [ ] **Step 3: Document the commands.**

Add this workflow to `README.md`, replacing `<terceiro-app>` with a catalog ID:

```bash
chmod 700 omarchy-restic-app-test
export RESTIC_REPOSITORY="/media/$USER/Backup/omarchy-restic-v2"

./omarchy-restic-app-test capture \
  --app rubymine \
  --app jetbrains-toolbox \
  --app <terceiro-app>
./omarchy-restic-app-test verify-capture

# O usuário desinstala manualmente os três aplicativos aqui.
./omarchy-restic-app-test assert-removed
./omarchy-restic-app-test restore
./omarchy-restic-app-test validate
```

Document that the current machine must first have the RubyMine, Toolbox, and
Obsidian executables installed for `capture` to perform a complete executable
test. Explain that `~/.config/JetBrains/RubyMine*` is preserved as user state,
while an absent Toolbox binary cannot be inferred from those settings. Add the
new script and catalog to the `install` commands that copy migration tools to
the external disk.

- [ ] **Step 4: Run documentation checks and commit.**

```bash
bash tests/omarchy-restic-app-test.sh
git diff --check HEAD
git add README.md omarchy-restic-apps.conf omarchy-restic-app-test tests/omarchy-restic-app-test.sh
git commit -m "docs: document application restore rehearsal"
```

Expected result: all test assertions pass, the documentation contains the complete order, and `git diff --check` exits zero.

## Task 7: Perform layered verification and handoff

**Files:**
- Verify: `omarchy-restic-backup`
- Verify: `omarchy-restic-restore`
- Verify: `omarchy-restic-verify`
- Verify: `omarchy-restic-app-test`
- Verify: `README.md`

- [ ] **Step 1: Run syntax and help checks.**

```bash
bash -n omarchy-restic-backup omarchy-restic-restore omarchy-restic-verify omarchy-restic-app-test tests/omarchy-restic-app-test.sh
./omarchy-restic-app-test --help
./omarchy-restic-backup --help
./omarchy-restic-restore --help
./omarchy-restic-verify --help
```

Expected result: all commands exit zero and the existing scripts show no behavior changes in their help output.

- [ ] **Step 2: Run the complete disposable application test.**

```bash
bash tests/omarchy-restic-app-test.sh
```

Expected result: the test reports PASS for catalog safety, capture, verified restore, removal assertion, home restore, hash validation, permission validation, sentinel preservation, unrelated-file preservation, and negative mismatch detection.

- [ ] **Step 3: Review the resulting diff and worktree.**

```bash
git diff --check HEAD~1..HEAD
git status --short --branch
git log --oneline -8
```

Confirm that only the new feature files and README are part of the implementation commits. Preserve the existing untracked application inventory and prior environment design document unless the user explicitly requests them to be committed.

- [ ] **Step 4: Prepare the real-machine rehearsal without uninstalling anything automatically.**

Run `capture` and `verify-capture` first. If either fails because RubyMine/Toolbox is not currently installed, stop and report that the configuration-only backup remains possible but the executable removal/restore test is not yet valid. Only after both phases pass should the user manually close and uninstall the three selected applications, then run `assert-removed`, `restore`, and `validate`.

- [ ] **Step 5: Final handoff.**

Report separate evidence for:

- disposable test result;
- Restic snapshot/tag used;
- home-owned paths restored and validated;
- system paths staged but not installed;
- any missing installer or executable;
- existing full migration verification status.

Do not claim the real RubyMine/Toolbox test passed until the user has performed the manual uninstall and the final `validate` command exits zero.
