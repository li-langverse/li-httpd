async function api(path, opts = {}) {
  const res = await fetch(path, { credentials: "include", ...opts });
  const text = await res.text();
  return { status: res.status, text };
}

document.getElementById("login").onclick = async () => {
  const r = await api("/api/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ user: "agent", pass: "secret" }),
  });
  document.getElementById("status").textContent = `login ${r.status}: ${r.text}`;
};

document.getElementById("me").onclick = async () => {
  const r = await api("/api/me");
  document.getElementById("status").textContent = `me ${r.status}: ${r.text}`;
};

document.getElementById("logout").onclick = async () => {
  const r = await api("/api/logout", { method: "POST" });
  document.getElementById("status").textContent = `logout ${r.status}: ${r.text}`;
};
