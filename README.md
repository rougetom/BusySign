# Busy Sign

A landscape **FREE / BUSY** door sign for an Android phone, hosted on Cloudflare. A small Mac reporter watches whether any microphone (including Krisp and recording apps) is in use and pushes that to the page.

Outside working hours (**Monday–Friday, 8:00–18:00** in your Mac’s timezone) the phone goes into **pseudo sleep**: a near-black screen, so it does not show BUSY for evening recordings or weekend calls.

## How it fits together

```
Mac mic (Zoom, Meet, Krisp, Voice Memos, …)
        → MicReporter (LaunchAgent)
        → POST /status (secret)
        → Cloudflare Worker + Durable Object
        → Android phone at GET /
```

## Krisp, meetings, and recordings

The reporter does **not** attach to the microphone. It asks Core Audio `kAudioDevicePropertyDeviceIsRunningSomewhere` on **every input device**, including virtual ones.

That is the same signal as the orange Control Center mic indicator, so it should turn BUSY when:

- A meeting app uses the built-in or USB mic (Zoom, Meet, Teams, FaceTime, Slack, …)
- A meeting app uses **Krisp Microphone** (Krisp’s virtual input). Krisp also usually opens the real mic while it is processing, which this loop will see as well
- You are **recording audio** (Voice Memos, QuickTime, Audacity, and similar)

If Krisp is left in an always-on mode that keeps the orange mic dot on even with no meeting and no recording, the sign will stay BUSY during work hours. In that case, turn off Krisp’s always-listen behaviour, or run the reporter with `BUSYSIGN_DEBUG=1` in `~/.busysign.env` to see which device name is holding the mic.

## Working hours / pseudo sleep

| When | Phone |
| --- | --- |
| Mon–Fri 08:00–18:00 | **BUSY** (red) or **FREE** (green) |
| Evenings, nights, weekends | Near-black **sleep** screen |

Hours use the timezone the Mac reporter sends (your Mac’s zone). Override the fallback in [`wrangler.jsonc`](wrangler.jsonc) (`TIMEZONE`, `WORK_START_HOUR`, `WORK_END_HOUR`, `WORK_DAYS`). `WORK_DAYS` is JS weekday numbers: `1,2,3,4,5` = Monday–Friday. The window is `[start, end)` so 18:00 is already sleep.

If the Mac reporter stops heartbeating for ~35 seconds during work hours, the sign shows **OFFLINE** instead of getting stuck on BUSY.

## Deploy the webpage

You need a Cloudflare account and Wrangler auth on your machine (`npx wrangler login`).

```bash
cp .dev.vars.example .dev.vars   # local only; put a real secret in STATUS_SECRET
npm install
npx wrangler secret put STATUS_SECRET   # same value the Mac reporter will send
npm test
npx wrangler deploy
```

Open the printed `https://busy-sign.<account>.workers.dev/` URL on the phone.

## Phone (Android, landscape)

1. Rotate to landscape.
2. Chrome → menu → **Add to Home screen** (standalone, no browser chrome).
3. Keep the phone plugged in; the page requests a screen wake lock so it can leave sleep at 08:00 without a tap.
4. If you see “Turn the phone sideways”, rotate it.

## Install the Mac reporter

On the Mac (needs Xcode Command Line Tools: `xcode-select --install`):

```bash
chmod +x mac/install.sh
./mac/install.sh
```

It compiles `mac/MicReporter.swift`, writes `~/.busysign.env`, and loads a Login LaunchAgent.

```
BUSYSIGN_URL=https://busy-sign.<account>.workers.dev/status
BUSYSIGN_TOKEN=<the STATUS_SECRET value>
```

This process does not capture audio, so it should not need Microphone permission.

Stop it:

```bash
launchctl bootout "gui/$(id -u)/com.busysign.reporter"
```

## Local development

```bash
cp .dev.vars.example .dev.vars
npm install
npm test
npm run dev
```

Then POST heartbeats:

```bash
curl -X POST http://127.0.0.1:8787/status \
  -H "Authorization: Bearer change-me" \
  -H "content-type: application/json" \
  -d '{"busy":true,"timezone":"Europe/London"}'
```
