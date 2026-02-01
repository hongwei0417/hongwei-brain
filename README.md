# Hongwei Brain Marketplace

A Claude Code plugin marketplace.

## Structure

```
hongwei-brain/
├── .claude-plugin/
│   └── marketplace.json    # Marketplace manifest
├── plugins/
│   └── example-plugin/
│       ├── .claude-plugin/
│       │   └── plugin.json # Plugin manifest
│       ├── skills/
│       │   └── example/
│       │       └── SKILL.md
│       ├── commands/
│       │   └── hello.md
│       └── agents/
│           └── example-agent.md
└── README.md
```

## Usage

### Add this marketplace locally

```shell
/plugin marketplace add .
```

### Install a plugin

```shell
/plugin install example-plugin@hongwei-marketplace
```

### Validate the marketplace

```bash
claude plugin validate .
```

## Adding New Plugins

1. Create a new directory under `plugins/`
2. Add `.claude-plugin/plugin.json` with plugin metadata
3. Add skills, commands, agents, hooks as needed
4. Update `marketplace.json` to include the new plugin

## Publishing

To share this marketplace:
1. Push to GitHub
2. Users can add with: `/plugin marketplace add owner/repo`
