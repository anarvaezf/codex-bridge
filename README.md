# Codex Bridge

A lightweight local HTTP bridge to execute structured AI agents using Codex.

This project allows you to define reusable agents (`.md` files) and execute them through a simple API, making it ideal for automation workflows, integrations, and tooling.

---

## Features

- Run AI agents via HTTP
- Reusable agent definitions
- Structured JSON input/output
- Optional debug output (raw Codex response)
- Optional context injection per request
- Works with automation tools like n8n
- Cross-platform (macOS, Linux, Windows)

---

## Requirements

- Node.js (v18+ recommended)
- npm
- Codex CLI installed and authenticated

---

## Installation

### macOS / Linux

Run:

    ./install.sh

### Windows (PowerShell)

Run:

    .\install.ps1

The installer will guide you through the setup process and ask for configuration values.

---

## Build step (required for development)

Before running the installer, you must generate the runtime file:

    npm run build

This creates `server.min.js`, which is used during installation.

---

## What the installer does

- Copies only runtime files
- Installs npm dependencies
- Prompts for configuration values (with defaults)
- Generates a `.env` file
- Prepares required directories (`agents/`, `contexts/`, `temp-workspaces/`)

---

## Running the server

    cd codex-bridge
    npm start

---

## Health check

    curl http://localhost:8787/health

---

## Running an agent

Endpoint:

    POST /run-codex

---

## Supported input types

The `input` field supports:

- string
- object
- array

Each agent is responsible for validating the input format.

---

## Agent Output Contract

All agents MUST return a valid JSON object.

### Valid formats

    {
      "result": <any>
    }

OR

    {
      "error": "<string>"
    }

### Rules

- Must be valid JSON
- Must not include extra text
- Cannot include both `result` and `error`
- `error` must be a string

---

## Context system (NEW)

You can optionally inject context files into the execution.

### Request field

    "contexts": ["path/to/context.md"]

### Behavior

- Contexts are optional
- If omitted → only `_base.md` + agent are used
- If provided → contexts are injected before the agent
- Multiple contexts are supported
- Order matters

### Example

    {
      "agent": "tikiflow-issue-refiner",
      "contexts": [
        "tikiflow/tikiflow-context.md",
        "tikiflow/tikiflow-api-context.md"
      ],
      "input": {
        "taskType": ["api"],
        "parent": {
          "title": "Feature title",
          "body": "Feature description"
        },
        "child": {
          "title": "Task title",
          "body": "Task description"
        }
      }
    }

---

## Folder structure

    agents/
      _base.md
      greeter.md
      count-chars.md

    contexts/
      tikiflow/
        tikiflow-context.md
        tikiflow-api-context.md
        tikiflow-admin-context.md
        tikiflow-database-context.md

    temp-workspaces/

---

## Examples

### Greeter (object input)

Request:

    {
      "agent": "greeter",
      "input": {
        "person": "Arturo",
        "language": "spanish"
      }
    }

Response:

    {
      "result": "Hola Arturo"
    }

---

### Count chars (object input)

Request:

    {
      "agent": "count-chars",
      "input": {
        "text": "Codex Bridge is working"
      }
    }

Response:

    {
      "result": {
        "Codex": 5,
        "Bridge": 6,
        "is": 2,
        "working": 7
      }
    }

---

### Count chars (string input)

Request:

    {
      "agent": "count-chars",
      "input": "Hello world"
    }

Response:

    {
      "result": {
        "Hello": 5,
        "world": 5
      }
    }

---

## Debug mode

Request:

    {
      "agent": "count-chars",
      "input": {
        "text": "debug test"
      },
      "options": {
        "debug": true
      }
    }

Response:

    {
      "result": {
        "debug": 5,
        "test": 4
      },
      "debug": {
        "agent": "count-chars",
        "raw": "...",
        "stderr": "",
        "durationMs": 1234
      }
    }

---

## Agent system

Agents are defined as Markdown files inside the `agents/` folder.

### Base agent (`_base.md`)

Defines shared rules for all agents:

- Output format
- Constraints
- Common behavior

### Specific agents

Each file represents a specific behavior:

- `greeter.md`
- `count-chars.md`

---

## How it works

1. Loads `_base.md`
2. Loads context files (if provided)
3. Loads selected agent (e.g. `greeter.md`)
4. Combines everything into runtime `AGENTS.md`
5. Executes Codex
6. Parses structured JSON response

---

## Environment configuration

The installer generates a `.env` file.

    PORT=8787
    CODEX_BRIDGE_ROOT=
    AGENTS_DIR=
    CONTEXTS_DIR=
    TEMP_WORKSPACES_DIR=
    CODEX_TIMEOUT=60000

All values are optional.

---

## Common errors

### "invalid input"
Input type is not supported (must be string, object, or array)

### "missing required fields"
The agent requires specific fields

### "Agent output is not valid JSON"
The agent did not follow the JSON contract

### "Codex execution timeout"
Execution exceeded `CODEX_TIMEOUT`

---

## Limitations

- Executes Codex locally via CLI
- No authentication included
- Not intended for public exposure without protection
- Each request creates a temporary workspace

---

## Suggested use cases

- GitHub issue refinement
- Prompt standardization
- Content generation pipelines
- Data processing workflows
- AI automation with n8n
- CLI tooling and scripting
- Internal developer tools

---

## Notes

- `.env` is optional (defaults exist)
- `contexts` is optional per request
- `temp-workspaces/` is used at runtime
- Agents must strictly follow JSON contract
- The bridge is stateless

---

## License

MIT