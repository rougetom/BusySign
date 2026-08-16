import { DurableObject } from "cloudflare:workers";
import {
  displayStatus,
  isWorkHours,
  workHoursFromEnv,
  type DisplayStatus,
  type MicStatus,
  type WorkHours,
} from "./hours";

const STALE_AFTER_MS = 35_000;
const ALARM_EVERY_MS = 15_000;

export interface SignSnapshot {
  mic: MicStatus;
  display: DisplayStatus;
  inWorkHours: boolean;
  timezone: string;
  workStartHour: number;
  workEndHour: number;
  workDays: number[];
  updatedAt: number;
}

interface StoredState {
  micBusy: boolean;
  lastHeartbeat: number;
  timezone: string;
  updatedAt: number;
}

export class BusySign extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS sign_state (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          mic_busy INTEGER NOT NULL,
          last_heartbeat INTEGER NOT NULL,
          timezone TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      `);
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/ws" && request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].send(JSON.stringify(this.snapshot()));
      return new Response(null, { status: 101, webSocket: pair[0] });
    }

    if (request.method === "POST" && url.pathname === "/heartbeat") {
      const body = (await request.json()) as {
        busy?: boolean;
        timezone?: string;
      };
      if (typeof body.busy !== "boolean") {
        return Response.json({ error: "busy boolean required" }, { status: 400 });
      }
      await this.applyHeartbeat(body.busy, body.timezone);
      return Response.json(this.snapshot());
    }

    if (request.method === "GET" && url.pathname === "/state") {
      return Response.json(this.snapshot());
    }

    return new Response("Not found", { status: 404 });
  }

  async alarm(): Promise<void> {
    this.broadcast(this.snapshot());
    await this.ctx.storage.setAlarm(Date.now() + ALARM_EVERY_MS);
  }

  webSocketMessage(ws: WebSocket): void {
    ws.send(JSON.stringify(this.snapshot()));
  }

  private async applyHeartbeat(busy: boolean, timezone?: string): Promise<void> {
    const now = Date.now();
    const current = this.readState();
    this.writeState({
      micBusy: busy,
      lastHeartbeat: now,
      timezone: timezone || current.timezone,
      updatedAt: now,
    });
    this.broadcast(this.snapshot());
    const existingAlarm = await this.ctx.storage.getAlarm();
    if (existingAlarm === null) {
      await this.ctx.storage.setAlarm(now + ALARM_EVERY_MS);
    }
  }

  private readState(): StoredState {
    const row = this.ctx.storage.sql
      .exec<{
        mic_busy: number;
        last_heartbeat: number;
        timezone: string;
        updated_at: number;
      }>("SELECT mic_busy, last_heartbeat, timezone, updated_at FROM sign_state WHERE id = 1")
      .toArray()[0];

    if (!row) {
      return {
        micBusy: false,
        lastHeartbeat: 0,
        timezone: this.env.TIMEZONE || "UTC",
        updatedAt: 0,
      };
    }

    return {
      micBusy: row.mic_busy === 1,
      lastHeartbeat: row.last_heartbeat,
      timezone: row.timezone,
      updatedAt: row.updated_at,
    };
  }

  private writeState(state: StoredState): void {
    this.ctx.storage.sql.exec(
      `INSERT INTO sign_state (id, mic_busy, last_heartbeat, timezone, updated_at)
       VALUES (1, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         mic_busy = excluded.mic_busy,
         last_heartbeat = excluded.last_heartbeat,
         timezone = excluded.timezone,
         updated_at = excluded.updated_at`,
      state.micBusy ? 1 : 0,
      state.lastHeartbeat,
      state.timezone,
      state.updatedAt,
    );
  }

  private hours(): WorkHours {
    return workHoursFromEnv(this.env, this.readState().timezone);
  }

  snapshot(): SignSnapshot {
    const state = this.readState();
    const hours = this.hours();
    const now = Date.now();
    const stale = state.lastHeartbeat === 0 || now - state.lastHeartbeat > STALE_AFTER_MS;
    const mic: MicStatus = stale ? "offline" : state.micBusy ? "busy" : "free";
    const inHours = isWorkHours(new Date(now), hours);
    return {
      mic,
      display: displayStatus(mic, inHours),
      inWorkHours: inHours,
      timezone: hours.timeZone,
      workStartHour: hours.startHour,
      workEndHour: hours.endHour,
      workDays: hours.days,
      updatedAt: state.updatedAt,
    };
  }

  private broadcast(snapshot: SignSnapshot): void {
    const payload = JSON.stringify(snapshot);
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(payload);
      } catch {
        // Socket already closing; hibernation handles cleanup.
      }
    }
  }
}
