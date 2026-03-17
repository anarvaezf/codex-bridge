require("dotenv").config();

const express = require("express");
const { execFile } = require("child_process");
const path = require("path");
const fs = require("fs");
const os = require("os");

const app = express();

app.use(express.json({ limit: "5mb" }));

const PROJECT_ROOT = process.env.CODEX_BRIDGE_ROOT || path.resolve(__dirname);

const AGENTS_DIR =
  process.env.AGENTS_DIR || path.join(PROJECT_ROOT, "agents");

const CONTEXTS_DIR =
  process.env.CONTEXTS_DIR || path.join(PROJECT_ROOT, "contexts");

const TEMP_WORKSPACES_DIR =
  process.env.TEMP_WORKSPACES_DIR ||
  path.join(PROJECT_ROOT, "temp-workspaces");

const BASE_AGENT_FILE = path.join(AGENTS_DIR, "_base.md");

const CODEX_TIMEOUT = Number(process.env.CODEX_TIMEOUT || 60000);
const MAX_BUFFER = 1024 * 1024 * 10;
const PORT = Number(process.env.PORT || 8787);

function ensureDirectory(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function ensureFileExists(filePath, description) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`${description} not found: ${filePath}`);
  }
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidInputType(value) {
  return (
    typeof value === "string" ||
    Array.isArray(value) ||
    isPlainObject(value)
  );
}

function isValidAgentName(agent) {
  return typeof agent === "string" && /^[a-z0-9-]+$/.test(agent);
}

function buildAgentFilePath(agent) {
  return path.join(AGENTS_DIR, `${agent}.md`);
}

function readFileOrThrow(filePath, description) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`${description} not found`);
  }

  return fs.readFileSync(filePath, "utf8");
}

/**
 * -------- CONTEXTS --------
 */

function isValidContextPath(contextPath) {
  if (typeof contextPath !== "string") return false;
  if (contextPath.startsWith("/")) return false;
  if (contextPath.includes("..")) return false;
  return true;
}

function resolveContextFilePath(contextPath) {
  const fullPath = path.resolve(CONTEXTS_DIR, contextPath);

  if (!fullPath.startsWith(path.resolve(CONTEXTS_DIR))) {
    throw new Error(`Invalid context path: ${contextPath}`);
  }

  return fullPath;
}

function readContextsOrThrow(contexts) {
  if (!Array.isArray(contexts)) {
    throw new Error("contexts must be an array");
  }

  const seen = new Set();

  return contexts.map((ctx) => {
    if (!isValidContextPath(ctx)) {
      throw new Error(`Invalid context path: ${ctx}`);
    }

    if (seen.has(ctx)) {
      throw new Error(`Duplicate context: ${ctx}`);
    }

    seen.add(ctx);

    const filePath = resolveContextFilePath(ctx);

    if (!fs.existsSync(filePath)) {
      throw new Error(`Context file not found: ${ctx}`);
    }

    return fs.readFileSync(filePath, "utf8");
  });
}

/**
 * -------- AGENTS COMPOSITION --------
 * Order:
 * 1. _base.md
 * 2. contexts
 * 3. agent
 */

function buildRuntimeAgentsContent({
  baseContent,
  contextContents,
  agentContent,
}) {
  const sections = [
    baseContent.trim(),
    ...contextContents.map((c) => c.trim()),
    agentContent.trim(),
  ];

  return `${sections.join("\n\n")}\n`;
}

/**
 * -------- PROMPT --------
 */

function buildPrompt(input) {
  if (typeof input === "string") {
    return [
      "Process the following input according to the active agent instructions.",
      "Return only the required JSON output.",
      "",
      "INPUT_TYPE: string",
      "INPUT:",
      input,
    ].join("\n");
  }

  return [
    "Process the following input according to the active agent instructions.",
    "Return only the required JSON output.",
    "",
    `INPUT_TYPE: ${Array.isArray(input) ? "array" : "object"}`,
    "INPUT_JSON:",
    JSON.stringify(input, null, 2),
  ].join("\n");
}

/**
 * -------- OUTPUT PARSING --------
 */

function extractCodexResult(stdout) {
  if (!stdout) return "";

  const normalized = stdout.replace(/\r\n/g, "\n");

  const codexLineRegex = /^\[[^\]]+\]\s+codex\s*$/m;
  const codexMatch = normalized.match(codexLineRegex);

  if (!codexMatch || codexMatch.index === undefined) {
    return normalized.trim();
  }

  const afterCodex = normalized.slice(codexMatch.index + codexMatch[0].length);

  const tokensRegex = /^\[[^\]]+\]\s+tokens used:.*$/m;
  const tokensMatch = afterCodex.match(tokensRegex);

  const result =
    tokensMatch && tokensMatch.index !== undefined
      ? afterCodex.slice(0, tokensMatch.index)
      : afterCodex;

  return result.trim();
}

function parseAgentJson(resultText) {
  try {
    return JSON.parse(resultText);
  } catch {
    throw new Error("Agent output is not valid JSON");
  }
}

function validateAgentOutput(parsedOutput) {
  if (!isPlainObject(parsedOutput)) {
    throw new Error("Agent output must be a JSON object");
  }

  const hasResult = Object.prototype.hasOwnProperty.call(parsedOutput, "result");
  const hasError = Object.prototype.hasOwnProperty.call(parsedOutput, "error");

  if (!hasResult && !hasError) {
    throw new Error("Agent output must contain either 'result' or 'error'");
  }

  if (hasResult && hasError) {
    throw new Error("Agent output cannot contain both 'result' and 'error'");
  }

  if (hasError && typeof parsedOutput.error !== "string") {
    throw new Error("Agent output field 'error' must be a string");
  }

  return parsedOutput;
}

/**
 * -------- RESPONSES --------
 */

function buildSuccessResponse(agent, result, debug, debugData) {
  if (!debug) {
    return { result };
  }

  return {
    result,
    debug: {
      agent,
      raw: debugData.raw,
      stderr: debugData.stderr,
      durationMs: debugData.durationMs,
    },
  };
}

function buildErrorResponse(errorMessage, agent, debug, debugData = {}) {
  if (!debug) {
    return { error: errorMessage };
  }

  return {
    error: errorMessage,
    debug: {
      agent,
      raw: debugData.raw ?? "",
      stderr: debugData.stderr ?? "",
      durationMs: debugData.durationMs ?? null,
    },
  };
}

function cleanupWorkspace(workspacePath) {
  if (workspacePath && fs.existsSync(workspacePath)) {
    fs.rmSync(workspacePath, { recursive: true, force: true });
  }
}

function validateStartupPaths() {
  ensureDirectory(TEMP_WORKSPACES_DIR);
  ensureDirectory(AGENTS_DIR);
  ensureDirectory(CONTEXTS_DIR);
  ensureFileExists(BASE_AGENT_FILE, "Base agent file");
}

validateStartupPaths();

/**
 * -------- ROUTE --------
 */

app.post("/run-codex", (req, res) => {
  let workspacePath = null;
  let hasResponded = false;
  const startedAt = Date.now();

  try {
    const { agent, input, contexts = [], options } = req.body ?? {};
    const debug = Boolean(options?.debug);

    if (!isValidAgentName(agent)) {
      return res.status(400).json(
        buildErrorResponse("Invalid or missing agent", agent ?? null, debug)
      );
    }

    if (!isValidInputType(input)) {
      return res.status(400).json(
        buildErrorResponse(
          "Invalid or missing input. Supported types: string, object, array",
          agent,
          debug
        )
      );
    }

    const agentFilePath = buildAgentFilePath(agent);

    const baseContent = readFileOrThrow(BASE_AGENT_FILE, "Base agent file");
    const agentContent = readFileOrThrow(agentFilePath, "Agent file");

    const contextContents = contexts.length
      ? readContextsOrThrow(contexts)
      : [];

    const combinedAgentsContent = buildRuntimeAgentsContent({
      baseContent,
      contextContents,
      agentContent,
    });

    workspacePath = fs.mkdtempSync(
      path.join(TEMP_WORKSPACES_DIR, "codex-bridge-")
    );

    const runtimeAgentsFilePath = path.join(workspacePath, "AGENTS.md");
    fs.writeFileSync(runtimeAgentsFilePath, combinedAgentsContent, "utf8");

    const prompt = buildPrompt(input);

    const child = execFile(
      "codex",
      ["exec", "--skip-git-repo-check", prompt],
      {
        cwd: workspacePath,
        maxBuffer: MAX_BUFFER,
      },
      (error, stdout, stderr) => {
        if (hasResponded) {
          cleanupWorkspace(workspacePath);
          return;
        }

        hasResponded = true;
        clearTimeout(timeout);

        const durationMs = Date.now() - startedAt;
        const raw = stdout ?? "";
        const cleanedResult = extractCodexResult(raw);

        if (error) {
          cleanupWorkspace(workspacePath);

          return res.status(500).json(
            buildErrorResponse("Codex execution failed", agent, debug, {
              raw,
              stderr: stderr ?? "",
              durationMs,
            })
          );
        }

        let parsedOutput;

        try {
          parsedOutput = parseAgentJson(cleanedResult);
          parsedOutput = validateAgentOutput(parsedOutput);
        } catch (parseError) {
          cleanupWorkspace(workspacePath);

          return res.status(500).json(
            buildErrorResponse(parseError.message, agent, debug, {
              raw,
              stderr: stderr ?? "",
              durationMs,
            })
          );
        }

        cleanupWorkspace(workspacePath);

        if (Object.prototype.hasOwnProperty.call(parsedOutput, "error")) {
          return res.status(400).json(
            buildErrorResponse(parsedOutput.error, agent, debug, {
              raw,
              stderr: stderr ?? "",
              durationMs,
            })
          );
        }

        return res.json(
          buildSuccessResponse(agent, parsedOutput.result, debug, {
            raw,
            stderr: stderr ?? "",
            durationMs,
          })
        );
      }
    );

    const timeout = setTimeout(() => {
      if (hasResponded) {
        cleanupWorkspace(workspacePath);
        return;
      }

      hasResponded = true;
      child.kill("SIGKILL");

      cleanupWorkspace(workspacePath);

      return res.status(500).json(
        buildErrorResponse("Codex execution timeout", agent, debug, {
          raw: "",
          stderr: "",
          durationMs: Date.now() - startedAt,
        })
      );
    }, CODEX_TIMEOUT);
  } catch (err) {
    cleanupWorkspace(workspacePath);

    const agent = req.body?.agent ?? null;
    const debug = Boolean(req.body?.options?.debug);

    return res.status(500).json(
      buildErrorResponse(err.message, agent, debug)
    );
  }
});

/**
 * -------- HEALTH --------
 */

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "codex-bridge",
    host: os.hostname(),
    projectRoot: PROJECT_ROOT,
    agentsDir: AGENTS_DIR,
    contextsDir: CONTEXTS_DIR,
    tempWorkspacesDir: TEMP_WORKSPACES_DIR,
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Codex bridge listening on http://0.0.0.0:${PORT}`);
  console.log(`Project root: ${PROJECT_ROOT}`);
  console.log(`Agents directory: ${AGENTS_DIR}`);
  console.log(`Contexts directory: ${CONTEXTS_DIR}`);
  console.log(`Temp workspaces directory: ${TEMP_WORKSPACES_DIR}`);
});