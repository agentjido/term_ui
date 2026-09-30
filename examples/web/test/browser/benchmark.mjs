import {chromium} from "@playwright/test";
import {readFile} from "node:fs/promises";

const javascript = await readFile(new URL("../../../../priv/web/term_ui.js", import.meta.url), "utf8");
const stylesheet = await readFile(new URL("../../../../priv/web/term_ui.css", import.meta.url), "utf8");
const browser = await chromium.launch();
try {
  const page = await browser.newPage({viewport: {width: 2400, height: 2400}});
  await page.route("http://term-ui.test/**", (route) => route.fulfill({
    contentType: "text/html",
    body: '<!doctype html><div id="terminal" style="width:2200px;height:2300px"></div>',
  }));
  await page.goto("http://term-ui.test/");
  const results = await page.evaluate(async ({javascript, stylesheet}) => {
    const style = document.createElement("style");
    style.textContent = stylesheet;
    document.head.append(style);
    const module = await import(URL.createObjectURL(new Blob([javascript], {type: "text/javascript"})));
    const view = new module.TermUIView(document.querySelector("#terminal"));
    let sequence = 0;
    const makeRow = (width, value) => Array.from({length: width}, (_, column) => [
      String.fromCharCode(65 + (column + value) % 26), 1, [40 + value % 100, 120, 180], null, column % 5 ? [] : ["bold"],
    ]);
    const percentile = (values, fraction) => [...values].sort((a, b) => a - b)[Math.floor((values.length - 1) * fraction)];
    const measure = async (payload) => {
      await new Promise(requestAnimationFrame);
      const start = performance.now();
      view.render(payload);
      view.grid.getBoundingClientRect();
      return performance.now() - start;
    };
    const results = [];
    for (const [width, height] of [[80, 24], [160, 50], [200, 100]]) {
      const full = (value) => ({v: 1, type: "frame", seq: ++sequence, base: null, full: true,
        width, height, rows: Array.from({length: height}, (_, row) => [row + 1, makeRow(width, value)]), cursor: null});
      const first = full(0);
      const firstFrameMs = await measure(first);
      const fullTimes = [];
      const deltaTimes = [];
      for (let index = 1; index <= 15; index++) fullTimes.push(await measure(full(index)));
      let delta;
      for (let index = 1; index <= 30; index++) {
        const base = sequence;
        delta = {...first, seq: ++sequence, base, full: false, rows: [[1, makeRow(width, 15 + index)]]};
        deltaTimes.push(await measure(delta));
      }
      results.push({width, height, cells: width * height, firstFrameMs,
        full: {samples: fullTimes.length, p50Ms: percentile(fullTimes, 0.5), p95Ms: percentile(fullTimes, 0.95)},
        deltaRow: {samples: deltaTimes.length, p50Ms: percentile(deltaTimes, 0.5), p95Ms: percentile(deltaTimes, 0.95)},
        fullBytes: new TextEncoder().encode(JSON.stringify(first)).length,
        deltaBytes: new TextEncoder().encode(JSON.stringify(delta)).length,
      });
    }
    view.destroy();
    return results;
  }, {javascript, stylesheet});
  console.log(JSON.stringify({browser: await browser.version(), platform: process.platform, architecture: process.arch,
    measured: "DOM update and synchronous layout; excludes server, network, and paint", results}, null, 2));
} finally {
  await browser.close();
}
