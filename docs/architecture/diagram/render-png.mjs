// Render solution-architecture.svg to a 2x PNG with Playwright + Chromium.
//   NODE_PATH=$(npm root -g) node docs/architecture/diagram/render-png.mjs
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// CommonJS require honours NODE_PATH, so a globally installed Playwright works too.
const { chromium } = createRequire(import.meta.url)("playwright");
const here = dirname(fileURLToPath(import.meta.url));
const svg = readFileSync(join(here, "solution-architecture.svg"), "utf8");
const [, w, h] = svg.match(/width="(\d+)" height="(\d+)"/).map(Number);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2 });
await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
await page.screenshot({ path: join(here, "solution-architecture.png"), clip: { x: 0, y: 0, width: w, height: h } });
await browser.close();
console.log("wrote solution-architecture.png");
