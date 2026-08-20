/// Date, time and money formatting.
///
/// Hand-rolled rather than pulled from `intl` so that Phase 1 stays free of a
/// localisation dependency it cannot yet use properly. When Hindi lands in
/// Phase 7 these become thin wrappers over `DateFormat` with a locale.
abstract final class Fmt {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// "12 Mar 2026"
  static String date(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// "12 Mar"
  static String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  /// "Tue"
  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  /// "4:30 PM"
  static String time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Today, 4:30 PM" / "Tomorrow, 9:00 AM" / "12 Mar, 4:30 PM"
  ///
  /// Relative labels only for the days people actually think about relatively;
  /// beyond that an absolute date is clearer than "in 9 days".
  static String dateTime(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;

    final label = switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => '${weekday(d)}, ${dayMonth(d)}',
    };
    return '$label, ${time(d)}';
  }

  /// "in 2 days" / "3 hours ago"
  static String relative(DateTime d) {
    final diff = d.difference(DateTime.now());
    final future = !diff.isNegative;
    final abs = diff.abs();

    final unit = switch (abs) {
      _ when abs.inMinutes < 1 => 'just now',
      _ when abs.inMinutes < 60 =>
        '${abs.inMinutes} minute${abs.inMinutes == 1 ? '' : 's'}',
      _ when abs.inHours < 24 =>
        '${abs.inHours} hour${abs.inHours == 1 ? '' : 's'}',
      _ when abs.inDays < 30 =>
        '${abs.inDays} day${abs.inDays == 1 ? '' : 's'}',
      _ => '${(abs.inDays / 30).floor()} month'
          '${(abs.inDays / 30).floor() == 1 ? '' : 's'}',
    };

    if (unit == 'just now') return unit;
    return future ? 'in $unit' : '$unit ago';
  }

  /// Countdown for slot holds and consent expiry: "9:58" or "2d 4h".
  static String countdown(Duration d) {
    if (d.inDays >= 1) {
      final hours = d.inHours % 24;
      return '${d.inDays}d ${hours}h';
    }
    if (d.inHours >= 1) {
      final minutes = d.inMinutes % 60;
      return '${d.inHours}h ${minutes}m';
    }
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// "45 min"
  static String duration(Duration d) {
    if (d.inHours >= 1) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours} hr' : '${d.inHours} hr $m min';
    }
    return '${d.inMinutes} min';
  }

  /// Indian digit grouping: 1,23,456 rather than 123,456.
  static String rupees(int amount) {
    final s = amount.toString();
    if (s.length <= 3) return 'Rs $s';

    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    return 'Rs ${groups.join(',')},$last3';
  }
}
