import 'package:flutter/foundation.dart';

import '../../providers_search/domain/doctor.dart';

/// A simple time of day, kept independent of any particular date so a weekly
/// rule can be expressed without inventing an arbitrary calendar day.
@immutable
class TimeOfDayValue implements Comparable<TimeOfDayValue> {
  const TimeOfDayValue(this.hour, this.minute);

  final int hour;
  final int minute;

  int get totalMinutes => hour * 60 + minute;

  String format() {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m ${hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  int compareTo(TimeOfDayValue other) =>
      totalMinutes.compareTo(other.totalMinutes);

  @override
  bool operator ==(Object other) =>
      other is TimeOfDayValue && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// A recurring weekly availability window.
///
/// Times are always Asia/Kolkata. India has no daylight saving, which removes
/// an entire category of scheduling bug — but the timezone is still explicit so
/// that assumption is recorded rather than accidental.
@immutable
class AvailabilityRule {
  const AvailabilityRule({
    required this.id,
    required this.weekday,
    required this.start,
    required this.end,
    required this.mode,
    required this.slotMinutes,
    this.isActive = true,
  });

  final String id;

  /// 1 = Monday through 7 = Sunday, matching DateTime.weekday.
  final int weekday;

  final TimeOfDayValue start;
  final TimeOfDayValue end;
  final ConsultationMode mode;
  final int slotMinutes;
  final bool isActive;

  static const weekdayNames = <int, String>{
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  String get weekdayName => weekdayNames[weekday] ?? 'Unknown';

  int get slotCount {
    final span = end.totalMinutes - start.totalMinutes;
    return span <= 0 ? 0 : span ~/ slotMinutes;
  }

  bool get isValid => end.totalMinutes > start.totalMinutes;

  /// Times cross the wire as minutes past midnight IST, not as clock strings.
  /// An integer has no format to disagree about and no timezone to lose.
  factory AvailabilityRule.fromJson(Map<String, dynamic> json) {
    TimeOfDayValue at(int minutes) =>
        TimeOfDayValue(minutes ~/ 60, minutes % 60);

    return AvailabilityRule(
      id: json['id'] as String,
      weekday: (json['weekday'] as num).toInt(),
      start: at((json['startMinutes'] as num).toInt()),
      end: at((json['endMinutes'] as num).toInt()),
      mode: ConsultationMode.fromWire(json['mode'] as String?),
      slotMinutes: (json['slotMinutes'] as num).toInt(),
      isActive: json['active'] as bool? ?? true,
    );
  }

  AvailabilityRule copyWith({
    TimeOfDayValue? start,
    TimeOfDayValue? end,
    ConsultationMode? mode,
    int? slotMinutes,
    bool? isActive,
  }) =>
      AvailabilityRule(
        id: id,
        weekday: weekday,
        start: start ?? this.start,
        end: end ?? this.end,
        mode: mode ?? this.mode,
        slotMinutes: slotMinutes ?? this.slotMinutes,
        isActive: isActive ?? this.isActive,
      );
}

/// A one-off change to the weekly pattern: a day off, or extra hours.
@immutable
class AvailabilityException {
  const AvailabilityException({
    required this.id,
    required this.date,
    required this.isBlocked,
    this.start,
    this.end,
    this.reason,
  });

  final String id;
  final DateTime date;

  /// True blocks the day; false adds an extra window.
  final bool isBlocked;

  final TimeOfDayValue? start;
  final TimeOfDayValue? end;
  final String? reason;

  factory AvailabilityException.fromJson(Map<String, dynamic> json) {
    TimeOfDayValue? at(Object? minutes) => minutes == null
        ? null
        : TimeOfDayValue((minutes as num).toInt() ~/ 60, minutes.toInt() % 60);

    // `date` is a plain calendar day, parsed as such. Treating it as an instant
    // shifts it either side of midnight depending on the reader's timezone.
    final parts = (json['date'] as String).split('-').map(int.parse).toList();

    return AvailabilityException(
      id: json['id'] as String,
      date: DateTime(parts[0], parts[1], parts[2]),
      isBlocked: json['isBlocked'] as bool? ?? true,
      start: at(json['startMinutes']),
      end: at(json['endMinutes']),
      reason: json['reason'] as String?,
    );
  }
}
