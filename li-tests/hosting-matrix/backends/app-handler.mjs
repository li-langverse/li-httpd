import { corsHeaders, headerValue, parseCookies, parseQuery } from "./http-common.mjs";

const sessions = new Map();
const users = new Map([
  ["1", { id: 1, name: "Alice", email: "alice@example.com" }],
  ["2", { id: 2, name: "Bob", email: "bob@example.com" }],
]);
let nextUserId = 3;

function json(status, body, extra = {}) {
  return {
    status,
    headers: { "content-type": "application/json", ...extra },
    body: JSON.stringify(body),
  };
}

function noContent(status = 204, extra = {}) {
  return { status, headers: { ...extra }, body: "" };
}

function isXmlContentType(ct) {
  const v = (ct || "").toLowerCase();
  return v.includes("text/xml") || v.includes("application/soap+xml") || v.includes("application/xml");
}

function soapResponse(action, bodyXml) {
  const envelope = `<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <EchoResponse xmlns="urn:hosting-matrix">
      <soapAction>${escapeXml(action || "")}</soapAction>
      ${bodyXml || "<ok>true</ok>"}
    </EchoResponse>
  </soap:Body>
</soap:Envelope>`;
  return {
    status: 200,
    headers: { "content-type": "text/xml; charset=utf-8" },
    body: envelope,
  };
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function matchRestUser(path) {
  const m = path.match(/^\/api\/rest\/users(?:\/(\d+))?$/);
  if (!m) return null;
  return { id: m[1] || null };
}

function handleRestUsers(method, path, query, body, origin) {
  const cors = corsHeaders(origin);
  const rest = matchRestUser(path);
  if (!rest) return null;

  if (method === "GET" && !rest.id) {
    let list = [...users.values()];
    if (query.filter) {
      const f = query.filter.toLowerCase();
      list = list.filter((u) => u.name.toLowerCase().includes(f));
    }
    return json(200, { users: list }, cors);
  }

  if (method === "GET" && rest.id) {
    const u = users.get(rest.id);
    if (!u) return json(404, { error: "not found" }, cors);
    return json(200, u, cors);
  }

  if (method === "POST" && !rest.id) {
    let payload = {};
    try {
      payload = JSON.parse(body || "{}");
    } catch {
      return json(400, { error: "invalid json" }, cors);
    }
    const id = String(nextUserId++);
    const user = { id: Number(id), name: payload.name || "anon", email: payload.email || "" };
    users.set(id, user);
    return { status: 201, headers: { "content-type": "application/json", ...cors }, body: JSON.stringify(user) };
  }

  if (method === "PUT" && rest.id) {
    if (!users.has(rest.id)) return json(404, { error: "not found" }, cors);
    let payload = {};
    try {
      payload = JSON.parse(body || "{}");
    } catch {
      return json(400, { error: "invalid json" }, cors);
    }
    const user = {
      id: Number(rest.id),
      name: payload.name || "anon",
      email: payload.email || "",
    };
    users.set(rest.id, user);
    return json(200, user, cors);
  }

  if (method === "PATCH" && rest.id) {
    const existing = users.get(rest.id);
    if (!existing) return json(404, { error: "not found" }, cors);
    let payload = {};
    try {
      payload = JSON.parse(body || "{}");
    } catch {
      return json(400, { error: "invalid json" }, cors);
    }
    const user = { ...existing, ...payload, id: existing.id };
    users.set(rest.id, user);
    return json(200, user, cors);
  }

  if (method === "DELETE" && rest.id) {
    if (!users.delete(rest.id)) return json(404, { error: "not found" }, cors);
    return noContent(204, cors);
  }

  return null;
}

function handleHeaders(method, headers, origin) {
  const cors = corsHeaders(origin);
  const echoed = {
    "content-type": headerValue(headers, "content-type"),
    accept: headerValue(headers, "accept"),
    soapaction: headerValue(headers, "soapaction"),
    authorization: headerValue(headers, "authorization"),
    "x-custom": headerValue(headers, "x-custom"),
  };
  return json(200, { headers: echoed, method }, cors);
}

/**
 * Pure app router — used by Node and Bun backends.
 * @returns {{ status: number, headers: Record<string,string>, body: string } | null}
 */
export function dispatchApp(runtime, { method, path, query, headers, body, origin }) {
  const cookies = parseCookies(headers.cookie || headers.Cookie);
  const cors = corsHeaders(origin);
  const q = typeof query === "string" ? parseQuery(query) : query || {};

  if (method === "OPTIONS" && path.startsWith("/api/")) {
    return noContent(204, cors);
  }

  if (path === "/health" || path === "/api/health") {
    return json(200, { ok: true, runtime });
  }

  if (path === "/api/login" && method === "POST") {
    let creds = {};
    try {
      creds = JSON.parse(body || "{}");
    } catch {
      return json(400, { error: "invalid json" });
    }
    if (creds.user !== "agent" || creds.pass !== "secret") {
      return json(401, { error: "bad credentials" });
    }
    const token = `sess-${runtime}-${Date.now()}`;
    sessions.set(token, { user: "agent", runtime });
    return {
      status: 200,
      headers: {
        "content-type": "application/json",
        "set-cookie": `session=${token}; Path=/; HttpOnly; SameSite=Lax`,
        ...cors,
      },
      body: JSON.stringify({ ok: true, user: "agent" }),
    };
  }

  if (path === "/api/logout" && method === "POST") {
    const token = cookies.session;
    if (token) sessions.delete(token);
    return {
      status: 200,
      headers: {
        "content-type": "application/json",
        "set-cookie": "session=; Path=/; HttpOnly; Max-Age=0",
        ...cors,
      },
      body: JSON.stringify({ ok: true }),
    };
  }

  if (path === "/api/me" && method === "GET") {
    const sess = cookies.session ? sessions.get(cookies.session) : null;
    if (!sess) {
      return json(401, { error: "unauthorized" }, cors);
    }
    return json(200, { user: sess.user, runtime: sess.runtime }, cors);
  }

  if (path === "/api/echo" && (method === "POST" || method === "PUT" || method === "PATCH")) {
    return json(
      200,
      {
        echo: body,
        contentType: headerValue(headers, "content-type"),
        accept: headerValue(headers, "accept"),
        runtime,
      },
      cors,
    );
  }

  if (path === "/api/headers" && (method === "GET" || method === "POST")) {
    return handleHeaders(method, headers, origin);
  }

  if (path === "/api/soap" && method === "POST") {
    const ct = headerValue(headers, "content-type");
    if (!isXmlContentType(ct)) {
      return json(415, { error: "expected text/xml or application/soap+xml" }, cors);
    }
    if (!body || !body.includes("Envelope")) {
      return json(400, { error: "invalid soap envelope" }, cors);
    }
    const action = headerValue(headers, "soapaction");
    return soapResponse(action, "<received>true</received>");
  }

  const rest = handleRestUsers(method, path, q, body, origin);
  if (rest) return rest;

  if (path === "/api/page" && method === "GET") {
    return {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8" },
      body: `<!DOCTYPE html><html><body><h1>${runtime} upstream html</h1></body></html>`,
    };
  }

  if ((path === "/" || path === "/index.html") && method === "GET") {
    const peer = process.env.BACKEND_RUNTIME || runtime;
    return {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8" },
      body: `<!DOCTYPE html><html><body><h1>${runtime} upstream</h1><p>peer=${peer}</p></body></html>`,
    };
  }

  return { status: 404, headers: { "content-type": "text/plain" }, body: "not found" };
}
