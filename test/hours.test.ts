import { describe, expect, it } from "vitest";
import { displayStatus, isWorkHours, workHoursFromEnv, zonedClock } from "../src/hours";

const nyHours = {
  timeZone: "America/New_York",
  startHour: 8,
  endHour: 18,
  days: [1, 2, 3, 4, 5],
};

describe("work hours", () => {
  it("treats Monday 8:00am New York as in hours", () => {
    // 2026-08-17 is a Monday; 12:00 UTC is 08:00 EDT.
    const date = new Date("2026-08-17T12:00:00.000Z");
    expect(zonedClock(date, "America/New_York")).toMatchObject({ weekday: 1, hour: 8, minute: 0 });
    expect(isWorkHours(date, nyHours)).toBe(true);
  });

  it("treats Monday 7:59am as outside hours", () => {
    expect(isWorkHours(new Date("2026-08-17T11:59:00.000Z"), nyHours)).toBe(false);
  });

  it("treats Monday 5:59pm as in hours and 6:00pm as sleep", () => {
    expect(isWorkHours(new Date("2026-08-17T21:59:00.000Z"), nyHours)).toBe(true);
    expect(isWorkHours(new Date("2026-08-17T22:00:00.000Z"), nyHours)).toBe(false);
  });

  it("sleeps all weekend", () => {
    expect(isWorkHours(new Date("2026-08-16T16:00:00.000Z"), nyHours)).toBe(false);
    expect(isWorkHours(new Date("2026-08-15T16:00:00.000Z"), nyHours)).toBe(false);
  });

  it("maps display to sleep outside hours even if the mic is busy", () => {
    expect(displayStatus("busy", false)).toBe("sleep");
    expect(displayStatus("free", false)).toBe("sleep");
    expect(displayStatus("offline", false)).toBe("sleep");
    expect(displayStatus("busy", true)).toBe("busy");
    expect(displayStatus("free", true)).toBe("free");
    expect(displayStatus("offline", true)).toBe("offline");
  });

  it("parses env defaults for Mon-Fri 8-18", () => {
    const hours = workHoursFromEnv({
      TIMEZONE: "Europe/London",
      WORK_START_HOUR: "8",
      WORK_END_HOUR: "18",
      WORK_DAYS: "1,2,3,4,5",
    });
    expect(hours).toEqual({
      timeZone: "Europe/London",
      startHour: 8,
      endHour: 18,
      days: [1, 2, 3, 4, 5],
    });
  });
});
