#!/usr/bin/env bash
# test/install.test.sh — mock-$HOME install tests for ./setup
#
# Usage:
#   ./test/install.test.sh
#
# Tests run in isolated temp directories. No system state is modified.

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# ─── Helpers ─────────────────────────────────────────────────

pass() { echo "    PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "    FAIL  $1"; FAIL=$((FAIL + 1)); }

assert_link() {
  local path="$1" label="$2"
  [ -L "$path" ] && pass "$label" || fail "$label — expected symlink at $path"
}

assert_no_link() {
  local path="$1" label="$2"
  [ ! -L "$path" ] && pass "$label" || fail "$label — unexpected symlink at $path"
}

assert_file() {
  local path="$1" label="$2"
  [ -f "$path" ] && pass "$label" || fail "$label — expected file at $path"
}

assert_contains() {
  local path="$1" needle="$2" label="$3"
  grep -q "$needle" "$path" 2>/dev/null && pass "$label" || fail "$label — '$needle' not in $path"
}

assert_exit_nonzero() {
  local code="$1" label="$2"
  [ "$code" -ne 0 ] && pass "$label" || fail "$label — expected non-zero exit"
}

run_setup() {
  (cd "$1" && ./setup "${@:2}") >/dev/null 2>&1
}

# Skills that should be registered (everything with a SKILL.md).
# This list is intentionally explicit — new skills must be added here consciously.
# The count-check below will catch a mismatch if a skill is added to the repo
# without updating this list.
#
# Format: skill_name:relative_path (name is what gets symlinked, path is source)
SKILLS_WITH_PATHS=(
  "seo-analysis:seo/seo-analysis"
  "content-writer:seo/content-writer"
  "keyword-research:seo/keyword-research"
  "meta-tags-optimizer:seo/meta-tags-optimizer"
  "schema-markup-generator:seo/schema-markup-generator"
  "setup-cms:seo/setup-cms"
  "ads:google-ads/ads"
  "toprank-upgrade:toprank-upgrade"
)

# Extract just skill names for iteration
SKILLS=()
for entry in "${SKILLS_WITH_PATHS[@]}"; do
  SKILLS+=("${entry%%:*}")
done

# Build associative-style lookup: skill_name -> relative_path
skill_rel_path() {
  local name="$1"
  for entry in "${SKILLS_WITH_PATHS[@]}"; do
    if [ "${entry%%:*}" = "$name" ]; then
      echo "${entry#*:}"
      return
    fi
  done
}

# Guard: actual SKILL.md count must match the SKILLS array above.
actual_skill_count=$(find "$REPO_ROOT" -maxdepth 3 -name "SKILL.md" | wc -l | tr -d ' ')
if [ "$actual_skill_count" -ne "${#SKILLS[@]}" ]; then
  echo "ERROR: SKILLS array has ${#SKILLS[@]} entries but repo has $actual_skill_count SKILL.md files."
  echo "       Update the SKILLS array in this file to match."
  exit 1
fi

# Make a fresh copy of the repo in a subdirectory of TMP (exclude .git to
# avoid confusing git rev-parse in tests that set up their own git repo)
clone_into() {
  local dest="$1"
  mkdir -p "$dest"
  rsync -a --exclude='.git' --exclude='.claude' "$REPO_ROOT/" "$dest/"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ─── Test 1: Claude Code global install (--host claude) ───────

echo ""
echo "=== 1. Claude Code global install ==="

T1="$TMP/t1"
SKILLS_DIR="$T1/.claude/skills"
TOPRANK_DIR="$SKILLS_DIR/toprank"

clone_into "$TOPRANK_DIR"
run_setup "$TOPRANK_DIR" --host claude

for skill in "${SKILLS[@]}"; do
  assert_link "$SKILLS_DIR/$skill" "symlink created: $skill"
done

# Each symlink must point to toprank/<relative_path>
for skill in "${SKILLS[@]}"; do
  rel=$(skill_rel_path "$skill")
  expected_target="toprank/$rel"
  target="$(readlink "$SKILLS_DIR/$skill" 2>/dev/null || echo '')"
  [ "$target" = "$expected_target" ] \
    && pass "symlink target correct: $skill -> $expected_target" \
    || fail "symlink target wrong for $skill — got '$target', want '$expected_target'"
done

# SKILL.md files (except toprank-upgrade and ads) must have preamble injected
for skill in "${SKILLS[@]}"; do
  [ "$skill" = "toprank-upgrade" ] && continue
  [ "$skill" = "ads" ] && continue
  rel=$(skill_rel_path "$skill")
  assert_contains "$TOPRANK_DIR/$rel/SKILL.md" "toprank-update-check" "preamble injected: $skill"
done

# ─── Test 2: Auto-detect via path (no --host flag) ────────────

echo ""
echo "=== 2. Auto-detect: path ends in .claude/skills ==="

T2="$TMP/t2"
SKILLS_DIR2="$T2/.claude/skills"
TOPRANK_DIR2="$SKILLS_DIR2/toprank"

clone_into "$TOPRANK_DIR2"
run_setup "$TOPRANK_DIR2"  # no --host flag

for skill in "${SKILLS[@]}"; do
  assert_link "$SKILLS_DIR2/$skill" "auto-detected and linked: $skill"
done

# ─── Test 3: Idempotency — running setup twice is safe ────────

echo ""
echo "=== 3. Idempotency (setup runs twice) ==="

run_setup "$TOPRANK_DIR" --host claude  # second run on T1

for skill in "${SKILLS[@]}"; do
  assert_link "$SKILLS_DIR/$skill" "symlink still valid after re-run: $skill"
done

# No extra symlinks created
actual_count="$(find "$SKILLS_DIR" -maxdepth 1 -type l | wc -l | tr -d ' ')"
expected_count="${#SKILLS[@]}"
[ "$actual_count" -eq "$expected_count" ] \
  && pass "no duplicate links ($actual_count total)" \
  || fail "wrong link count — got $actual_count, want $expected_count"

# ─── Test 4: Real directory is not overwritten ────────────────

echo ""
echo "=== 4. Existing real directory is not overwritten ==="

T4="$TMP/t4"
SKILLS_DIR4="$T4/.claude/skills"
TOPRANK_DIR4="$SKILLS_DIR4/toprank"

clone_into "$TOPRANK_DIR4"
mkdir -p "$SKILLS_DIR4/seo-analysis"  # real dir, not a symlink

output="$(cd "$TOPRANK_DIR4" && ./setup --host claude 2>&1 || true)"

assert_no_link "$SKILLS_DIR4/seo-analysis" "real dir not overwritten"
echo "$output" | grep -q "skipped seo-analysis" \
  && pass "skip message shown for existing real dir" \
  || fail "no skip message for existing real dir"

# Other skills still get linked
for skill in "${SKILLS[@]}"; do
  [ "$skill" = "seo-analysis" ] && continue
  assert_link "$SKILLS_DIR4/$skill" "other skills linked despite skip: $skill"
done

# ─── Test 5: Codex install (--host codex) ─────────────────────

echo ""
echo "=== 5. Codex install ==="

T5="$TMP/t5"
REPO="$T5/myproject"
TOPRANK_DIR5="$REPO/.agents/skills/toprank"
AGENTS_DIR="$REPO/.agents/skills"

git init "$REPO" >/dev/null 2>&1
clone_into "$TOPRANK_DIR5"
run_setup "$TOPRANK_DIR5" --host codex

for skill in "${SKILLS[@]}"; do
  codex_name="toprank-$skill"
  assert_file  "$AGENTS_DIR/$codex_name/agents/openai.yaml" "openai.yaml created: $codex_name"
  assert_file  "$AGENTS_DIR/$codex_name/SKILL.md"           "SKILL.md copied: $codex_name"
done

# openai.yaml must have required fields
yaml="$AGENTS_DIR/toprank-seo-analysis/agents/openai.yaml"
assert_contains "$yaml" "display_name"             "openai.yaml has display_name"
assert_contains "$yaml" "allow_implicit_invocation" "openai.yaml has allow_implicit_invocation"
assert_contains "$yaml" "toprank-seo-analysis"      "openai.yaml has correct skill name"

# ─── Test 6: Invalid --host value exits non-zero ──────────────

echo ""
echo "=== 6. Invalid --host exits non-zero ==="

T6="$TMP/t6"
clone_into "$T6/toprank"
exit_code=0
(cd "$T6/toprank" && ./setup --host badvalue) >/dev/null 2>&1 || exit_code=$?
assert_exit_nonzero "$exit_code" "--host badvalue exits non-zero"

# ─── Test 7: Google Ads interactive setup ─────────────────────

echo ""
echo "=== 7. Google Ads interactive setup ==="

T7="$TMP/t7"
SKILLS_DIR7="$T7/.claude/skills"
TOPRANK_DIR7="$SKILLS_DIR7/toprank"
HOME7="$T7/home"

clone_into "$TOPRANK_DIR7"

# Simulate interactive input: "y" then a test API key
# TOPRANK_FORCE_INTERACTIVE bypasses the isatty() check for piped input
printf 'y\nasa_test_key_123\n' | HOME="$HOME7" TOPRANK_FORCE_INTERACTIVE=1 \
  bash -c 'cd "'"$TOPRANK_DIR7"'" && ./setup --host claude' >/dev/null 2>&1

# Verify config was written
config_file="$HOME7/.adsagent/config.json"
assert_file "$config_file" "ads config file created"
if [ -f "$config_file" ]; then
  assert_contains "$config_file" "asa_test_key_123" "ads config has correct API key"
fi

# ─── Test 8: Google Ads setup with --api-key flag ─────────────

echo ""
echo "=== 8. Google Ads --api-key flag ==="

T8="$TMP/t8"
SKILLS_DIR8="$T8/.claude/skills"
TOPRANK_DIR8="$SKILLS_DIR8/toprank"
HOME8="$T8/home"

clone_into "$TOPRANK_DIR8"
HOME="$HOME8" bash -c 'cd "'"$TOPRANK_DIR8"'" && ./setup --host claude --api-key asa_flag_key_456' >/dev/null 2>&1

config_file8="$HOME8/.adsagent/config.json"
assert_file "$config_file8" "ads config created via --api-key"
if [ -f "$config_file8" ]; then
  assert_contains "$config_file8" "asa_flag_key_456" "ads config has flag API key"
fi

# ─── Results ──────────────────────────────────────────────────

echo ""
echo "─────────────────────────────"
echo "  $PASS passed  |  $FAIL failed"
echo "─────────────────────────────"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
