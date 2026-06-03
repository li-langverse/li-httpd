/** Shared helpers for hosting-matrix backends (CL responses for li-httpd proxy relay). */

export function replyCl(res, status, headers, body) {
  const buf = Buffer.from(body ?? "", "utf8");
  const h = {
    "content-length": String(buf.length),
    connection: "close",
    ...headers,
  };
  res.writeHead(status, h);
  res.end(buf);
}

export function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let len = 0;
    req.on("data", (c) => {
      len += c.length;
      if (len > 1_000_000) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

export function parseCookies(header) {
  const out = {};
  if (!header) return out;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i < 1) continue;
    const k = part.slice(0, i).trim();
    const v = part.slice(i + 1).trim();
    if (k) out[k] = decodeURIComponent(v);
  }
  return out;
}

export function corsHeaders(origin) {
  const o = origin || "*";
  return {
    "access-control-allow-origin": o,
    "access-control-allow-credentials": "true",
    "access-control-allow-methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    "access-control-allow-headers":
      "content-type, accept, cookie, authorization, soapaction, x-custom, x-requested-with",
    vary: "Origin",
  };
}

/** Case-insensitive header lookup from Node/Bun request headers object. */
export function headerValue(headers, name) {
  if (!headers) return "";
  const target = name.toLowerCase();
  for (const [k, v] of Object.entries(headers)) {
    if (k.toLowerCase() === target) return Array.isArray(v) ? v[0] : String(v);
  }
  return "";
}

export function parseQuery(search) {
  const out = {};
  if (!search || search === "?") return out;
  const q = search.startsWith("?") ? search.slice(1) : search;
  for (const part of q.split("&")) {
    if (!part) continue;
    const i = part.indexOf("=");
    if (i < 0) out[decodeURIComponent(part)] = "";
    else out[decodeURIComponent(part.slice(0, i))] = decodeURIComponent(part.slice(i + 1));
  }
  return out;
}
