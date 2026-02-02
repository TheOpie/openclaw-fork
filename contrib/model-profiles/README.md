# OpenClaw Model Profile Switcher

A utility for managing multiple model configurations in OpenClaw. Quickly switch between different AI models (Anthropic Claude, Ollama, OpenAI, etc.) while preserving your base configuration.

## Features

- **Quick model switching** - Change models with a single command
- **Config preservation** - Base settings (skills, channels, hooks) are preserved across switches
- **Auto-sync** - Manual changes to `openclaw.json` are automatically detected and merged
- **Backup protection** - Old configurations are backed up with timestamps before changes
- **Multiple providers** - Support for Anthropic, Ollama, OpenAI, and custom providers

## Installation

### Quick Install

```bash
# Copy the script to your PATH
cp openclaw-model-switch.sh ~/.local/bin/openclaw-model-switch
chmod +x ~/.local/bin/openclaw-model-switch

# Initialize the profile system
openclaw-model-switch --init
```

### With Shell Aliases (Recommended)

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Model switching aliases
alias ocm="~/.local/bin/openclaw-model-switch"
alias ocm-opus="openclaw-model-switch opus-4.5"
alias ocm-sonnet="openclaw-model-switch sonnet-4.5"
alias ocm-ollama="openclaw-model-switch ollama-local"
```

Then reload: `source ~/.bashrc`

## Usage

```bash
# Show current model and available profiles
openclaw-model-switch

# Switch to a specific profile
openclaw-model-switch opus-4.5
openclaw-model-switch sonnet-4.5
openclaw-model-switch ollama-local

# List all available profiles
openclaw-model-switch --list

# Manually sync base.json with config changes
openclaw-model-switch --sync

# Initialize/reset the profile system
openclaw-model-switch --init

# Show help
openclaw-model-switch --help
```

## How It Works

### Directory Structure

After initialization, your `~/.openclaw/config/` will contain:

```
~/.openclaw/
├── openclaw.json           # Active config (generated)
└── config/
    ├── base.json           # Shared settings (skills, channels, hooks, etc.)
    ├── .current-model      # Tracks which profile is active
    └── models/
        ├── opus-4.5.json   # Claude Opus 4.5 profile
        ├── sonnet-4.5.json # Claude Sonnet 4.5 profile
        └── ollama-local.json # Local Ollama profile
```

### Config Merging

When you switch profiles, the script:

1. **Checks for changes** - Compares current `openclaw.json` with `base.json`
2. **Backs up if needed** - Creates `base.json.YYYY-MM-DD_HHMMSS.bak`
3. **Updates base.json** - Preserves any manual changes (new skills, etc.)
4. **Merges configs** - Combines `base.json` + selected model profile
5. **Writes openclaw.json** - Generates the final config

### What's in Each File

**base.json** - Everything except model-specific settings:
- Authentication profiles
- Skills configuration
- Channel settings (Slack, etc.)
- Hooks and plugins
- Gateway configuration

**Model profiles** - Only model-specific settings:
- Primary model ID
- Available models
- Provider configuration (for Ollama, etc.)

## Creating Custom Profiles

Create a new JSON file in `~/.openclaw/config/models/`:

```json
{
  "name": "My Custom Model",
  "description": "Description shown in the profile list",
  "primary": "provider/model-id",
  "models": {
    "provider/model-id": {}
  },
  "providers": {}
}
```

### Anthropic Example

```json
{
  "name": "Claude Opus 4.5",
  "description": "Latest flagship model",
  "primary": "anthropic/claude-opus-4-5",
  "models": {
    "anthropic/claude-opus-4-5": {}
  },
  "providers": {}
}
```

### Ollama Example

```json
{
  "name": "Ollama Mistral",
  "description": "Local Mistral model via Ollama",
  "primary": "ollama/mistral:latest",
  "models": {},
  "providers": {
    "ollama": {
      "baseUrl": "http://127.0.0.1:11434/v1",
      "apiKey": "ollama-local",
      "api": "openai-responses",
      "models": [
        {
          "id": "mistral:latest",
          "name": "Mistral",
          "reasoning": false,
          "input": ["text"],
          "cost": { "input": 0, "output": 0 },
          "contextWindow": 32768,
          "maxTokens": 8192
        }
      ]
    }
  }
}
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENCLAW_MODEL` | Auto-apply this profile when running without arguments |
| `OPENCLAW_DIR` | Override config directory (default: `~/.openclaw`) |

Example:
```bash
export OPENCLAW_MODEL="opus-4.5"
openclaw-model-switch  # Will automatically switch to opus-4.5
```

## After Switching

The gateway needs to be restarted for model changes to take effect:

```bash
openclaw gateway restart
```

The script will remind you if the gateway is running.

## Troubleshooting

### "Profile not found"
Make sure the profile JSON file exists in `~/.openclaw/config/models/`

### "Base config not found"
Run `openclaw-model-switch --init` to set up the profile system

### "jq is required"
Install jq: `sudo apt install jq` (Debian/Ubuntu) or `brew install jq` (macOS)

### Changes not taking effect
Restart the gateway: `openclaw gateway restart`

## Testing

A test script is included to verify the functionality:

```bash
./test-model-switch.sh
```

This runs in a temporary directory and doesn't affect your actual configuration.

## Contributing

Found a bug or want to improve this utility?

1. Fork the OpenClaw repository
2. Make your changes in `contrib/model-profiles/`
3. Submit a pull request

## License

Same license as OpenClaw (see repository root).
