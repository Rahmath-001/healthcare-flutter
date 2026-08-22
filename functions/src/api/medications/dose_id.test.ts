import { describe, expect, it } from "vitest";

import { daysBetween, istDay, parseDoseId } from "./routes";

/**
 * The dose id and the calendar arithmetic behind it.
 *
 * Both are the kind of thing that works perfectly on an Indian dev machine and
 * is wrong in production: Cloud Functions runs in UTC, so anything that reads
 * a calendar day out of an instant without saying which timezone it means is
 * five and a half hours off for part of every day.
 */
describe("dose ids", () => {
  it("round-trips a well-formed id", () => {
    expect(parseDoseId("p3#0#2026-06-10#MORNING")).toEqual({
      prescriptionId: "p3",
      itemIndex: 0,
      day: "2026-06-10",
      slot: "MORNING",
    });
  });

  it("refuses anything malformed", () => {
    // The id is user input on the path *and* the document id. A lenient parse
    // is a way to write documents whose ids do not mean what the collection
    // assumes they mean.
    for (const bad of [
      "",
      "p3#0#2026-06-10",
      "p3#0#2026-06-10#MORNING#extra",
      "p3#-1#2026-06-10#MORNING",
      "p3#x#2026-06-10#MORNING",
      "p3#0#10-06-2026#MORNING",
      "p3#0#2026-06-10#LUNCHTIME",
      "#0#2026-06-10#MORNING",
    ]) {
      expect(() => parseDoseId(bad), bad).toThrow();
    }
  });

  it("does not accept a fractional item index", () => {
    expect(() => parseDoseId("p3#0.5#2026-06-10#NIGHT")).toThrow();
  });
});

describe("IST calendar days", () => {
  it("reads the Indian day, not the UTC one", () => {
    // 20:00 UTC is already the next day in India. A server reading its own
    // local day would file the dose against yesterday for every evening dose
    // in the country.
    expect(istDay(new Date("2026-06-10T20:00:00Z"))).toBe("2026-06-11");
    expect(istDay(new Date("2026-06-10T18:29:00Z"))).toBe("2026-06-10");
    expect(istDay(new Date("2026-06-10T18:30:00Z"))).toBe("2026-06-11");
  });

  it("counts whole days between calendar dates", () => {
    expect(daysBetween("2026-06-01", "2026-06-10")).toBe(9);
    expect(daysBetween("2026-06-10", "2026-06-10")).toBe(0);
    // Negative means the first date is later — which is how a future dose is
    // detected.
    expect(daysBetween("2026-06-11", "2026-06-10")).toBe(-1);
  });

  it("counts across a month and a year boundary", () => {
    expect(daysBetween("2026-01-31", "2026-02-01")).toBe(1);
    expect(daysBetween("2025-12-31", "2026-01-01")).toBe(1);
    // 2028 is a leap year, so February has 29 days.
    expect(daysBetween("2028-02-28", "2028-03-01")).toBe(2);
  });
});
