// Render diagram SVGs to 2x PNGs with Playwright + Chromium.
//   NODE_PATH=$(npm root -g) node docs/architecture/diagram/render-png.mjs                       # solution-architecture
//   NODE_PATH=$(npm root -g) node docs/architecture/diagram/render-png.mjs tier2-shared-cell tier3-pooled
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// CommonJS require honours NODE_PATH, so a globally installed Playwright works too.
const { chromium } = createRequire(import.meta.url)("playwright");
const here = dirname(fileURLToPath(import.meta.url));
const names = process.argv.slice(2).length ? process.argv.slice(2) : ["solution-architecture"];

for (const name of names) {
  const browser = await chromium.launch(); // one browser per diagram: large canvases can exhaust a shared one
  const svg = readFileSync(join(here, `${name}.svg`), "utf8");
  const [, w, h] = svg.match(/width="(\d+)" height="(\d+)"/).map(Number);
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2 });
  await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
  await page.screenshot({ path: join(here, `${name}.png`), clip: { x: 0, y: 0, width: w, height: h } });
  await browser.close();
  console.log(`wrote ${name}.png`);
}
