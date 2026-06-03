import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync } from "node:fs";

const root = new URL(".", import.meta.url).pathname;
const dist = `${root}dist`;

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });

execFileSync(
  "npx",
  ["tailwindcss", "-i", "./src/input.css", "-o", "./dist/styles.css", "--minify"],
  { cwd: root, stdio: "inherit" },
);

cpSync(`${root}index.html`, `${dist}/index.html`);
cpSync(`${root}fonts`, `${dist}/fonts`, { recursive: true });

console.log("built -> dist/");
