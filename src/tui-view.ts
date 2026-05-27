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
        `result:  ${result.status}`,
        `passes:  ${result.passes} / ${result.max}`,
        `branch:  ${result.branch}`,
        `commit:  ${result.commit || "none"}`,
        ...(isIsolatedWorktree(result) ? [`worktree: ${result.worktree}`] : []),
        `report:  ${resultPath(result, result.report)}`,
        `track:   ${resultPath(result, result.track)}`,
      ]
    : ["", "enter toggles logs, ↑/↓ moves"];
  return [LOGO, "", ...body, ...tail].join("\n");
}

function icon(status: Row["status"], spinnerFrame: number) {
  if (status === "ok") return "ok";
  if (status === "fail") return "!!";
  return SPINNER_FRAMES[Math.abs(spinnerFrame) % SPINNER_FRAMES.length]!;
}
