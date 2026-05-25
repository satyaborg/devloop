import type { Event, Result, Sink } from "./devloop.ts";

type Row = { id: string; title: string; status: "run" | "ok" | "fail"; detail: string; lines: string[]; open: boolean };

const LOGO = [
  "   ▐▌▗▞▀▚▖▄   ▄ █  ▄▄▄   ▄▄▄  ▄▄▄▄  ",
  "   ▐▌▐▛▀▀▘█   █ █ █   █ █   █ █   █ ",
  "▗▞▀▜▌▝▚▄▄▖ ▀▄▀  █ ▀▄▄▄▀ ▀▄▄▄▀ █▄▄▄▀ ",
  "▝▚▄▟▌           █             █     ",
  "                              ▀",
];

export async function createTuiSink(): Promise<Sink> {
  const { TextRenderable, createCliRenderer } = await import("@opentui/core");
  const renderer = await createCliRenderer({ exitOnCtrlC: true, consoleMode: "disabled", screenMode: "alternate-screen" });
  const text = new TextRenderable(renderer, { id: "devloop", width: "100%", height: "100%", content: "" });
  const rows: Row[] = [];
  let selected = 0;
  let result: Result | undefined;

  renderer.root.add(text);
  renderer.keyInput.on("keypress", (key) => {
    if (key.name === "up" || key.name === "k") selected = Math.max(0, selected - 1);
    else if (key.name === "down" || key.name === "j") selected = Math.min(rows.length - 1, selected + 1);
    else if (rows.length && (key.name === "return" || key.name === "space")) rows[selected]!.open = !rows[selected]!.open;
    render();
  });

  function render() {
    text.content = view(rows, selected, result);
    renderer.requestRender();
  }

  render();
  return {
    event(event: Event) {
      if (event.type === "step") rows.push({ id: event.id, title: event.title, status: "run", detail: "running", lines: [], open: false });
      else if (event.type === "log") row(rows, event.id).lines.push(event.line);
      else if (event.type === "done") Object.assign(row(rows, event.id), { status: event.ok ? "ok" : "fail", detail: event.detail });
      else if (event.type === "gate") rows.push({ id: event.name, title: event.name, status: event.ok ? "ok" : "fail", detail: event.detail, lines: [], open: false });
      else result = event.result;
      selected = Math.min(selected, Math.max(0, rows.length - 1));
      render();
    },
    close() {
      renderer.destroy();
    },
  };
}

export function view(rows: Row[], selected: number, result?: Result) {
  const body = rows.flatMap((item, i) => {
    const mark = i === selected ? ">" : " ";
    const fold = item.lines.length ? (item.open ? "[-]" : "[+]") : "   ";
    const head = `${mark} ${icon(item.status)} ${fold} ${item.title} - ${item.detail}`;
    return item.open ? [head, ...item.lines.slice(-80).map((line) => `      ${line}`)] : [head];
  });
  const tail = result ? ["", `result:  ${result.status}`, `passes:  ${result.passes} / ${result.max}`, `branch:  ${result.branch}`, `commit:  ${result.commit || "none"}`, `report:  ${result.report}`, `track:   ${result.track}`] : ["", "enter toggles logs, j/k moves"];
  return [...LOGO, "", ...body, ...tail].join("\n");
}

function row(rows: Row[], id: string) {
  return rows.find((item) => item.id === id) ?? rows[rows.push({ id, title: id, status: "run", detail: "running", lines: [], open: false }) - 1]!;
}

function icon(status: Row["status"]) {
  return status === "ok" ? "ok" : status === "fail" ? "!!" : "..";
}
