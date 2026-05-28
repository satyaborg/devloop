import {
  isIsolatedWorktree,
  LOGO,
  resultPath,
  type Result,
} from "./devloop.ts";

export type Row = { id: string; title: string; status: "run" | "ok" | "fail"; detail: string; lines: string[]; open: boolean };
const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

export function view(rows: Row[], selected: number, result?: Result, spinnerFrame = 0) {
  const body = rows.flatMap((item, i) => {
    const mark = i === selected ? ">" : " ";
    const fold = item.lines.length ? (item.open ? "[-]" : "[+]") : "   ";
    const head = `${mark} ${icon(item.status, spinnerFrame)} ${fold} ${item.title} - ${item.detail}`;
    return item.open ? [head, ...item.lines.slice(-80).map((line) => `      ${line}`)] : [head];
  });
  const tail = result
    ? [
        "",
        resultLine("result", result.status),
        resultLine("passes", `${result.passes} / ${result.max}`),
        resultLine("coder", result.coder),
        resultLine("reviewer", result.reviewer),
        resultLine("branch", result.branch),
        resultLine("commit", result.commit || "none"),
        ...(result.pullRequest ? [resultLine("pr", result.pullRequest)] : []),
        ...(isIsolatedWorktree(result) ? [resultLine("worktree", result.worktree)] : []),
        resultLine("report", resultPath(result, result.report)),
        resultLine("track", resultPath(result, result.track)),
      ]
    : ["", "enter toggles logs, ↑/↓ moves"];
  return [LOGO, "", ...body, ...tail].join("\n");
}

function resultLine(label: string, value: string) {
  return `${`${label}:`.padEnd(10)}${value}`;
}

function icon(status: Row["status"], spinnerFrame: number) {
  if (status === "ok") return "ok";
  if (status === "fail") return "!!";
  return SPINNER_FRAMES[Math.abs(spinnerFrame) % SPINNER_FRAMES.length]!;
}
