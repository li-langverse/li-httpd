import http from "node:http";

const port = Number(process.env.BACKEND_PORT || "39231");
const runtime = "node";

/** li-httpd proxy relay expects CL responses (not chunked) from upstream. */
function reply(res, status, contentType, body) {
  const buf = Buffer.from(body, "utf8");
  res.writeHead(status, {
    "content-type": contentType,
    "content-length": String(buf.length),
    connection: "close",
  });
  res.end(buf);
}

const server = http.createServer((req, res) => {
  if (req.url === "/health" || req.url === "/api/health") {
    reply(res, 200, "application/json", JSON.stringify({ ok: true, runtime }));
    return;
  }
  if (req.url === "/api/page") {
    reply(
      res,
      200,
      "text/html; charset=utf-8",
      `<!DOCTYPE html><html><body><h1>${runtime} upstream html</h1></body></html>`,
    );
    return;
  }
  if (req.url === "/" || req.url === "/index.html") {
    reply(
      res,
      200,
      "text/html; charset=utf-8",
      `<!DOCTYPE html><html><body><h1>${runtime} upstream</h1></body></html>`,
    );
    return;
  }
  reply(res, 404, "text/plain", "not found");
});

server.listen(port, "127.0.0.1", () => {
  console.log(`${runtime} listening on ${port}`);
});
