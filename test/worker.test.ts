import { env, runDurableObjectAlarm, runInDurableObject, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { BusySign } from "../src/sign";

const auth = {
  Authorization: "Bearer test-secret",
  "content-type": "application/json",
};

describe("busy sign worker", () => {
  it("serves a landscape sign page", async () => {
    const res = await SELF.fetch("https://example.com/");
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("Turn the phone sideways");
    expect(html).toContain("orientation: portrait");
    expect(html).toContain("/ws");
  });

  it("rejects status updates without the secret", async () => {
    const res = await SELF.fetch("https://example.com/status", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ busy: true }),
    });
    expect(res.status).toBe(401);
  });

  it("records microphone busy and free heartbeats", async () => {
    const busyRes = await SELF.fetch("https://example.com/status", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({ busy: true, timezone: "America/New_York" }),
    });
    expect(busyRes.status).toBe(200);
    const busy = await busyRes.json<{ mic: string; timezone: string }>();
    expect(busy.mic).toBe("busy");
    expect(busy.timezone).toBe("America/New_York");

    const freeRes = await SELF.fetch("https://example.com/status", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({ busy: false, timezone: "America/New_York" }),
    });
    const free = await freeRes.json<{ mic: string }>();
    expect(free.mic).toBe("free");
  });

  it("marks the mic offline after a stale heartbeat", async () => {
    await SELF.fetch("https://example.com/status", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({ busy: true, timezone: "America/New_York" }),
    });

    const stub = env.SIGN.getByName("home");
    await runInDurableObject(stub, async (instance: BusySign, state) => {
      expect(instance).toBeInstanceOf(BusySign);
      state.storage.sql.exec(
        "UPDATE sign_state SET last_heartbeat = 1, mic_busy = 1 WHERE id = 1",
      );
    });

    const ran = await runDurableObjectAlarm(stub);
    expect(ran).toBe(true);

    const res = await SELF.fetch("https://example.com/api/status");
    const body = await res.json<{ mic: string }>();
    expect(body.mic).toBe("offline");
  });
});
