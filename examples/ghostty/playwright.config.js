import {defineConfig} from "../web/node_modules/@playwright/test/index.mjs";

export default defineConfig({
  testDir: "./test/browser",
  timeout: 30000,
  workers: 1,
  use: {baseURL: "http://127.0.0.1:4041", viewport: {width: 1000, height: 800}},
  webServer: {
    command: "mix run --no-halt",
    url: "http://127.0.0.1:4041",
    reuseExistingServer: false,
    timeout: 120000,
    env: {TERM_UI_WEB_PORT: "4041", TERM: "xterm-256color", SHELL: "/bin/sh"},
  },
});
