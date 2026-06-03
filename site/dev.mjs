import { spawn } from "node:child_process";
import { copyFileSync, cpSync, mkdirSync, rmSync, watch } from "node:fs";

const root = new URL(".", import.meta.url).pathname;
const dist = `${root}dist`;
const port = process.env.PORT ?? "4178";

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
copyFileSync(`${root}index.html`, `${dist}/index.html`);
cpSync(`${root}fonts`, `${dist}/fonts`, { recursive: true });

const child = (cmd, args) =>
  spawn(cmd, args, { cwd: root, stdio: "inherit" });

child("npx", [
  "tailwindcss",
  "-i", "./src/input.css",
  "-o", "./dist/styles.css",
  "--watch",
]);

let pending;
watch(`${root}index.html`, () => {
  clearTimeout(pending);
  pending = setTimeout(() => {
    try {
      copyFileSync(`${root}index.html`, `${dist}/index.html`);
    } catch (err) {
      console.error(`[dev] index.html copy skipped: ${err.message}`);
    }
  }, 50);
});

child("npx", [
  "browser-sync",
  "start",
  "--server", "dist",
  "--files", "dist",
  "--port", port,
  "--no-notify",
]);
