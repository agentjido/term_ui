import {defineConfig} from "@playwright/test";

export default defineConfig({
  testDir: "./test/browser",
  timeout: 30000,
  use: {baseURL: "http://127.0.0.1:4040", viewport: {width: 1000, height: 800}},
  webServer: {
    command: "mix run --no-halt",
    url: "http://127.0.0.1:4040",
    reuseExistingServer: false,
    timeout: 120000,
    env: {TERM_UI_WEB_PORT: "4040"},
  },
});
