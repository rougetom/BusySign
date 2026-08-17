export interface WorkHours {
  timeZone: string;
  startHour: number;
  endHour: number;
  days: number[];
}

const WEEKDAY_TO_JS: Record<string, number> = {
  Sun: 0,
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
};

export function parseWorkDays(raw: string): number[] {
  return raw
    .split(",")
    .map((part) => Number(part.trim()))
    .filter((day) => Number.isInteger(day) && day >= 0 && day <= 6);
}

export function workHoursFromEnv(env: {
  TIMEZONE: string;
  WORK_START_HOUR: string;
  WORK_END_HOUR: string;
  WORK_DAYS: string;
}, timeZoneOverride?: string): WorkHours {
  const startHour = Number(env.WORK_START_HOUR);
  const endHour = Number(env.WORK_END_HOUR);
  const days = parseWorkDays(env.WORK_DAYS);
  return {
    timeZone: timeZoneOverride || env.TIMEZONE || "UTC",
    startHour: Number.isFinite(startHour) ? startHour : 8,
    endHour: Number.isFinite(endHour) ? endHour : 18,
    days: days.length ? days : [1, 2, 3, 4, 5],
  };
}

export function zonedClock(date: Date, timeZone: string): {
  weekday: number;
  hour: number;
  minute: number;
} {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "short",
    hour: "numeric",
    minute: "numeric",
    hourCycle: "h23",
  }).formatToParts(date);

  const value = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? "";

  let hour = Number(value("hour"));
  if (hour === 24) hour = 0;

  return {
    weekday: WEEKDAY_TO_JS[value("weekday")] ?? 0,
    hour,
    minute: Number(value("minute")),
  };
}

/** True during [startHour, endHour) on configured weekdays in the given zone. */
export function isWorkHours(date: Date, hours: WorkHours): boolean {
  const clock = zonedClock(date, hours.timeZone);
  if (!hours.days.includes(clock.weekday)) return false;
  const minutes = clock.hour * 60 + clock.minute;
  return minutes >= hours.startHour * 60 && minutes < hours.endHour * 60;
}

export type MicStatus = "busy" | "free" | "offline";
export type DisplayStatus = "busy" | "free" | "offline" | "sleep";

export function displayStatus(mic: MicStatus, inHours: boolean): DisplayStatus {
  if (!inHours) return "sleep";
  return mic;
}
