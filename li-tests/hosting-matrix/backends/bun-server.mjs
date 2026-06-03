import { dispatchApp } from "./app-handler.mjs";

const port = Number(process.env.BACKEND_PORT || "39232");
const runtime = process.env.BACKEND_RUNTIME || "bun";

function toResponse(out) {
  const headers = new Headers();
  for (const [k, v] of Object.entries(out.headers)) {
    if (k === "set-cookie") headers.append("set-cookie", v);
    else headers.set(k, v);
  }
  const enc = new TextEncoder().encode(out.body);
  headers.set("content-length", String(enc.length));
  headers.set("connection", "close");
  return new Response(enc, { status: out.status, headers });
}

Bun.serve({
  hostname: "127.0.0.1",
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const body =
      req.method === "POST" || req.method === "PUT" || req.method === "PATCH" ? await req.text() : "";
    const out = dispatchApp(runtime, {
      method: req.method,
      path: url.pathname,
      query: url.search,
      headers: Object.fromEntries(req.headers.entries()),
      body,
      origin: req.headers.get("origin"),
    });
    return toResponse(out);
  },
});

console.log(`${runtime} listening on ${port}`);
