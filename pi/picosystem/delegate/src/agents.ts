import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { getAgentDir, parseFrontmatter, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { resolvePreloadedSkills, type PreloadedSkill } from "./skills.ts";

export interface Agent {
  name: string;
  description: string;
  tools: string[];
  extensions: string[];
  skills: string[];
  model?: string;
  thinking?: string;
  systemPrompt: string;
  source: string;
}

/** Everything a worker needs, saved in meta.json so a continue reuses it as is. */
export interface Loadout {
  agent: string;
  tools: string[];
  extensions: string[];
  systemPrompt: string;
  skills: PreloadedSkill[];
  model?: string;
  thinking: string;
  cwd: string;
  approveProject: boolean;
}

export const NAME = /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$/;
const KEYS = new Set(["name", "description", "tools", "extensions", "skills", "model", "thinking"]);
const THINKING = new Set(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);
const BUILTIN_TOOLS = new Set(["read", "bash", "edit", "write", "grep", "find", "ls", "powershell"]);
const bundledDir = fileURLToPath(new URL("../agents/", import.meta.url));
const expandHome = (path: string) => (path.startsWith("~/") ? join(homedir(), path.slice(2)) : path);

function list(value: unknown, field: string): string[] {
  const raw = typeof value === "string" ? value.split(",") : value;
  if (!Array.isArray(raw) || raw.some((item) => typeof item !== "string" || !item.trim())) {
    throw new Error(`${field} must be a comma-separated string or an array of nonempty strings`);
  }
  return [...new Set(raw.map((item: string) => item.trim()))];
}

function optionalString(value: unknown, field: string): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !value.trim()) throw new Error(`${field} must be a nonempty string`);
  return value.trim();
}

export function parseAgent(content: string, file: string): Agent {
  const { frontmatter: f, body } = parseFrontmatter<Record<string, unknown>>(content);
  // An ignored key such as an old `isolation: worktree` would quietly change what the worker may do.
  const unknown = Object.keys(f).filter((key) => !KEYS.has(key));
  if (unknown.length) throw new Error(`Unknown key${unknown.length > 1 ? "s" : ""}: ${unknown.join(", ")}`);
  const name = optionalString(f.name, "name");
  const description = optionalString(f.description, "description");
  if (!name || !NAME.test(name) || !description) throw new Error("A valid name and description are required");
  const tools = list(f.tools, "tools");
  if (!tools.length) throw new Error("tools must not be empty");
  const thinking = optionalString(f.thinking, "thinking");
  if (thinking && !THINKING.has(thinking)) throw new Error(`Invalid thinking level: ${thinking}`);
  return {
    name, description, tools,
    extensions: f.extensions === undefined ? [] : list(f.extensions, "extensions").map((p) =>
      p.startsWith("builtin:") ? p : resolve(dirname(file), expandHome(p))),
    skills: f.skills === undefined ? [] : list(f.skills, "skills"),
    model: optionalString(f.model, "model"),
    thinking,
    systemPrompt: body.trim(),
    source: file,
  };
}

/** The nearest `.pi/<name>` directory at or above cwd, never the global agent home's parent (~/.pi). */
function nearestProjectDir(cwd: string, name: string): string | undefined {
  const globalPi = resolve(getAgentDir(), "..");
  for (let current = resolve(cwd); ; current = dirname(current)) {
    const path = join(current, ".pi", name);
    if (resolve(current, ".pi") !== globalPi && existsSync(path) && statSync(path).isDirectory()) return path;
    if (dirname(current) === current) return undefined;
  }
}

/** Bundled, then global, then the nearest trusted project's profiles; a later file with the same name wins. */
export function discoverAgents(cwd: string, trusted: boolean): { agents: Agent[]; warnings: string[] } {
  const agents = new Map<string, Agent>();
  const warnings: string[] = [];
  const project = trusted ? nearestProjectDir(cwd, "agents") : undefined;
  for (const dir of [bundledDir, join(getAgentDir(), "agents"), ...(project ? [project] : [])]) {
    if (!existsSync(dir)) continue;
    for (const name of readdirSync(dir).filter((n) => n.endsWith(".md")).sort()) {
      const file = join(dir, name);
      try {
        const agent = parseAgent(readFileSync(file, "utf8"), file);
        agents.set(agent.name, agent);
      } catch (error) {
        // A broken override must not fall back to the less restricted profile it replaces.
        agents.delete(name.slice(0, -3));
        warnings.push(`${file}: ${error instanceof Error ? error.message : error}`);
      }
    }
  }
  return { agents: [...agents.values()], warnings };
}

export function resolveLoadout(agent: Agent, pi: ExtensionAPI, ctx: ExtensionContext, cwdOverride?: string, modelOverride?: string): Loadout {
  const extensions = new Set(agent.extensions);
  const known = new Map(pi.getAllTools().map((tool) => [tool.name, tool]));
  for (const name of agent.tools) {
    if (name.startsWith("subagent")) throw new Error(`${agent.source}: workers cannot use '${name}'; subagents do not nest.`);
    if (BUILTIN_TOOLS.has(name)) continue;
    const source = known.get(name)?.sourceInfo.path;
    if (!source) {
      if (agent.extensions.length) continue; // The worker checks tools from explicit extensions when it loads them.
      throw new Error(`Tool '${name}' is unavailable. Load its extension in the parent or list extensions in ${agent.source}.`);
    }
    if (source.startsWith("builtin:") || isAbsolute(source)) extensions.add(source);
    else throw new Error(`Cannot load '${name}' from ${source} in a worker. List its extension file in ${agent.source}.`);
  }
  const cwd = resolve(ctx.cwd, expandHome(cwdOverride ?? ctx.cwd));
  if (!existsSync(cwd) || !statSync(cwd).isDirectory()) throw new Error(`Not a directory: ${cwd}`);
  return {
    agent: agent.name,
    tools: agent.tools,
    extensions: [...extensions],
    systemPrompt: agent.systemPrompt,
    skills: resolvePreloadedSkills(agent.skills, pi, ctx),
    model: modelOverride ?? agent.model ?? (ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined),
    thinking: agent.thinking ?? ctx.thinkingLevel ?? pi.getThinkingLevel(),
    cwd,
    // Never trust a different directory just because the parent's is trusted.
    approveProject: cwd === resolve(ctx.cwd) && ctx.isProjectTrusted(),
  };
}
