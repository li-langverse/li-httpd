const port = Number(process.env.BACKEND_PORT || "39232");
const runtime = "bun";

function clResponse(status, contentType, body) {
  const bytes = new TextEncoder().encode(body);
  return new Response(bytes, {
    status,
    headers: {
      "content-type": contentType,
      "content-length": String(bytes.length),
      connection: "close",
    },
  });
}

Bun.serve({
  hostname: "127.0.0.1",
  port,
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/health" || url.pathname === "/api/health") {
      return clResponse(200, "application/json", JSON.stringify({ ok: true, runtime }));
    }
    if (url.pathname === "/api/page") {
      return clResponse(
        200,
        "text/html; charset=utf-8",
        `<!DOCTYPE html><html><body><h1>${runtime} upstream html</h1></body></html>`,
      );
    }
    if (url.pathname === "/" || url.pathname === "/index.html") {
      return clResponse(
        200,
        "text/html; charset=utf-8",
        `<!DOCTYPE html><html><body><h1>${runtime} upstream</h1></body></html>`,
      );
    }
    return clResponse(404, "text/plain", "not found");
  },
});

console.log(`${runtime} listening on ${port}`);
