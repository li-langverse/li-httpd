/**
 * Bun-hosted matrix backend — same CL wire format as node-server.mjs (replyCl).
 * li-httpd C proxy reads upstream bodies via connection-close when Content-Length
 * is lowercase (Node); Title-Case Content-Length from Bun.serve hits a broken CL relay path.
 */
import http from "node:http";
import { dispatchApp } from "./app-handler.mjs";
import { readBody, replyCl } from "./http-common.mjs";

const port = Number(process.env.BACKEND_PORT || "39232");
const host = process.env.BACKEND_HOST || "127.0.0.1";
const runtime = process.env.BACKEND_RUNTIME || "bun";

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  let body = "";
  if (req.method === "POST" || req.method === "PUT" || req.method === "PATCH") {
    try {
      body = await readBody(req);
    } catch {
      replyCl(res, 413, { "content-type": "application/json" }, JSON.stringify({ error: "body too large" }));
      return;
    }
  }
  const out = dispatchApp(runtime, {
    method: req.method || "GET",
    path: url.pathname,
    query: url.search,
    headers: req.headers,
    body,
    origin: req.headers.origin,
  });
  replyCl(res, out.status, out.headers, out.body);
});

server.listen(port, host, () => {
  console.log(`${runtime} listening on ${host}:${port}`);
});
