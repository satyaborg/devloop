#!/usr/bin/env bun
import {
  isIsolatedWorktree,
  parseArgs,
  resultPath,
  runDevloop,
  welcome,
  type Event,
  type Sink,
} from "./devloop.ts";
import {
  bundledSpecSkillPath,
  generateSpec,
  parseSpecArgs,
  readBundledSpecSkill,
} from "./spec.ts";
import { createTuiSink } from "./tui.ts";

const argv = process.argv.slice(2);
if (argv[0] === "spec") await runSpecCommand(argv.slice(1));

if (argv.length === 0 || argv.includes("-h") || argv.includes("--help")) {
  console.log(welcome());
  process.exit(0);
}

const parsed = parseArgs(argv);

if (typeof parsed === "string") {
  console.error(parsed);
  process.exit(argv.includes("-h") || argv.includes("--help") ? 0 : 2);
}

const useTui = argv.includes("--tui") || (!argv.includes("--plain") && Boolean(process.stdout.isTTY));
const sink = useTui ? await createTuiSink() : plainSink();

try {
  const result = await runDevloop(parsed, sink);
  await sink.close?.();
  if (useTui) printResult(result);
  process.exit(result.status === "accepted" ? 0 : result.status === "stalled" || result.status === "max-turns" || result.status === "unclear" ? 1 : 2);
} catch (error) {
  await sink.close?.();
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(2);
}

function plainSink(): Sink {
  return {
    event(event: Event) {
      if (event.type === "step") console.error(`[devloop] ${event.title}`);
      else if (event.type === "done") console.error(`[devloop] ${event.detail}`);
      else if (event.type === "gate") console.error(`[devloop] ${event.name}: ${event.detail}`);
      else if (event.type === "result") printResult(event.result);
    },
  };
}

function printResult(result: {
  status: string;
  passes: number;
  max: number;
  report: string;
  track: string;
  worktree?: string;
  sourceRepo?: string;
}) {
  console.log("");
  console.log(`result:  ${result.status}`);
  console.log(`passes:  ${result.passes} / ${result.max}`);
  if ("branch" in result) console.log(`branch:  ${result.branch}`);
  if ("commit" in result) console.log(`commit:  ${result.commit || "none"}`);
  if (hasWorktreeInfo(result) && isIsolatedWorktree(result))
    console.log(`worktree: ${result.worktree}`);
  console.log(`report:  ${displayPath(result, result.report)}`);
  console.log(`track:   ${displayPath(result, result.track)}`);
}

function hasWorktreeInfo(result: {
  worktree?: string;
  sourceRepo?: string;
}): result is { worktree: string; sourceRepo: string } {
  return Boolean(result.worktree && result.sourceRepo);
}

function displayPath(
  result: { worktree?: string; sourceRepo?: string },
  file: string,
) {
  return hasWorktreeInfo(result) ? resultPath(result, file) : file;
}

async function runSpecCommand(argv: string[]) {
  const parsed = parseSpecArgs(argv);
  if (typeof parsed === "string") {
    const help = argv.includes("-h") || argv.includes("--help");
    console[help ? "log" : "error"](parsed);
    process.exit(help ? 0 : 2);
  }

  try {
    if (parsed.type === "print-skill") console.log(await readBundledSpecSkill());
    else if (parsed.type === "skill-path") console.log(bundledSpecSkillPath());
    else {
      const result = await generateSpec(parsed.options);
      console.log(`spec:  ${result.file}`);
      console.log(`agent: ${result.agent}`);
    }
    process.exit(0);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(2);
  }
}
