const port = Number(process.env.BACKEND_PORT || "39232");
const runtime = "bun";

Bun.serve({
  hostname: "127.0.0.1",
  port,
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/health" || url.pathname === "/api/health") {
      return Response.json({ ok: true, runtime });
    }
    if (url.pathname === "/api/page") {
      return new Response(
        `<!DOCTYPE html><html><body><h1>${runtime} upstream html</h1></body></html>`,
        { headers: { "content-type": "text/html; charset=utf-8" } },
      );
    }
    if (url.pathname === "/" || url.pathname === "/index.html") {
      return new Response(
        `<!DOCTYPE html><html><body><h1>${runtime} upstream</h1></body></html>`,
        { headers: { "content-type": "text/html; charset=utf-8" } },
      );
    }
    return new Response("not found", { status: 404 });
  },
});

console.log(`${runtime} listening on ${port}`);
