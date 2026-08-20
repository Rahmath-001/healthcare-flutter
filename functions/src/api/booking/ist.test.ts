import { describe, expect, it } from "vitest";

import { slotLockId } from "../db";
import { istCalendarDate, istMidnightUtcMs, istWeekday, parseSlotId } from "./routes";

/**
 * Availability arithmetic.
 *
 * This is the logic most likely to break silently and least likely to be
 * noticed in review: Cloud Functions runs in UTC, so anchoring a doctor's hours
 * to server-local time looks perfectly correct on an Indian development machine
 * and shifts every clinic by 5.5 hours in production. The README claimed this
 * was verified by hand under two TZ settings; a claim with no test behind it
 * survives exactly until someone refactors.
 *
 * `process.env.TZ` is deliberately not set anywhere here — every function under
 * test must be independent of it, and if any of them ever reads local time
 * these assertions fail on some machines and not others.
 */
describe("IST calendar handling", () => {
  it("reads a calendar date out of a string without parsing an instant", () => {
    expect(istCalendarDate("2026-03-15")).toEqual({ y: 2026, m: 3, d: 15 });
  });

  it("rejects anything that is not a plain calendar date", () => {
    expect(istCalendarDate("2026-3-15")).toBeNull();
    expect(istCalendarDate("15/03/2026")).toBeNull();
    expect(istCalendarDate("")).toBeNull();
  });

  it("refuses an instant where a calendar day is meant", () => {
    // 20:00 UTC on the 15th is already the 16th in IST. Reading the text day
    // out of a timestamp would return the wrong day's slots, so the whole
    // shape is rejected rather than interpreted.
    expect(istCalendarDate("2026-03-15T10:00:00Z")).toBeNull();
    expect(istCalendarDate("2026-03-15T20:00:00Z")).toBeNull();
    expect(istCalendarDate("2026-03-15 ")).toBeNull();
  });

  it("refuses a date that does not exist", () => {
    // Date.UTC rolls these forward instead of failing.
    expect(istCalendarDate("2026-13-01")).toBeNull();
    expect(istCalendarDate("2026-00-10")).toBeNull();
    expect(istCalendarDate("2026-04-31")).toBeNull();
    expect(istCalendarDate("2026-02-29")).toBeNull();
    expect(istCalendarDate("2028-02-29")).toEqual({ y: 2028, m: 2, d: 29 });
  });

  it("places IST midnight at 18:30 UTC the previous day", () => {
    const ms = istMidnightUtcMs({ y: 2026, m: 3, d: 15 });
    expect(new Date(ms).toISOString()).toBe("2026-03-14T18:30:00.000Z");
  });

  it("maps Sunday to 7, not 0", () => {
    // 2026-03-15 is a Sunday in IST. JS getUTCDay() returns 0 for Sunday while
    // Dart's DateTime.weekday returns 7, and the rules are stored Dart-style —
    // so a naive conversion makes every Sunday rule dead.
    expect(istWeekday(istMidnightUtcMs({ y: 2026, m: 3, d: 15 }))).toBe(7);
    expect(istWeekday(istMidnightUtcMs({ y: 2026, m: 3, d: 16 }))).toBe(1);
    expect(istWeekday(istMidnightUtcMs({ y: 2026, m: 3, d: 21 }))).toBe(6);
  });

  it("keeps the IST weekday across the UTC day boundary", () => {
    // 20:00 UTC on the 14th is 01:30 IST on the 15th — a Sunday. Reading this
    // in UTC would report Saturday and offer the wrong doctor's hours.
    const instant = Date.UTC(2026, 2, 14, 20, 0);
    expect(istWeekday(instant)).toBe(7);
  });

  it("agrees with an explicit IST rendering for a whole week", () => {
    for (let d = 15; d <= 21; d++) {
      const ms = istMidnightUtcMs({ y: 2026, m: 3, d });
      const rendered = new Date(ms).toLocaleDateString("en-GB", {
        timeZone: "Asia/Kolkata",
        day: "2-digit",
      });
      expect(rendered).toBe(String(d).padStart(2, "0"));
    }
  });
});

/**
 * Slot ids.
 *
 * The id is not a label — it is the concurrency control. Two phones booking the
 * same slot address the same document, which is what lets a Firestore
 * transaction serialise them the way a Postgres exclusion constraint would.
 */
describe("slot ids", () => {
  it("round-trips a doctor id and a start instant", () => {
    const start = new Date(Date.UTC(2026, 2, 15, 4, 30));
    const id = slotLockId("d1", start);
    expect(parseSlotId(id)).toEqual({ doctorId: "d1", startMs: start.getTime() });
  });

  it("is deterministic — the same slot always yields the same id", () => {
    const start = new Date(Date.UTC(2026, 2, 15, 4, 30));
    expect(slotLockId("d1", start)).toBe(slotLockId("d1", new Date(start)));
  });

  it("distinguishes doctors and times", () => {
    const start = new Date(Date.UTC(2026, 2, 15, 4, 30));
    const later = new Date(start.getTime() + 60_000);
    expect(slotLockId("d1", start)).not.toBe(slotLockId("d2", start));
    expect(slotLockId("d1", start)).not.toBe(slotLockId("d1", later));
  });

  it("splits on the last separator, so a doctor id may contain one", () => {
    const parsed = parseSlotId("clinic__north__1773546600000");
    expect(parsed.doctorId).toBe("clinic__north");
    expect(parsed.startMs).toBe(1773546600000);
  });

  it("refuses a malformed id rather than inventing a slot", () => {
    expect(() => parseSlotId("nonsense")).toThrow();
    expect(() => parseSlotId("d1__notanumber")).toThrow();
    expect(() => parseSlotId("")).toThrow();
  });
});
