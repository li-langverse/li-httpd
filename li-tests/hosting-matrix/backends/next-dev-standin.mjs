/**
 * Minimal Next.js-like dev upstream for hosting-matrix (Content-Length, no chunked).
 * Use when full `next dev` streaming breaks li-httpd proxy relay (see smoke section 6).
 */
import http from "node:http";

const port = Number(process.env.BACKEND_PORT || "39237");

const body = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"/></head><body><main><h1>Next.js dev via li-httpd proxy</h1><p>App router page</p></main></body></html>`;
const buf = Buffer.from(body, "utf8");

http
  .createServer((_req, res) => {
    res.writeHead(200, {
      "content-type": "text/html; charset=utf-8",
      "content-length": String(buf.length),
      connection: "close",
    });
    res.end(buf);
  })
  .listen(port, "127.0.0.1", () => {
    console.log(`next-dev-standin listening on ${port}`);
  });
