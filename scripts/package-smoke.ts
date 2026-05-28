#!/usr/bin/env bun
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

type PackFile = { path: string };
type PackResult = {
  filename: string;
  files: PackFile[];
  name: string;
  version: string;
};

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const work = await mkdtemp(path.join(tmpdir(), "devloop-package-smoke."));
const cache = path.join(work, "npm-cache");
const packDir = path.join(work, "pack");
const prefix = path.join(work, "prefix");

try {
  await mkdir(packDir, { recursive: true });
  const output = await run(["npm", "--cache", cache, "pack", "--json", "--pack-destination", packDir], root);
  const [pack] = JSON.parse(output) as PackResult[];
  if (!pack) throw new Error("npm pack did not return package metadata");

  const paths = pack.files.map((file) => file.path).sort();
  for (const required of [
    "package.json",
    "README.md",
    "LICENSE",
    "src/cli.ts",
    "src/devloop.ts",
    "src/spec.ts",
    "src/tui.ts",
    "src/tui-view.ts",
    "skills/spec/SKILL.md",
    "templates/spec.md",
  ]) {
    if (!paths.includes(required)) throw new Error(`packed package is missing ${required}`);
  }

  for (const excluded of [
    "AGENTS.md",
    "bunfig.toml",
    "tsconfig.json",
    "scripts/install.ts",
  ]) {
    if (paths.includes(excluded)) throw new Error(`packed package includes ${excluded}`);
  }

  for (const excludedPrefix of ["tests/", "coverage/", ".codex/", ".specs/", ".github/"]) {
    const match = paths.find((item) => item.startsWith(excludedPrefix));
    if (match) throw new Error(`packed package includes ${match}`);
  }

  const tarball = path.join(packDir, pack.filename);
  await run(["npm", "--cache", cache, "install", "--global", tarball, "--prefix", prefix, "--no-audit", "--fund=false"], root);
  const help = await run([installedBin(prefix), "--help"], root);
  if (!help.includes("Common commands:")) throw new Error("installed devloop --help did not print CLI help");

  console.log(`package smoke passed: ${pack.name}@${pack.version}`);
} finally {
  await rm(work, { recursive: true, force: true });
}

async function run(cmd: string[], cwd: string) {
  const proc = Bun.spawn(cmd, {
    cwd,
    env: Bun.env,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (code !== 0)
    throw new Error(`${cmd.join(" ")} failed with ${code}\n${stdout}${stderr}`.trim());
  return stdout;
}

function installedBin(prefixDir: string) {
  return process.platform === "win32"
    ? path.join(prefixDir, "devloop.cmd")
    : path.join(prefixDir, "bin", "devloop");
}
