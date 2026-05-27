import { type Event, type Result, type Sink } from "./devloop.ts";
import { view, type Row } from "./tui-view.ts";

export async function createTuiSink(): Promise<Sink> {
  const { TextRenderable, createCliRenderer } = await import("@opentui/core");
  const renderer = await createCliRenderer({ exitOnCtrlC: true, consoleMode: "disabled", screenMode: "alternate-screen" });
  const text = new TextRenderable(renderer, { id: "devloop", width: "100%", height: "100%", content: "" });
  const rows: Row[] = [];
  let selected = 0;
  let result: Result | undefined;

  renderer.root.add(text);
  renderer.keyInput.on("keypress", (key) => {
    if (key.name === "up") selected = Math.max(0, selected - 1);
    else if (key.name === "down") selected = Math.min(rows.length - 1, selected + 1);
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

function row(rows: Row[], id: string) {
  return rows.find((item) => item.id === id) ?? rows[rows.push({ id, title: id, status: "run", detail: "running", lines: [], open: false }) - 1]!;
}
