import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const root = path.resolve(import.meta.dir, "..");
const npmCache = await mkdtemp(path.join(tmpdir(), "devloop-npm-cache."));

afterAll(async () => rm(npmCache, { recursive: true, force: true }));

describe("npm package readiness", () => {
  test("declares public package metadata for the scoped npm package", async () => {
    const pkg = await packageJson();

    expect(pkg.name).toBe("@satyaborg/devloop");
    expect(pkg.bin).toEqual({ devloop: "./src/cli.ts" });
    expect(pkg.description).toBe("Spec-driven code and review loop with Codex and Claude Code.");
    expect(pkg.license).toBe("MIT");
    expect(pkg.author).toEqual({ name: "@satyaborg", url: "https://satyaborg.com" });
    expect(pkg.repository).toEqual({ type: "git", url: "git+https://github.com/satyaborg/devloop.git" });
    expect(pkg.bugs).toEqual({ url: "https://github.com/satyaborg/devloop/issues" });
    expect(pkg.homepage).toBe("https://github.com/satyaborg/devloop#readme");
    expect(pkg.keywords).toEqual(expect.arrayContaining(["agent", "codex", "claude", "cli", "devloop"]));
    expect(pkg.packageManager).toMatch(/^bun@\d+\.\d+\.\d+$/);
    expect(pkg.engines).toEqual({ bun: ">=1.2.0" });
    expect(pkg.publishConfig).toEqual({ access: "public" });
  });

  test("allows only runtime package files into the packed tarball", async () => {
    const pkg = await packageJson();

    expect(pkg.files).toEqual([
      "src",
      "skills/spec/SKILL.md",
      "templates/spec.md",
      "README.md",
      "LICENSE",
    ]);

    const paths = await dryRunPackFiles();
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
      expect(paths).toContain(required);
    }

    for (const forbidden of [
      "AGENTS.md",
      "bunfig.toml",
      "tsconfig.json",
      "scripts/install.ts",
    ]) {
      expect(paths).not.toContain(forbidden);
    }

    for (const prefix of ["tests/", "coverage/", ".codex/", ".specs/", ".github/"]) {
      expect(paths.some((item) => item.startsWith(prefix))).toBe(false);
    }
  });
});

describe("release readiness documentation", () => {
  test("documents public install paths, badges, prerequisites, and security model", async () => {
    const readme = await readFile(path.join(root, "README.md"), "utf8");

    expect(readme).toContain("[![CI](https://github.com/satyaborg/devloop/actions/workflows/ci.yml/badge.svg)]");
    expect(readme).toContain("[![npm version](https://img.shields.io/npm/v/@satyaborg/devloop.svg)]");
    expect(readme).toContain("[![license](https://img.shields.io/npm/l/@satyaborg/devloop.svg)]");
    expect(readme).toContain("[![npm downloads](https://img.shields.io/npm/dm/@satyaborg/devloop.svg)]");
    expect(readme).toContain("npm install -g @satyaborg/devloop");
    expect(readme).toContain("bunx @satyaborg/devloop");
    expect(readme).toContain("`devloop` runs a local implementation and review loop");
    expect(readme).toContain("Prereqs:");
    expect(readme).toContain("Bun");
    expect(readme).toContain("bun scripts/install.ts");
    expect(readme).toContain("runs local agent CLIs against your checkout");
    expect(readme).toContain("Uses isolated sibling git worktrees by default");
    expect(readme).toContain("Writes tracks, reviews, reports, logs, session ids, and spec snapshots under `.codex/`");
    expect(readme).toContain("adds no telemetry");
  });

  test("documents release automation and first publish setup", async () => {
    const contributing = await readFile(path.join(root, "CONTRIBUTING.md"), "utf8");
    const security = await readFile(path.join(root, "SECURITY.md"), "utf8");

    expect(contributing).toContain("Conventional Commits");
    expect(contributing).toContain("Release Please");
    expect(contributing).toContain("CHANGELOG.md");
    expect(contributing).toContain("GitHub releases");
    expect(contributing).toContain("trusted publishing");
    expect(contributing).toContain("@satyaborg/devloop");
    expect(contributing).toContain("must be created or first-published by a maintainer");
    expect(contributing).toContain("publish.yml");
    expect(security).toContain("runs local agent CLIs with broad permissions");
    expect(security).toContain("does not add telemetry");
  });
});

describe("open source project files", () => {
  test("includes contributor, issue, pull request, CI, release, and publish files", async () => {
    for (const file of [
      "CONTRIBUTING.md",
      "SECURITY.md",
      "CODE_OF_CONDUCT.md",
      ".github/PULL_REQUEST_TEMPLATE.md",
      ".github/ISSUE_TEMPLATE/bug_report.yml",
      ".github/ISSUE_TEMPLATE/feature_request.yml",
      ".github/workflows/ci.yml",
      ".github/workflows/release.yml",
      ".github/workflows/publish.yml",
      "release-please-config.json",
      ".release-please-manifest.json",
      "CHANGELOG.md",
    ]) {
      expect(await exists(path.join(root, file))).toBe(true);
    }
  });

  test("runs CI, release, and publish workflows with the expected gates", async () => {
    const ci = await readFile(path.join(root, ".github/workflows/ci.yml"), "utf8");
    const release = await readFile(path.join(root, ".github/workflows/release.yml"), "utf8");
    const publish = await readFile(path.join(root, ".github/workflows/publish.yml"), "utf8");

    expect(ci).toContain("pull_request:");
    expect(ci).toContain("push:");
    expect(ci).toContain("branches: [main]");
    expect(ci).toContain("oven-sh/setup-bun");
    expect(ci).toContain("bun install --frozen-lockfile");
    expect(ci).toContain("bun run typecheck");
    expect(ci).toContain("bun test");
    expect(ci).toContain("npm --cache");
    expect(ci).toContain("pack --dry-run --json");
    expect(ci).toContain("bun run package:smoke");

    expect(release).toContain("googleapis/release-please-action");
    expect(release).toContain("release-type");
    expect(release).toContain("node");
    expect(release).toContain("CHANGELOG.md");

    expect(publish).toContain("workflow_run:");
    expect(publish).toContain("Release Please");
    expect(publish).toContain("id-token: write");
    expect(publish).toContain("bun run typecheck");
    expect(publish).toContain("bun test");
    expect(publish).toContain("bun run package:smoke");
    expect(publish).toContain("npm publish");
    expect(publish).not.toContain("NPM_TOKEN");
    expect(publish).not.toContain("NODE_AUTH_TOKEN");
  });
});

async function packageJson() {
  return JSON.parse(await readFile(path.join(root, "package.json"), "utf8")) as Record<string, unknown>;
}

async function dryRunPackFiles() {
  const output =
    await Bun.$`npm --cache ${npmCache} pack --dry-run --json`
      .cwd(root)
      .quiet()
      .text();
  const [pack] = JSON.parse(output) as Array<{ files: Array<{ path: string }> }>;
  return pack.files.map((file) => file.path).sort();
}

async function exists(file: string) {
  return Boolean(await stat(file).catch(() => false));
}
