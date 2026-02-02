#!/bin/bash
#
# OpenClaw Model Profile Switcher
#
# A utility for managing multiple model configurations in OpenClaw.
# Allows quick switching between different AI models (Anthropic, Ollama, OpenAI, etc.)
# while preserving your base configuration (skills, channels, hooks, etc.).
#
# Usage:
#   openclaw-model-switch                  # Show current model and available profiles
#   openclaw-model-switch <profile>        # Switch to a specific profile
#   openclaw-model-switch --list           # List available profiles
#   openclaw-model-switch --sync           # Sync base.json with current config changes
#   openclaw-model-switch --init           # Initialize the profile system
#
# Environment:
#   OPENCLAW_MODEL - Set to auto-apply a profile on switch
#   OPENCLAW_DIR   - Override the OpenClaw config directory (default: ~/.openclaw)
#

set -e

# Configuration
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG_DIR="$OPENCLAW_DIR/config"
MODELS_DIR="$CONFIG_DIR/models"
BASE_CONFIG="$CONFIG_DIR/base.json"
OUTPUT_CONFIG="$OPENCLAW_DIR/openclaw.json"
CURRENT_MODEL_FILE="$CONFIG_DIR/.current-model"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Check dependencies
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed.${NC}"
        echo "Install with: sudo apt install jq (Debian/Ubuntu) or brew install jq (macOS)"
        exit 1
    fi
}

# Extract base config from a full config (strips model-specific fields)
extract_base() {
    local config_file="$1"
    jq '
        .meta.lastTouchedAt = null |
        .agents.defaults.model.primary = null |
        .agents.defaults.models = {} |
        del(.models)
    ' "$config_file" 2>/dev/null
}

# Sync base.json with any changes from current openclaw.json
sync_base_config() {
    if [[ ! -f "$OUTPUT_CONFIG" ]]; then
        return 0
    fi

    if [[ ! -f "$BASE_CONFIG" ]]; then
        echo -e "${YELLOW}No base.json found, creating from current config...${NC}"
        extract_base "$OUTPUT_CONFIG" > "$BASE_CONFIG"
        return 0
    fi

    # Extract base portions from both files for comparison
    local current_base=$(extract_base "$OUTPUT_CONFIG")
    local stored_base=$(extract_base "$BASE_CONFIG")

    # Compare (normalize by sorting keys)
    local current_hash=$(echo "$current_base" | jq -S '.' | md5sum | cut -d' ' -f1)
    local stored_hash=$(echo "$stored_base" | jq -S '.' | md5sum | cut -d' ' -f1)

    if [[ "$current_hash" != "$stored_hash" ]]; then
        local datestamp=$(date +"%Y-%m-%d_%H%M%S")
        local backup_file="$CONFIG_DIR/base.json.${datestamp}.bak"

        echo -e "${YELLOW}Detected changes in openclaw.json base settings${NC}"
        echo -e "Backing up old base.json to: ${CYAN}$(basename "$backup_file")${NC}"

        # Backup old base.json
        cp "$BASE_CONFIG" "$backup_file"

        # Update base.json with current config's base settings
        extract_base "$OUTPUT_CONFIG" > "$BASE_CONFIG"

        echo -e "${GREEN}Updated base.json with current config changes${NC}"
        echo ""
    fi
}

# Get current model from config
get_current_model() {
    if [[ -f "$OUTPUT_CONFIG" ]]; then
        jq -r '.agents.defaults.model.primary // "unknown"' "$OUTPUT_CONFIG" 2>/dev/null || echo "unknown"
    else
        echo "not configured"
    fi
}

# Get current profile name
get_current_profile() {
    if [[ -f "$CURRENT_MODEL_FILE" ]]; then
        cat "$CURRENT_MODEL_FILE"
    else
        echo "unknown"
    fi
}

# List available profiles
list_profiles() {
    echo -e "${BOLD}Available Model Profiles:${NC}"
    echo ""

    if [[ ! -d "$MODELS_DIR" ]] || [[ -z "$(ls -A "$MODELS_DIR" 2>/dev/null)" ]]; then
        echo -e "  ${YELLOW}No profiles found. Run with --init to set up example profiles.${NC}"
        return
    fi

    for profile in "$MODELS_DIR"/*.json; do
        if [[ -f "$profile" ]]; then
            local name=$(basename "$profile" .json)
            local display_name=$(jq -r '.name // "Unknown"' "$profile")
            local description=$(jq -r '.description // ""' "$profile")
            local primary=$(jq -r '.primary // ""' "$profile")

            local current_profile=$(get_current_profile)
            if [[ "$name" == "$current_profile" ]]; then
                echo -e "  ${GREEN}* $name${NC} - $display_name"
            else
                echo -e "    $name - $display_name"
            fi
            echo -e "      ${CYAN}$primary${NC}"
            if [[ -n "$description" ]]; then
                echo -e "      $description"
            fi
            echo ""
        fi
    done
}

# Show current status
show_status() {
    local current=$(get_current_model)
    local profile=$(get_current_profile)

    echo -e "${BOLD}OpenClaw Model Configuration${NC}"
    echo -e "───────────────────────────────"
    echo -e "Current Profile: ${GREEN}$profile${NC}"
    echo -e "Active Model:    ${CYAN}$current${NC}"

    if [[ -n "$OPENCLAW_MODEL" ]]; then
        echo -e "Env Override:    ${YELLOW}OPENCLAW_MODEL=$OPENCLAW_MODEL${NC}"
    fi
    echo ""

    # Check if gateway is running
    if command -v lsof &> /dev/null && lsof -i :18789 &>/dev/null; then
        echo -e "Gateway Status:  ${GREEN}Running${NC} (restart needed for changes)"
    elif command -v ss &> /dev/null && ss -tlnp 2>/dev/null | grep -q ":18789"; then
        echo -e "Gateway Status:  ${GREEN}Running${NC} (restart needed for changes)"
    else
        echo -e "Gateway Status:  ${YELLOW}Stopped${NC}"
    fi
    echo ""
}

# Initialize the profile system
init_profiles() {
    echo -e "${BOLD}Initializing Model Profile System${NC}"
    echo ""

    # Create directories
    mkdir -p "$CONFIG_DIR/models"

    # Create base.json from current config if it exists
    if [[ -f "$OUTPUT_CONFIG" ]]; then
        if [[ ! -f "$BASE_CONFIG" ]]; then
            echo -e "Creating base.json from current openclaw.json..."
            extract_base "$OUTPUT_CONFIG" > "$BASE_CONFIG"
            echo -e "${GREEN}Created: $BASE_CONFIG${NC}"
        else
            echo -e "${YELLOW}base.json already exists, skipping...${NC}"
        fi
    else
        echo -e "${RED}Warning: No openclaw.json found. Run 'openclaw setup' first.${NC}"
    fi

    # Copy example profiles if models dir is empty
    if [[ -z "$(ls -A "$MODELS_DIR" 2>/dev/null)" ]]; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -d "$script_dir/examples" ]]; then
            echo -e "Copying example profiles..."
            cp "$script_dir/examples/"*.json "$MODELS_DIR/" 2>/dev/null || true
            echo -e "${GREEN}Copied example profiles to: $MODELS_DIR${NC}"
        else
            echo -e "${YELLOW}No example profiles found. Creating defaults...${NC}"
            # Create default Anthropic profiles
            cat > "$MODELS_DIR/opus-4.5.json" << 'EOF'
{
  "name": "Claude Opus 4.5",
  "description": "Anthropic Claude Opus 4.5 - Latest flagship model",
  "primary": "anthropic/claude-opus-4-5",
  "models": {
    "anthropic/claude-opus-4-5": {}
  },
  "providers": {}
}
EOF
            cat > "$MODELS_DIR/sonnet-4.5.json" << 'EOF'
{
  "name": "Claude Sonnet 4.5",
  "description": "Anthropic Claude Sonnet 4.5 - Fast and capable",
  "primary": "anthropic/claude-sonnet-4-5",
  "models": {
    "anthropic/claude-sonnet-4-5": {}
  },
  "providers": {}
}
EOF
            echo -e "${GREEN}Created default profiles${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}Initialization complete!${NC}"
    echo -e "Run '$(basename "$0")' to see available profiles."
}

# Apply a model profile
apply_profile() {
    local profile_name="$1"
    local profile_file="$MODELS_DIR/${profile_name}.json"

    if [[ ! -f "$profile_file" ]]; then
        echo -e "${RED}Error: Profile '$profile_name' not found${NC}"
        echo "Available profiles:"
        ls -1 "$MODELS_DIR"/*.json 2>/dev/null | xargs -n1 basename | sed 's/.json$//' | sed 's/^/  /'
        exit 1
    fi

    # Sync base.json with any manual changes to openclaw.json
    sync_base_config

    if [[ ! -f "$BASE_CONFIG" ]]; then
        echo -e "${RED}Error: Base config not found at $BASE_CONFIG${NC}"
        echo "Run with --init to set up the profile system."
        exit 1
    fi

    echo -e "Switching to profile: ${CYAN}$profile_name${NC}"

    # Read profile data
    local primary=$(jq -r '.primary' "$profile_file")
    local models=$(jq '.models // {}' "$profile_file")
    local providers=$(jq '.providers // {}' "$profile_file")
    local display_name=$(jq -r '.name // "Unknown"' "$profile_file")

    # Merge base config with profile
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    jq --arg primary "$primary" \
       --argjson models "$models" \
       --argjson providers "$providers" \
       --arg timestamp "$timestamp" '
       .meta.lastTouchedAt = $timestamp |
       .agents.defaults.model.primary = $primary |
       .agents.defaults.models = $models |
       if ($providers | length) > 0 then
         .models = {
           "mode": "merge",
           "providers": $providers
         }
       else
         del(.models)
       end
    ' "$BASE_CONFIG" > "$OUTPUT_CONFIG.tmp"

    # Validate JSON before replacing
    if jq empty "$OUTPUT_CONFIG.tmp" 2>/dev/null; then
        mv "$OUTPUT_CONFIG.tmp" "$OUTPUT_CONFIG"
        echo "$profile_name" > "$CURRENT_MODEL_FILE"
        echo -e "${GREEN}Successfully switched to $display_name${NC}"
        echo -e "Primary model: ${CYAN}$primary${NC}"

        # Check if gateway is running
        if command -v lsof &> /dev/null && lsof -i :18789 &>/dev/null; then
            echo ""
            echo -e "${YELLOW}Note: Gateway is running. Restart it for changes to take effect.${NC}"
            echo "  Run: openclaw gateway restart"
        fi
    else
        echo -e "${RED}Error: Generated config is invalid${NC}"
        rm -f "$OUTPUT_CONFIG.tmp"
        exit 1
    fi
}

# Show help
show_help() {
    echo "OpenClaw Model Profile Switcher"
    echo ""
    echo "A utility for managing multiple model configurations. Allows quick"
    echo "switching between AI models while preserving your base config."
    echo ""
    echo "Usage:"
    echo "  $(basename "$0")                Show current config and available profiles"
    echo "  $(basename "$0") <profile>      Switch to a model profile"
    echo "  $(basename "$0") --list         List available profiles"
    echo "  $(basename "$0") --sync         Sync base.json with openclaw.json changes"
    echo "  $(basename "$0") --init         Initialize the profile system"
    echo "  $(basename "$0") --help         Show this help message"
    echo ""
    echo "Auto-sync:"
    echo "  When switching profiles, any manual changes to openclaw.json"
    echo "  (new skills, channels, etc.) are automatically detected and"
    echo "  merged into base.json. Old base.json is backed up with timestamp."
    echo ""
    echo "Environment:"
    echo "  OPENCLAW_MODEL  Set to auto-apply a profile"
    echo "  OPENCLAW_DIR    Override config directory (default: ~/.openclaw)"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") opus-4.5       Switch to Claude Opus 4.5"
    echo "  $(basename "$0") ollama-local   Switch to local Ollama model"
    echo ""
    echo "For more information, see the README in the contrib/model-profiles directory."
}

# Main
main() {
    check_dependencies

    # Check for environment variable override
    if [[ -n "$OPENCLAW_MODEL" && -z "$1" ]]; then
        echo -e "${YELLOW}Using OPENCLAW_MODEL environment variable: $OPENCLAW_MODEL${NC}"
        apply_profile "$OPENCLAW_MODEL"
        exit 0
    fi

    case "${1:-}" in
        "")
            show_status
            echo ""
            list_profiles
            echo -e "${BOLD}Usage:${NC} $(basename "$0") <profile-name>"
            echo -e "Run with --help for more options."
            ;;
        --list|-l)
            list_profiles
            ;;
        --sync|-s)
            echo -e "${BOLD}Syncing base.json with current config...${NC}"
            sync_base_config
            echo -e "${GREEN}Sync complete.${NC}"
            ;;
        --init|-i)
            init_profiles
            ;;
        --help|-h)
            show_help
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run with --help for usage information."
            exit 1
            ;;
        *)
            apply_profile "$1"
            ;;
    esac
}

main "$@"
