import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";

import type { NotificationPreferencesDoc } from "../db";
import { allows, isQuiet, istHour, istWhen } from "./send";

/**
 * The delivery rules.
 *
 * These are the decisions that are wrong in a way nobody notices: a quiet
 * window evaluated in UTC silences the afternoon instead of the night, and a
 * mandatory kind that respects a toggle means a patient can opt out of the only
 * warning that their consultation was cancelled.
 */
const prefs = (
  over: Partial<NotificationPreferencesDoc> = {}
): NotificationPreferencesDoc => ({
  enabled: ["APPOINTMENT_REMINDER", "PRESCRIPTION_ISSUED"],
  quietHours: { startHour: 22, endHour: 7 },
  updatedAt: Timestamp.now(),
  ...over,
});

/** An instant that is `hour` in IST. */
const atIst = (hour: number) =>
  new Date(Date.UTC(2026, 7, 23, hour, 0) - 5.5 * 60 * 60 * 1000);

describe("IST arithmetic", () => {
  it("reads the hour in IST, not UTC", () => {
    // 18:30 UTC is midnight IST. A UTC-based quiet-hours check would call this
    // the middle of the working day.
    expect(istHour(new Date("2026-08-23T18:30:00Z"))).toBe(0);
    expect(istHour(new Date("2026-08-23T05:30:00Z"))).toBe(11);
  });

  it("formats a time the way a patient reads it", () => {
    expect(istWhen(new Date("2026-08-23T11:00:00Z"))).toBe("23 Aug at 4:30 PM");
    // Straddles the date line: 20:00 UTC is already the 24th in India.
    expect(istWhen(new Date("2026-08-23T20:00:00Z"))).toBe("24 Aug at 1:30 AM");
  });
});

describe("quiet hours", () => {
  const night = { startHour: 22, endHour: 7 };

  it("wraps past midnight", () => {
    // The case a naive `hour >= start && hour < end` gets exactly backwards.
    expect(isQuiet(night, atIst(23))).toBe(true);
    expect(isQuiet(night, atIst(2))).toBe(true);
    expect(isQuiet(night, atIst(6))).toBe(true);
  });

  it("is open during the day", () => {
    expect(isQuiet(night, atIst(7))).toBe(false);
    expect(isQuiet(night, atIst(15))).toBe(false);
    expect(isQuiet(night, atIst(21))).toBe(false);
  });

  it("handles a same-day window", () => {
    const siesta = { startHour: 13, endHour: 16 };
    expect(isQuiet(siesta, atIst(14))).toBe(true);
    expect(isQuiet(siesta, atIst(12))).toBe(false);
    expect(isQuiet(siesta, atIst(16))).toBe(false);
  });

  it("treats an equal start and end as disabled", () => {
    // Otherwise "quiet from 0 to 0" silences the entire day, which is not what
    // anyone setting both to the same value means.
    expect(isQuiet({ startHour: 0, endHour: 0 }, atIst(3))).toBe(false);
  });
});

describe("what gets delivered", () => {
  it("sends an enabled kind during the day", () => {
    expect(allows(prefs(), "APPOINTMENT_REMINDER", atIst(10))).toBe(true);
  });

  it("holds an ordinary kind during quiet hours", () => {
    expect(allows(prefs(), "APPOINTMENT_REMINDER", atIst(23))).toBe(false);
  });

  it("drops a kind the user turned off", () => {
    expect(allows(prefs(), "RECORD_READY", atIst(10))).toBe(false);
  });

  it("sends an appointment change at 3am anyway", () => {
    // The whole point. Finding out at 9am that you travelled to a cancelled
    // 8am consultation is worse than being woken at 3.
    expect(allows(prefs(), "APPOINTMENT_CHANGED", atIst(3))).toBe(true);
  });

  it("sends a mandatory kind even when it is absent from the enabled list",
    () => {
      // A client that omits it — by accident, or by a user who found a way to
      // untick it — must not be able to silence a cancellation.
      expect(allows(prefs({ enabled: [] }), "APPOINTMENT_CHANGED", atIst(15)))
        .toBe(true);
      expect(allows(prefs({ enabled: [] }), "ACCOUNT_UPDATE", atIst(15)))
        .toBe(true);
    });

  it("still respects the toggle for everything else", () => {
    expect(allows(prefs({ enabled: [] }), "PRESCRIPTION_ISSUED", atIst(15)))
      .toBe(false);
  });
});
