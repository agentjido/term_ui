import {test, expect} from "../../../web/node_modules/@playwright/test/index.mjs";
import {mkdtemp, readFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";

const row = (page, number) => page.locator(`#terminal .term-ui-row:nth-child(${number})`);

async function command(page, text) {
  await page.getByRole("textbox", {name: "Terminal input"}).focus();
  await page.keyboard.insertText(text);
  await page.keyboard.press("Enter");
}

async function stopped(pid) {
  await expect.poll(() => {
    try { process.kill(pid, 0); return false; }
    catch (error) { if (error.code === "ESRCH") return true; throw error; }
  }).toBe(true);
}

test("real shell frames use the shared renderer and close the OS child", async ({page}) => {
  const directory = await mkdtemp(join(tmpdir(), "term-ui-browser-shell-"));
  const file = join(directory, "pid");
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  try {
    await page.goto("/");
    await expect(row(page, 1)).toContainText("TermUI shell · Shell");
    await command(page, `printf '%s\\n' $$ > '${file}'; printf '\\033[2J\\033[H\\033[38;2;12;34;56mé界\\033[0m\\n'`);
    await expect(row(page, 3)).toContainText("é界");
    await expect(row(page, 3).locator("span").nth(0)).toHaveCSS("color", "rgb(12, 34, 56)");
    await expect(row(page, 3).locator("span").nth(2)).toBeHidden();
    await expect.poll(async () => readFile(file, "utf8").catch(() => "")).toMatch(/^\d+\n$/);
    const pid = Number(await readFile(file, "utf8"));
    const previousColumns = await row(page, 1).locator("span").count();
    await page.setViewportSize({width: 680, height: 620});
    await expect.poll(() => row(page, 1).locator("span").count()).toBeLessThan(previousColumns);
    const dimensions = await page.locator("#terminal .term-ui-grid").evaluate((grid) => ({
      rows: Math.min(30, Math.max(1, grid.children.length - 2)),
      columns: Math.min(80, grid.firstElementChild.children.length),
    }));
    await command(page, "stty size");
    await expect(page.locator("#terminal .term-ui-grid")).toContainText(`${dimensions.rows} ${dimensions.columns}`);
    await page.keyboard.press("Control+Alt+q");
    await expect(page.locator("#status")).toHaveText("Closed");
    await stopped(pid);
    expect(errors).toEqual([]);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test("Vim input and two browsers have separate PTYs and state", async ({page, context}) => {
  const directory = await mkdtemp(join(tmpdir(), "term-ui-browser-vim-"));
  const file = join(directory, "vim.txt");
  const pidFile = join(directory, "second-pid");
  const second = await context.newPage();
  try {
    await page.goto("/");
    await second.goto("/");
    await expect(row(page, 1)).toContainText("TermUI shell · Shell");
    await expect(row(second, 1)).toContainText("TermUI shell · Shell");
    await command(second, `printf '%s\\n' $$ > '${pidFile}'; printf '\\033[2J\\033[HSECOND\\n'`);
    await expect(row(second, 3)).toContainText("SECOND");
    await command(page, `vim -Nu NONE -n -i NONE '${file}'`);
    await expect(page.locator("#terminal .term-ui-grid")).toContainText("vim.txt");
    await page.keyboard.press("i");
    await page.keyboard.insertText("Browser Ghostty works");
    await expect(row(page, 3)).toContainText("Browser Ghostty works");
    await expect(row(second, 3)).toContainText("SECOND");
    await page.keyboard.press("Escape");
    await page.keyboard.insertText(":wq");
    await page.keyboard.press("Enter");
    await expect.poll(async () => readFile(file, "utf8").catch(() => "")).toBe("Browser Ghostty works\n");
    await page.keyboard.press("Control+Alt+q");
    await expect(page.locator("#status")).toHaveText("Closed");
    await expect(second.locator("#status")).toHaveText("Connected");
    await expect.poll(async () => readFile(pidFile, "utf8").catch(() => "")).toMatch(/^\d+\n$/);
    const pid = Number(await readFile(pidFile, "utf8"));
    await second.close();
    await stopped(pid);
  } finally { await second.close(); await rm(directory, {recursive: true, force: true}); }
});
