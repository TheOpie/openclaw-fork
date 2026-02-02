#!/bin/bash
#
# Test suite for openclaw-model-switch.sh
# Uses temporary directories - does not modify actual config files
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temporary test directory
TEST_DIR=""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Setup test environment
setup() {
    TEST_DIR=$(mktemp -d)
    echo -e "${CYAN}Setting up test environment in: $TEST_DIR${NC}"

    # Create directory structure
    mkdir -p "$TEST_DIR/.openclaw/config/models"

    # Create a minimal base.json for testing
    cat > "$TEST_DIR/.openclaw/config/base.json" << 'EOF'
{
  "meta": {
    "lastTouchedVersion": "2026.1.30",
    "lastTouchedAt": null
  },
  "auth": {
    "profiles": {
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key"
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": null
      },
      "models": {},
      "workspace": "/tmp/test-workspace"
    }
  },
  "skills": {
    "entries": {
      "existing-skill": {
        "apiKey": "original-key"
      }
    }
  },
  "plugins": {
    "entries": {}
  }
}
EOF

    # Copy example model profiles
    cp "$SCRIPT_DIR/examples/"*.json "$TEST_DIR/.openclaw/config/models/" 2>/dev/null || {
        # Create minimal profiles if examples don't exist
        cat > "$TEST_DIR/.openclaw/config/models/opus-4.5.json" << 'EOF'
{
  "name": "Claude Opus 4.5",
  "description": "Test Opus 4.5",
  "primary": "anthropic/claude-opus-4-5",
  "models": { "anthropic/claude-opus-4-5": {} },
  "providers": {}
}
EOF
        cat > "$TEST_DIR/.openclaw/config/models/ollama-local.json" << 'EOF'
{
  "name": "Ollama Local",
  "description": "Test Ollama",
  "primary": "ollama/llama3.2:latest",
  "models": {},
  "providers": {
    "ollama": {
      "baseUrl": "http://127.0.0.1:11434/v1",
      "apiKey": "ollama-local"
    }
  }
}
EOF
    }

    # Create initial openclaw.json (same as base but with a model set)
    jq '.agents.defaults.model.primary = "anthropic/claude-opus-4-5"' \
        "$TEST_DIR/.openclaw/config/base.json" > "$TEST_DIR/.openclaw/openclaw.json"

    # Create a modified version of the script that uses TEST_DIR
    sed "s|OPENCLAW_DIR=\"\${OPENCLAW_DIR:-\$HOME/.openclaw}\"|OPENCLAW_DIR=\"$TEST_DIR/.openclaw\"|g" \
        "$SCRIPT_DIR/openclaw-model-switch.sh" > "$TEST_DIR/openclaw-model-switch.sh"
    chmod +x "$TEST_DIR/openclaw-model-switch.sh"
}

# Cleanup test environment
cleanup() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        echo -e "${CYAN}Cleaning up test directory...${NC}"
        rm -rf "$TEST_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Test assertion helpers
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    Expected: ${CYAN}$expected${NC}"
        echo -e "    Actual:   ${RED}$actual${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local description="$1"
    local needle="$2"
    local haystack="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  ${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    Expected to contain: ${CYAN}$needle${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local description="$1"
    local filepath="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ -f "$filepath" ]]; then
        echo -e "  ${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    File not found: ${RED}$filepath${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================
# TEST CASES
# ============================================

test_basic_profile_switch() {
    echo -e "\n${BOLD}Test: Basic Profile Switch${NC}"

    # Switch to ollama profile
    "$TEST_DIR/openclaw-model-switch.sh" ollama-local > /dev/null 2>&1

    # Check the model was set correctly
    local model=$(jq -r '.agents.defaults.model.primary' "$TEST_DIR/.openclaw/openclaw.json")
    assert_equals "Primary model set to ollama" "ollama/llama3.2:latest" "$model"

    # Check providers section was added
    local has_ollama=$(jq '.models.providers.ollama != null' "$TEST_DIR/.openclaw/openclaw.json")
    assert_equals "Ollama provider config present" "true" "$has_ollama"

    # Switch back to opus
    "$TEST_DIR/openclaw-model-switch.sh" opus-4.5 > /dev/null 2>&1

    model=$(jq -r '.agents.defaults.model.primary' "$TEST_DIR/.openclaw/openclaw.json")
    assert_equals "Primary model set to opus" "anthropic/claude-opus-4-5" "$model"

    # Check providers section was removed (opus doesn't need it)
    local has_models=$(jq '.models != null' "$TEST_DIR/.openclaw/openclaw.json")
    assert_equals "Models section removed for Anthropic profile" "false" "$has_models"
}

test_sync_detects_new_skill() {
    echo -e "\n${BOLD}Test: Sync Detects New Skill Added${NC}"

    # Add a new skill directly to openclaw.json
    jq '.skills.entries["test-new-skill"] = {"apiKey": "test-key-12345"}' \
        "$TEST_DIR/.openclaw/openclaw.json" > "$TEST_DIR/.openclaw/openclaw.json.tmp"
    mv "$TEST_DIR/.openclaw/openclaw.json.tmp" "$TEST_DIR/.openclaw/openclaw.json"

    # Switch profile (should trigger sync)
    local output=$("$TEST_DIR/openclaw-model-switch.sh" ollama-local 2>&1)
    assert_contains "Sync detected changes" "Detected changes" "$output"

    # Check that base.json now has the new skill
    local skill_in_base=$(jq -r '.skills.entries["test-new-skill"].apiKey' "$TEST_DIR/.openclaw/config/base.json")
    assert_equals "Skill synced to base.json" "test-key-12345" "$skill_in_base"
}

test_sync_creates_backup() {
    echo -e "\n${BOLD}Test: Sync Creates Backup${NC}"

    # Count backups before
    local backup_count_before=$(ls -1 "$TEST_DIR/.openclaw/config/base.json."*.bak 2>/dev/null | wc -l)

    sleep 1  # Ensure different timestamp

    # Make a change
    jq '.skills.entries["another-skill"] = {"key": "value"}' \
        "$TEST_DIR/.openclaw/openclaw.json" > "$TEST_DIR/.openclaw/openclaw.json.tmp"
    mv "$TEST_DIR/.openclaw/openclaw.json.tmp" "$TEST_DIR/.openclaw/openclaw.json"

    # Switch profile
    "$TEST_DIR/openclaw-model-switch.sh" opus-4.5 > /dev/null 2>&1

    # Check backup was created
    local backup_count_after=$(ls -1 "$TEST_DIR/.openclaw/config/base.json."*.bak 2>/dev/null | wc -l)
    local expected=$((backup_count_before + 1))
    assert_equals "Backup file created" "$expected" "$backup_count_after"
}

test_no_sync_when_unchanged() {
    echo -e "\n${BOLD}Test: No Sync When Config Unchanged${NC}"

    # Count current backups
    local backup_count_before=$(ls -1 "$TEST_DIR/.openclaw/config/base.json."*.bak 2>/dev/null | wc -l)

    # Switch profile without making changes
    local output=$("$TEST_DIR/openclaw-model-switch.sh" ollama-local 2>&1)

    # Should NOT contain "Detected changes"
    if echo "$output" | grep -q "Detected changes"; then
        TESTS_RUN=$((TESTS_RUN + 1))
        echo -e "  ${RED}✗${NC} No sync triggered when unchanged"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        echo -e "  ${GREEN}✓${NC} No sync triggered when unchanged"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    # Backup count should be the same
    local backup_count_after=$(ls -1 "$TEST_DIR/.openclaw/config/base.json."*.bak 2>/dev/null | wc -l)
    assert_equals "No new backup created" "$backup_count_before" "$backup_count_after"
}

test_model_specific_fields_excluded() {
    echo -e "\n${BOLD}Test: Model-Specific Fields Excluded From Base${NC}"

    # Switch to ollama (adds .models section)
    "$TEST_DIR/openclaw-model-switch.sh" ollama-local > /dev/null 2>&1

    # Verify .models section exists in openclaw.json
    local has_models_in_config=$(jq '.models != null' "$TEST_DIR/.openclaw/openclaw.json")
    assert_equals "Models section in openclaw.json" "true" "$has_models_in_config"

    # Verify .models section is NOT in base.json
    local has_models_in_base=$(jq '.models != null' "$TEST_DIR/.openclaw/config/base.json")
    assert_equals "Models section excluded from base.json" "false" "$has_models_in_base"

    # Verify primary model is null in base.json
    local primary_in_base=$(jq -r '.agents.defaults.model.primary' "$TEST_DIR/.openclaw/config/base.json")
    assert_equals "Primary model null in base.json" "null" "$primary_in_base"
}

test_current_model_tracking() {
    echo -e "\n${BOLD}Test: Current Model Tracking${NC}"

    # Switch to ollama
    "$TEST_DIR/openclaw-model-switch.sh" ollama-local > /dev/null 2>&1

    # Check .current-model file
    local current=$(cat "$TEST_DIR/.openclaw/config/.current-model")
    assert_equals "Current model tracked (ollama)" "ollama-local" "$current"

    # Switch to opus
    "$TEST_DIR/openclaw-model-switch.sh" opus-4.5 > /dev/null 2>&1

    current=$(cat "$TEST_DIR/.openclaw/config/.current-model")
    assert_equals "Current model tracked (opus)" "opus-4.5" "$current"
}

test_invalid_profile() {
    echo -e "\n${BOLD}Test: Invalid Profile Handling${NC}"

    local output=$("$TEST_DIR/openclaw-model-switch.sh" nonexistent-profile 2>&1 || true)
    assert_contains "Error shown for invalid profile" "not found" "$output"
}

test_help_command() {
    echo -e "\n${BOLD}Test: Help Command${NC}"

    local output=$("$TEST_DIR/openclaw-model-switch.sh" --help 2>&1)
    assert_contains "Help shows usage" "Usage" "$output"
    assert_contains "Help shows examples" "Examples" "$output"
}

# ============================================
# RUN TESTS
# ============================================

main() {
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Model Profile Switcher Test Suite${NC}"
    echo -e "${BOLD}========================================${NC}"

    # Check for jq
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required to run tests${NC}"
        exit 1
    fi

    setup

    test_basic_profile_switch
    test_sync_detects_new_skill
    test_sync_creates_backup
    test_no_sync_when_unchanged
    test_model_specific_fields_excluded
    test_current_model_tracking
    test_invalid_profile
    test_help_command

    echo -e "\n${BOLD}========================================${NC}"
    echo -e "${BOLD}  Test Results${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo -e "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "  Failed: 0"
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
