import http from "node:http";

const port = Number(process.env.BACKEND_PORT || "39231");
const runtime = "node";

const server = http.createServer((req, res) => {
  if (req.url === "/health" || req.url === "/api/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, runtime }));
    return;
  }
  if (req.url === "/api/page") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(`<!DOCTYPE html><html><body><h1>${runtime} upstream html</h1></body></html>`);
    return;
  }
  if (req.url === "/" || req.url === "/index.html") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(`<!DOCTYPE html><html><body><h1>${runtime} upstream</h1></body></html>`);
    return;
  }
  res.writeHead(404, { "content-type": "text/plain" });
  res.end("not found");
});

server.listen(port, "127.0.0.1", () => {
  console.log(`${runtime} listening on ${port}`);
});
