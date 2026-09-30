const palette = [
  "#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
  "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff",
];
const names = [
  "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
  "bright_black", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_white",
];
const attributes = new Set(["bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strikethrough"]);
const namedKeys = new Set([
  "Enter", "Tab", "Backspace", "Delete", "Escape", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
  "Home", "End", "PageUp", "PageDown", "Insert", ...Array.from({length: 12}, (_, i) => `F${i + 1}`),
]);
const modifiers = (event) => [
  event.ctrlKey && "ctrl", event.altKey && "alt", event.metaKey && "meta", event.shiftKey && "shift",
].filter(Boolean);
const integer = (value, min, max) => Number.isInteger(value) && value >= min && value <= max;

function color(value) {
  if (value === null) return null;
  if (typeof value === "string") {
    const index = names.indexOf(value);
    if (index < 0) throw new Error("Invalid named color");
    return palette[index];
  }
  if (integer(value, 0, 255)) {
    if (value < 16) return palette[value];
    if (value < 232) {
      const levels = [0, 95, 135, 175, 215, 255];
      const index = value - 16;
      return `rgb(${levels[Math.floor(index / 36)]}, ${levels[Math.floor(index / 6) % 6]}, ${levels[index % 6]})`;
    }
    const level = 8 + (value - 232) * 10;
    return `rgb(${level}, ${level}, ${level})`;
  }
  if (Array.isArray(value) && value.length === 3 && value.every((part) => integer(part, 0, 255))) {
    return `rgb(${value.join(", ")})`;
  }
  throw new Error("Invalid cell color");
}

function validateCell(cell, previous) {
  if (!Array.isArray(cell) || cell.length !== 5 || typeof cell[0] !== "string" ||
      !integer(cell[1], 0, 2) || !Array.isArray(cell[4]) || cell[4].some((value) => !attributes.has(value))) {
    throw new Error("Invalid frame cell");
  }
  if ((cell[1] === 0 && (cell[0] !== "" || previous?.[1] !== 2)) || (cell[1] !== 0 && cell[0] === "")) {
    throw new Error("Invalid wide character");
  }
  color(cell[2]);
  color(cell[3]);
}

/** Render TermUI frames and send the existing input events. No HTML from cells is executed. */
export class TermUIView {
  constructor(element, {send = () => {}, maxColumns = 300, maxRows = 120} = {}) {
    this.element = element;
    this.send = (payload) => send({v: 1, ...payload});
    this.maxColumns = maxColumns;
    this.maxRows = maxRows;
    this.sequence = null;
    this.width = 0;
    this.height = 0;
    this.rows = [];
    this.resyncPending = false;
    this.composing = false;
    this.listeners = [];
    element.classList.add("term-ui");
    element.setAttribute("role", "application");
    element.setAttribute("aria-label", "TermUI application");
    this.grid = document.createElement("div");
    this.grid.className = "term-ui-grid";
    this.cursor = document.createElement("div");
    this.cursor.className = "term-ui-cursor";
    this.cursor.hidden = true;
    this.cursor.setAttribute("aria-hidden", "true");
    this.editor = document.createElement("textarea");
    this.editor.className = "term-ui-input";
    this.editor.setAttribute("aria-label", "Terminal input");
    this.editor.setAttribute("autocapitalize", "off");
    this.editor.setAttribute("autocomplete", "off");
    this.editor.spellcheck = false;
    this.measure = document.createElement("span");
    this.measure.className = "term-ui-measure";
    this.measure.textContent = "MMMMMMMMMM";
    this.measure.setAttribute("aria-hidden", "true");
    element.replaceChildren(this.grid, this.cursor, this.editor, this.measure);
    this.bindInput();
    this.observer = new ResizeObserver(() => this.requestSize());
    this.observer.observe(element);
    this.requestSize();
  }

  reset() {
    this.sequence = null;
    this.resyncPending = false;
    this.lastSize = null;
  }

  focus() { this.editor.focus({preventScroll: true}); }

  destroy() {
    this.observer.disconnect();
    cancelAnimationFrame(this.mouseAnimation);
    for (const [target, name, listener, options] of this.listeners) target.removeEventListener(name, listener, options);
    this.element.replaceChildren();
  }

  render(frame) {
    this.validateFrame(frame);
    if (this.sequence !== null && frame.seq <= this.sequence) {
      this.send({type: "ack", seq: frame.seq});
      return false;
    }
    if (!frame.full && (frame.base !== this.sequence || frame.width !== this.width || frame.height !== this.height)) {
      if (!this.resyncPending) this.send({type: "resync"});
      this.resyncPending = true;
      return false;
    }
    if (frame.full && (this.width !== frame.width || this.height !== frame.height || !this.rows.length)) {
      this.makeGrid(frame.width, frame.height);
    }
    for (const [number, cells] of frame.rows) this.renderRow(number - 1, cells);
    this.cursor.hidden = frame.cursor === null;
    if (frame.cursor) {
      this.cursor.style.left = `calc(${frame.cursor[0] - 1} * var(--term-ui-cell-width))`;
      this.cursor.style.top = `calc(${frame.cursor[1] - 1} * var(--term-ui-cell-height))`;
    }
    this.sequence = frame.seq;
    this.resyncPending = false;
    this.element.dataset.sequence = String(frame.seq);
    this.send({type: "ack", seq: frame.seq});
    return true;
  }

  validateFrame(frame) {
    if (frame?.v !== 1 || frame.type !== "frame" || !integer(frame.seq, 1, Number.MAX_SAFE_INTEGER) ||
        typeof frame.full !== "boolean" || !integer(frame.width, 1, this.maxColumns) ||
        !integer(frame.height, 1, this.maxRows) || !Array.isArray(frame.rows) || frame.rows.length > frame.height ||
        (frame.full ? frame.base !== null || frame.rows.length !== frame.height : !integer(frame.base, 1, frame.seq - 1))) {
      throw new Error("Invalid frame message");
    }
    const seen = new Set();
    for (const row of frame.rows) {
      if (!Array.isArray(row) || row.length !== 2 || !integer(row[0], 1, frame.height) || seen.has(row[0]) ||
          !Array.isArray(row[1]) || row[1].length !== frame.width) throw new Error("Invalid frame row");
      seen.add(row[0]);
      row[1].forEach((cell, index) => {
        validateCell(cell, row[1][index - 1]);
        if (cell[1] === 2 && row[1][index + 1]?.[1] !== 0) throw new Error("Missing wide character placeholder");
      });
    }
    if (frame.cursor !== null && (!Array.isArray(frame.cursor) || frame.cursor.length !== 2 ||
        !integer(frame.cursor[0], 1, frame.width) || !integer(frame.cursor[1], 1, frame.height))) {
      throw new Error("Invalid frame cursor");
    }
  }

  makeGrid(width, height) {
    this.width = width;
    this.height = height;
    this.rows = [];
    const fragment = document.createDocumentFragment();
    for (let row = 0; row < height; row++) {
      const element = document.createElement("div");
      element.className = "term-ui-row";
      const nodes = Array.from({length: width}, () => {
        const node = document.createElement("span");
        node.className = "term-ui-cell";
        element.append(node);
        return node;
      });
      this.rows.push({nodes, values: []});
      fragment.append(element);
    }
    this.grid.replaceChildren(fragment);
    this.grid.style.width = `calc(${width} * var(--term-ui-cell-width))`;
    this.grid.style.height = `calc(${height} * var(--term-ui-cell-height))`;
  }

  renderRow(row, cells) {
    const {nodes, values} = this.rows[row];
    cells.forEach((cell, column) => {
      const signature = JSON.stringify(cell);
      if (values[column] === signature) return;
      values[column] = signature;
      const node = nodes[column];
      const [text, width, fg, bg, attrs] = cell;
      node.hidden = width === 0;
      node.textContent = text;
      node.style.width = `calc(${width} * var(--term-ui-cell-width))`;
      let foreground = color(fg) || "var(--term-ui-fg)";
      let background = color(bg) || "var(--term-ui-bg)";
      if (attrs.includes("reverse")) [foreground, background] = [background, foreground];
      node.style.color = attrs.includes("dim") ? `color-mix(in srgb, ${foreground} 50%, ${background})` : foreground;
      node.style.backgroundColor = background;
      node.className = "term-ui-cell " + attrs.map((attribute) => `term-ui-${attribute}`).join(" ");
    });
  }

  listen(target, name, listener, options) {
    target.addEventListener(name, listener, options);
    this.listeners.push([target, name, listener, options]);
  }

  requestSize() {
    const metrics = this.measure.getBoundingClientRect();
    this.cellWidth = metrics.width / 10;
    this.cellHeight = metrics.height;
    if (!this.cellWidth || !this.cellHeight) return;
    this.element.style.setProperty("--term-ui-cell-width", `${this.cellWidth}px`);
    this.element.style.setProperty("--term-ui-cell-height", `${this.cellHeight}px`);
    const width = Math.max(1, Math.min(this.maxColumns, Math.floor(this.element.clientWidth / this.cellWidth)));
    const height = Math.max(1, Math.min(this.maxRows, Math.floor(this.element.clientHeight / this.cellHeight)));
    const signature = `${width}:${height}`;
    if (signature !== this.lastSize) {
      this.lastSize = signature;
      this.send({type: "resize", width, height});
    }
  }

  bindInput() {
    this.listen(this.element, "pointerdown", () => this.focus());
    this.listen(this.editor, "focus", () => this.send({type: "focus", focused: true}));
    this.listen(this.editor, "blur", () => this.send({type: "focus", focused: false}));
    this.listen(this.editor, "compositionstart", () => { this.composing = true; });
    this.listen(this.editor, "compositionend", (event) => {
      this.composing = false;
      if (event.data) this.send({type: "text", text: event.data});
      this.editor.value = "";
    });
    this.listen(this.editor, "beforeinput", (event) => {
      if (this.composing || event.inputType.includes("Composition")) return;
      if (event.data && event.inputType.startsWith("insert")) {
        event.preventDefault();
        this.send({type: "text", text: event.data});
      }
    });
    this.listen(this.editor, "input", () => { if (!this.composing) this.editor.value = ""; });
    this.listen(this.editor, "paste", (event) => {
      event.preventDefault();
      this.send({type: "paste", text: event.clipboardData.getData("text/plain")});
    });
    this.listen(this.editor, "keydown", (event) => {
      if (this.composing || event.isComposing || event.key === "Process" || event.key === "Dead") return;
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "v") return;
      const mods = modifiers(event);
      if (namedKeys.has(event.key) || ((event.ctrlKey || event.altKey || event.metaKey) && [...event.key].length === 1)) {
        event.preventDefault();
        this.send({type: "key", key: event.key, modifiers: mods});
      } else if ([...event.key].length === 1) {
        event.preventDefault();
        this.send({type: "text", text: event.key});
      }
    });
    this.listen(this.element, "contextmenu", (event) => event.preventDefault());
    this.listen(this.grid, "pointerdown", (event) => this.mouse(event, "press"));
    this.listen(this.grid, "pointerup", (event) => this.mouse(event, "release"));
    this.listen(this.grid, "pointermove", (event) => {
      this.pendingMouse = event;
      if (!this.mouseAnimation) this.mouseAnimation = requestAnimationFrame(() => {
        this.mouseAnimation = null;
        this.mouse(this.pendingMouse, this.pendingMouse.buttons ? "drag" : "move");
      });
    });
    this.listen(this.grid, "wheel", (event) => {
      event.preventDefault();
      if (event.deltaY) this.mouse(event, event.deltaY < 0 ? "scroll_up" : "scroll_down");
    }, {passive: false});
  }

  mouse(event, action) {
    const bounds = this.grid.getBoundingClientRect();
    const x = Math.floor((event.clientX - bounds.left) / this.cellWidth);
    const y = Math.floor((event.clientY - bounds.top) / this.cellHeight);
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return;
    const button = action.startsWith("scroll") || action === "move" ? null : action === "drag"
      ? (event.buttons & 1 ? "left" : event.buttons & 4 ? "middle" : "right")
      : ["left", "middle", "right"][event.button];
    this.send({type: "mouse", action, button, x, y, modifiers: modifiers(event)});
  }
}

/** Connect to a host-selected application. The host must authenticate the connection. */
export function connectTermUI(element, url, {onStatus = () => {}, ...options} = {}) {
  let socket;
  const view = new TermUIView(element, {...options, send(payload) {
    if (socket?.readyState === WebSocket.OPEN) {
      if (socket.bufferedAmount > 262144) {
        socket.close(1008, "Input buffer limit");
        onStatus("error");
        return;
      }
      socket.send(JSON.stringify(payload));
    }
  }});
  const connect = () => {
    socket?.close();
    view.reset();
    onStatus("connecting");
    const connection = new WebSocket(url);
    let failed = false;
    socket = connection;
    connection.addEventListener("open", () => {
      if (socket !== connection) return;
      onStatus("connected");
      view.lastSize = null;
      view.requestSize();
      view.focus();
    });
    connection.addEventListener("message", (event) => {
      if (socket !== connection) return;
      try {
        const payload = JSON.parse(event.data);
        if (payload.v === 1 && payload.type === "closed") {
          failed = payload.reason !== "normal";
          onStatus(payload.reason === "normal" ? "closed" : "error");
          connection.close();
        } else view.render(payload);
      } catch (_error) {
        failed = true;
        onStatus("error");
        connection.close(1002, "Invalid frame");
      }
    });
    connection.addEventListener("close", (event) => {
      if (socket === connection) onStatus(failed || ![1000, 1005].includes(event.code) ? "error" : "closed");
    });
    connection.addEventListener("error", () => { failed = true; if (socket === connection) onStatus("error"); });
  };
  connect();
  return {view, reconnect: connect, close() { socket?.close(); socket = null; view.destroy(); }};
}
