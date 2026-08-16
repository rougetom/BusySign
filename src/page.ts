export function signPage(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="theme-color" content="#050505">
  <link rel="manifest" href="/manifest.webmanifest">
  <title>Busy Sign</title>
  <style>
    :root { color-scheme: dark; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body {
      height: 100%;
      width: 100%;
      overflow: hidden;
      background: #050505;
      font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
      -webkit-user-select: none;
      user-select: none;
      touch-action: manipulation;
    }
    body {
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100dvh;
      transition: background 220ms ease;
    }
    .sign {
      text-align: center;
      padding: 4vmin;
    }
    .label {
      font-weight: 800;
      letter-spacing: 0.06em;
      line-height: 0.9;
      font-size: clamp(4.5rem, 28vmin, 14rem);
      text-transform: uppercase;
    }
    .sub {
      margin-top: 3vmin;
      font-size: clamp(1rem, 4.2vmin, 2.4rem);
      font-weight: 600;
      letter-spacing: 0.18em;
      text-transform: uppercase;
      opacity: 0.82;
    }
    body.busy { background: #b42318; color: #fff5f5; }
    body.free { background: #157347; color: #f0fff4; }
    body.offline { background: #2b2b2b; color: #d0d0d0; }
    body.sleep {
      background: #050505;
      color: #141414;
    }
    body.sleep .label,
    body.sleep .sub { display: none; }
    .sleep-dot {
      display: none;
      position: fixed;
      right: max(12px, env(safe-area-inset-right));
      bottom: max(12px, env(safe-area-inset-bottom));
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: #1c1c1c;
    }
    body.sleep .sleep-dot { display: block; }
    .rotate {
      display: none;
      position: fixed;
      inset: 0;
      background: #111;
      color: #eee;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 8vw;
      font-size: 6vw;
      font-weight: 700;
      z-index: 5;
    }
    @media (orientation: portrait) {
      .rotate { display: flex; }
    }
  </style>
</head>
<body class="offline">
  <div class="rotate">Turn the phone sideways</div>
  <div class="sign">
    <div class="label" id="label">…</div>
    <div class="sub" id="sub">connecting</div>
  </div>
  <div class="sleep-dot" aria-hidden="true"></div>
  <script>
    const labelEl = document.getElementById("label");
    const subEl = document.getElementById("sub");
    const COPY = {
      busy: { label: "BUSY", sub: "On a call" },
      free: { label: "FREE", sub: "Available" },
      offline: { label: "OFFLINE", sub: "Mac not reporting" },
      sleep: { label: "", sub: "" },
    };
    let lastState = null;
    let wakeLock = null;

    function inWorkHours(state, now) {
      if (!state) return false;
      const tz = state.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone;
      const fmt = new Intl.DateTimeFormat("en-US", {
        timeZone: tz,
        weekday: "short",
        hour: "numeric",
        minute: "numeric",
        hourCycle: "h23",
      });
      const parts = Object.fromEntries(fmt.formatToParts(now).map((p) => [p.type, p.value]));
      const days = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
      const weekday = days[parts.weekday];
      let hour = Number(parts.hour);
      if (hour === 24) hour = 0;
      const minute = Number(parts.minute);
      if (!state.workDays.includes(weekday)) return false;
      const mins = hour * 60 + minute;
      return mins >= state.workStartHour * 60 && mins < state.workEndHour * 60;
    }

    function displayOf(state) {
      if (!state) return "offline";
      if (!inWorkHours(state, new Date())) return "sleep";
      return state.mic;
    }

    async function keepAwake() {
      if (!("wakeLock" in navigator)) return;
      try {
        wakeLock = await navigator.wakeLock.request("screen");
      } catch {}
    }

    function render(state) {
      const display = displayOf(state);
      document.body.className = display;
      const copy = COPY[display];
      labelEl.textContent = copy.label;
      subEl.textContent = copy.sub;
      const colors = { busy: "#b42318", free: "#157347", offline: "#2b2b2b", sleep: "#050505" };
      document.querySelector('meta[name="theme-color"]').setAttribute("content", colors[display]);
      keepAwake();
    }

    function apply(state) {
      lastState = state;
      render(state);
    }

    function connect() {
      const proto = location.protocol === "https:" ? "wss" : "ws";
      const ws = new WebSocket(proto + "://" + location.host + "/ws");
      ws.onmessage = (event) => {
        try { apply(JSON.parse(event.data)); } catch {}
      };
      ws.onclose = () => setTimeout(connect, 1500);
      ws.onerror = () => ws.close();
    }

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && lastState) render(lastState);
    });

    setInterval(() => { if (lastState) render(lastState); }, 10000);
    connect();
  </script>
</body>
</html>`;
}
