#!/usr/bin/env bun
import { chmod, mkdir, readlink, rm, symlink } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const cli = path.join(root, "src", "cli.ts");
const binDir = process.env.DEVLOOP_BIN_DIR ?? path.join(homedir(), ".local", "bin");
const link = path.join(binDir, "devloop");

await run(["bun", "install"], root);
await mkdir(binDir, { recursive: true });
await chmod(cli, 0o755);

const existing = await readlink(link).catch(() => "");
if (existing && path.resolve(binDir, existing) === cli) {
  console.log(`devloop already points to ${cli}`);
} else {
  await rm(link, { force: true });
  await symlink(cli, link);
  console.log(`installed devloop -> ${cli}`);
}

if (!pathInEnv(binDir)) {
  console.log("");
  console.log(`${binDir} is not on PATH. Add this to ~/.zshrc:`);
  console.log(`export PATH="${binDir}:$PATH"`);
}

console.log("");
console.log("try: devloop --help");

async function run(cmd: string[], cwd: string) {
  const proc = Bun.spawn(cmd, { cwd, stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) process.exit(code);
}

function pathInEnv(dir: string) {
  return (process.env.PATH ?? "").split(path.delimiter).some((entry) => path.resolve(entry) === dir);
}
