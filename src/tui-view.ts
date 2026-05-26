import { LOGO, type Result } from "./devloop.ts";

export type Row = { id: string; title: string; status: "run" | "ok" | "fail"; detail: string; lines: string[]; open: boolean };

export function view(rows: Row[], selected: number, result?: Result) {
  const body = rows.flatMap((item, i) => {
    const mark = i === selected ? ">" : " ";
    const fold = item.lines.length ? (item.open ? "[-]" : "[+]") : "   ";
    const head = `${mark} ${icon(item.status)} ${fold} ${item.title} - ${item.detail}`;
    return item.open ? [head, ...item.lines.slice(-80).map((line) => `      ${line}`)] : [head];
  });
  const tail = result
    ? [
        "",
        `result:  ${result.status}`,
        `passes:  ${result.passes} / ${result.max}`,
        `branch:  ${result.branch}`,
        `commit:  ${result.commit || "none"}`,
        `worktree: ${result.worktree}`,
        `report:  ${result.report}`,
        `track:   ${result.track}`,
      ]
    : ["", "enter toggles logs, j/k moves"];
  return [LOGO, "", ...body, ...tail].join("\n");
}

function icon(status: Row["status"]) {
  return status === "ok" ? "ok" : status === "fail" ? "!!" : "..";
}
