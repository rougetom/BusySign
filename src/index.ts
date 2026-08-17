import { BusySign } from "./sign";
import { signPage } from "./page";

export { BusySign };

const SIGN_NAME = "home";

function signStub(env: Env) {
  return env.SIGN.getByName(SIGN_NAME);
}

function unauthorized(): Response {
  return new Response("Unauthorized", { status: 401 });
}

function isAuthorized(request: Request, secret: string): boolean {
  if (!secret) return false;
  const header = request.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return false;
  const a = new TextEncoder().encode(token);
  const b = new TextEncoder().encode(secret);
  if (a.byteLength !== b.byteLength) return false;
  return crypto.subtle.timingSafeEqual(a, b);
}

function manifest(): Response {
  return new Response(
    JSON.stringify({
      name: "Busy Sign",
      short_name: "Busy",
      start_url: "/",
      display: "standalone",
      orientation: "landscape",
      background_color: "#050505",
      theme_color: "#050505",
    }),
    { headers: { "content-type": "application/manifest+json" } },
  );
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const sign = signStub(env);

    if (request.method === "GET" && url.pathname === "/") {
      return new Response(signPage(), {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store",
        },
      });
    }

    if (request.method === "GET" && url.pathname === "/manifest.webmanifest") {
      return manifest();
    }

    if (url.pathname === "/ws") {
      return sign.fetch(request);
    }

    if (request.method === "GET" && url.pathname === "/api/status") {
      return sign.fetch(new Request("https://sign/state", { method: "GET" }));
    }

    if (request.method === "POST" && url.pathname === "/status") {
      if (!isAuthorized(request, env.STATUS_SECRET)) return unauthorized();
      return sign.fetch(
        new Request("https://sign/heartbeat", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: await request.text(),
        }),
      );
    }

    return new Response("Not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
