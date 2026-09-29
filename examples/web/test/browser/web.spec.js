import {test, expect} from "@playwright/test";

const row = (page, number) => page.locator(`#terminal .term-ui-row:nth-child(${number})`);
const cell = (text = " ", width = 1, fg = null, bg = null, attrs = []) => [text, width, fg, bg, attrs];
const frame = (seq, rows, extra = {}) => ({v: 1, type: "frame", seq, base: null, full: true,
  width: rows[0].length, height: rows.length, rows: rows.map((cells, index) => [index + 1, cells]), cursor: null, ...extra});

async function fixture(page) {
  await page.goto("/");
  await page.evaluate(async () => {
    const {TermUIView} = await import("/assets/term_ui.js");
    const element = document.createElement("div");
    element.id = "fixture";
    element.style.cssText = "width:400px;height:220px;position:relative";
    document.body.append(element);
    window.messages = [];
    window.view = new TermUIView(element, {send: (payload) => window.messages.push(payload)});
  });
}

test("normal Elm input, Unicode, colors, resize, shutdown, and reconnect", async ({page}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await expect(page.locator("#status")).toHaveText("Connected");
  await expect(row(page, 3)).toContainText("Count: 0");
  const editor = page.getByRole("textbox", {name: "Terminal input"});
  await editor.focus();
  await page.keyboard.press("Space");
  await page.keyboard.press("ArrowUp");
  await expect(row(page, 3)).toContainText("Count: 2");
  await page.keyboard.insertText("é界👩‍💻");
  await expect(row(page, 4)).toContainText("Text: é界👩‍💻");
  await expect(row(page, 1).locator("span").first()).toHaveCSS("color", "rgb(240, 200, 20)");
  await expect(row(page, 3).locator("span").first()).toHaveCSS("background-color", "rgb(10, 20, 180)");
  await page.keyboard.press("Control+o");
  await expect(row(page, 5)).toContainText('Key "o" [:ctrl]');
  const before = await row(page, 1).textContent();
  await page.setViewportSize({width: 720, height: 650});
  await expect(row(page, 1)).not.toHaveText(before);
  await expect(row(page, 3)).toContainText("Count: 2");
  await page.keyboard.press("q");
  await expect(page.locator("#status")).toHaveText("Closed");
  await page.getByRole("button", {name: "Reconnect"}).click();
  await expect(page.locator("#status")).toHaveText("Connected");
  await expect(row(page, 3)).toContainText("Count: 0");
  await expect(row(page, 4)).not.toContainText("é界");
  expect(errors).toEqual([]);
});

test("two browser connections keep application state and close separate", async ({page, context}) => {
  const second = await context.newPage();
  await page.goto("/");
  await second.goto("/");
  await expect(row(page, 3)).toContainText("Count: 0");
  await expect(row(second, 3)).toContainText("Count: 0");
  await page.getByRole("textbox", {name: "Terminal input"}).focus();
  await page.keyboard.press("Space");
  await expect(row(page, 3)).toContainText("Count: 1");
  await expect(row(second, 3)).toContainText("Count: 0");
  await page.keyboard.press("q");
  await expect(page.locator("#status")).toHaveText("Closed");
  await second.getByRole("textbox", {name: "Terminal input"}).focus();
  await second.keyboard.press("ArrowUp");
  await expect(row(second, 3)).toContainText("Count: 1");
  await second.close();
});

test("changed rows clear old cells, preserve wide cells, show styles, and use a confirmed base", async ({page}) => {
  await fixture(page);
  const styled = cell("é", 1, [10, 20, 30], 42, ["bold", "italic", "underline", "strikethrough"]);
  const initial = frame(1, [[styled, cell("界", 2), cell("", 0), cell("x")], [cell("a"), cell("b"), cell("c"), cell("d")]], {cursor: [4, 2]});
  await page.evaluate((payload) => window.view.render(payload), initial);
  const cells = page.locator("#fixture .term-ui-row").first().locator("span");
  await expect(cells.nth(0)).toHaveCSS("color", "rgb(10, 20, 30)");
  await expect(cells.nth(0)).toHaveCSS("background-color", "rgb(0, 215, 135)");
  await expect(cells.nth(0)).toHaveCSS("font-weight", "700");
  await expect(cells.nth(0)).toHaveCSS("font-style", "italic");
  await expect(cells.nth(0)).toHaveCSS("text-decoration-line", "underline line-through");
  await expect(cells.nth(2)).toBeHidden();
  const widths = await cells.evaluateAll((nodes) => nodes.map((node) => node.getBoundingClientRect().width));
  expect(widths[1]).toBeCloseTo(widths[0] * 2, 1);
  await expect(page.locator("#fixture .term-ui-cursor")).toBeVisible();
  const changed = frame(2, [[cell("a"), cell(), cell(" ", 1, null, "blue"), cell()]], {
    full: false, base: 1, width: 4, height: 2, rows: [[2, [cell("a"), cell(), cell(" ", 1, null, "blue"), cell()]]],
  });
  await page.evaluate((payload) => window.view.render(payload), changed);
  await expect(page.locator("#fixture .term-ui-row").nth(1)).toHaveText("a   ");
  await expect(page.locator("#fixture .term-ui-row").nth(1).locator("span").nth(2)).toHaveCSS("background-color", "rgb(36, 114, 200)");
  await expect(cells.nth(0)).toHaveText("é");
  const missing = {...changed, seq: 4, base: 3};
  expect(await page.evaluate((payload) => window.view.render(payload), missing)).toBe(false);
  await page.evaluate((payload) => window.view.render(payload), missing);
  expect(await page.evaluate(() => window.messages.filter((message) => message.type === "resync").length)).toBe(1);
  const replacement = frame(5, [[cell("z"), cell()]], {cursor: null});
  await page.evaluate((payload) => window.view.render(payload), replacement);
  await expect(page.locator("#fixture .term-ui-row")).toHaveCount(1);
  await expect(page.locator("#fixture .term-ui-cell")).toHaveCount(2);
  expect(await page.evaluate(() => window.messages.at(-1))).toEqual({v: 1, type: "ack", seq: 5});
});

test("keyboard, IME, paste, mouse, focus, and measured resize send normalized maps", async ({page}) => {
  await fixture(page);
  await page.evaluate((payload) => window.view.render(payload), frame(1, Array.from({length: 10}, () => Array.from({length: 30}, () => cell()))));
  await page.evaluate(() => { window.messages = []; window.view.focus(); });
  await page.keyboard.press("A");
  await page.keyboard.press("Control+Alt+o");
  await page.keyboard.press("ArrowUp");
  await page.evaluate(() => {
    const input = window.view.editor;
    input.dispatchEvent(new CompositionEvent("compositionstart"));
    input.dispatchEvent(new InputEvent("beforeinput", {inputType: "insertCompositionText", data: "界", isComposing: true}));
    input.dispatchEvent(new CompositionEvent("compositionend", {data: "界"}));
    input.dispatchEvent(new InputEvent("beforeinput", {inputType: "insertFromComposition", data: "界"}));
    const clipboardData = new DataTransfer();
    clipboardData.setData("text/plain", "one\ntwo");
    input.dispatchEvent(new ClipboardEvent("paste", {clipboardData, cancelable: true}));
  });
  const grid = page.locator("#fixture .term-ui-grid");
  await grid.click({position: {x: 25, y: 45}});
  const messages = await page.evaluate(() => window.messages);
  expect(messages).toContainEqual({v: 1, type: "text", text: "A"});
  expect(messages).toContainEqual({v: 1, type: "key", key: "o", modifiers: ["ctrl", "alt"]});
  expect(messages).toContainEqual({v: 1, type: "key", key: "ArrowUp", modifiers: []});
  expect(messages.filter((message) => message.text === "界")).toEqual([{v: 1, type: "text", text: "界"}]);
  expect(messages).toContainEqual({v: 1, type: "paste", text: "one\ntwo"});
  expect(messages).toContainEqual({v: 1, type: "mouse", action: "press", button: "left", x: 2, y: 2, modifiers: []});
  await page.evaluate(() => { window.view.editor.blur(); window.view.element.style.width = "200px"; });
  await expect.poll(() => page.evaluate(() => window.messages.some((message) => message.type === "focus" && !message.focused))).toBe(true);
  await expect.poll(() => page.evaluate(() => window.messages.some((message) => message.type === "resize" && message.width < 30))).toBe(true);
});

test("cell text cannot execute HTML and invalid frames cannot partially change the screen", async ({page}) => {
  await fixture(page);
  const text = '<img src=x onerror="window.executed=true">';
  await page.evaluate((payload) => window.view.render(payload), frame(1, [[cell(text)]]));
  await expect(page.locator("#fixture img")).toHaveCount(0);
  expect(await page.evaluate(() => window.executed)).toBeUndefined();
  for (const invalid of [
    frame(2, [[cell("bad")]], {v: 2}),
    frame(2, [[cell("bad", 0)]]),
    frame(2, [[cell("bad", 1, "url(evil)")]]),
    frame(2, [[cell("bad", 1, null, null, ["unknown"])]]),
    frame(2, [[cell("bad")]], {cursor: [2, 1]}),
  ]) {
    expect(await page.evaluate((payload) => {
      try { window.view.render(payload); return false; } catch (_error) { return true; }
    }, invalid)).toBe(true);
    await expect(page.locator("#fixture .term-ui-cell")).toHaveText(text);
  }
});

test("the host rejects an unknown origin and invalid input", async ({page}) => {
  const refused = await page.evaluate(() => new Promise((resolve) => {
    const socket = new WebSocket("ws://127.0.0.1:4040/ws");
    socket.addEventListener("open", () => resolve(false));
    socket.addEventListener("close", () => resolve(true));
  }));
  expect(refused).toBe(true);
  await page.goto("/");
  const code = await page.evaluate(() => new Promise((resolve) => {
    const socket = new WebSocket(`ws://${location.host}/ws`);
    socket.addEventListener("open", () => socket.send(JSON.stringify({v: 1, type: "resize", width: 999999, height: 1})));
    socket.addEventListener("close", (event) => resolve(event.code));
  }));
  expect(code).toBe(1008);
});
