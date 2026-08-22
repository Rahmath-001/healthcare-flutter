import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../features/appointments/domain/appointment.dart';
import '../../features/appointments/presentation/appointments_controller.dart';
import '../../features/notifications/presentation/notifications_controller.dart';
import '../../features/providers_search/domain/doctor.dart';
import '../../l10n/l10n.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/app_motion.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/skeleton.dart';

/// The patient's landing screen.
///
/// It used to be a greeting card and four tiles, which meant the first screen
/// after sign-in answered none of the two questions someone opens a health app
/// to ask: *when is my appointment* and *how do I see a doctor*. The next
/// appointment is now the largest thing on the page and the search entry sits
/// directly under the greeting; the tiles are demoted to what they always were,
/// which is navigation.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(nextAppointmentProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(patientAppointmentsProvider.future),
          child: CustomScrollView(
            // Always scrollable, so pull-to-refresh works on a short page. A
            // refresh gesture that only responds once you have enough content
            // to scroll is a gesture users learn does not exist.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Greeting()),
              const SliverToBoxAdapter(child: _SearchEntry()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.gutter,
                  Insets.xl,
                  Insets.gutter,
                  0,
                ),
                sliver: SliverList.list(
                  children: [
                    SectionHeader(
                      title: context.l10n.homeNextAppointment,
                      actionLabel: context.l10n.navAppointments,
                      onAction: () => context.go(Routes.patientAppointments),
                    ),
                    const SizedBox(height: Insets.md),
                    AsyncView<Appointment?>(
                      value: upcoming,
                      onRetry: () =>
                          ref.invalidate(patientAppointmentsProvider),
                      skeleton: Skeleton.rect(height: 148),
                      data: (appointment) => appointment == null
                          ? const _NothingBooked()
                          : _NextAppointmentCard(appointment: appointment),
                    ),
                    const SizedBox(height: Insets.xl),
                    SectionHeader(title: context.l10n.homeQuickActions),
                    const SizedBox(height: Insets.md),
                  ],
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  Insets.gutter,
                  0,
                  Insets.gutter,
                  Insets.xxl,
                ),
                sliver: _QuickActionsGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The soonest upcoming appointment, or null.
///
/// Derived from the list the Appointments tab already watches rather than
/// fetched separately, so opening Home does not cost a second round trip and
/// the two screens can never disagree about what is next.
final nextAppointmentProvider = FutureProvider<Appointment?>((ref) async {
  final all = await ref.watch(patientAppointmentsProvider.future);
  final upcoming = all.where((a) => a.status.isUpcoming).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return upcoming.isEmpty ? null : upcoming.first;
});

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final theme = Theme.of(context);
    final name = session?.greetingName ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Insets.lg,
        Insets.gutter,
        0,
      ),
      child: FadeSlideIn(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _partOfDay(context),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    context.l10n.homeGreeting(name),
                    style: theme.textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.sm),
            _NotificationBell(),
            const SizedBox(width: Insets.xs),
            // The avatar is the profile entry point every other app on the
            // phone puts here. Wrapped in a 48pt tap target rather than left as
            // a bare image, and labelled, because an unlabelled photo is
            // announced as "button" and nothing else.
            Semantics(
              button: true,
              label: context.l10n.profileTitle,
              child: InkWell(
                onTap: () => context.go(Routes.patientProfile),
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(Insets.xs),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    backgroundImage: session?.photoUrl != null
                        ? NetworkImage(session!.photoUrl!)
                        : null,
                    child: session?.photoUrl != null
                        ? null
                        : Text(
                            _initials(name),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Initials beat a generic person icon: it is the difference between "an
  /// account" and "your account", and it costs nothing to render.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  static String _partOfDay(BuildContext context) {
    final hour = DateTime.now().hour;
    final l10n = context.l10n;
    if (hour < 12) return l10n.homeGoodMorning;
    if (hour < 17) return l10n.homeGoodAfternoon;
    return l10n.homeGoodEvening;
  }
}

/// A tap target that looks like a search field but is not one.
///
/// Deliberately not a live `TextField`: focusing it here would open the
/// keyboard on a screen with no results to show, and the real search screen
/// owns the debounce, the filters and the cancellation token.
class _SearchEntry extends StatelessWidget {
  const _SearchEntry();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Insets.gutter,
        Insets.gutter,
        0,
      ),
      child: FadeSlideIn(
        index: 1,
        child: Semantics(
          button: true,
          label: context.l10n.homeFindDoctor,
          excludeSemantics: true,
          child: Material(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: Radii.pillAll,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.go(Routes.doctorSearch),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.gutter,
                  vertical: Insets.lg,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: theme.colorScheme.primary),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Text(
                        context.l10n.homeFindDoctor,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.tune,
                      size: 20,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero card. The only place on Home that uses the brand colour as a fill.
class _NextAppointmentCard extends StatelessWidget {
  const _NextAppointmentCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = appointment;
    final joinable = a.canJoinConsultation;

    return FadeSlideIn(
      index: 2,
      child: PressableScale(
        child: Material(
          color: scheme.primaryContainer,
          shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('${Routes.patientAppointments}/${a.id}'),
            child: Padding(
              padding: const EdgeInsets.all(Insets.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DateBlock(date: a.start),
                      const SizedBox(width: Insets.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.doctor.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onPrimaryContainer,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              a.doctor.specialtyLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.75),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: Insets.sm),
                            Row(
                              children: [
                                Icon(
                                  _modeIcon(a.mode),
                                  size: 16,
                                  color: scheme.onPrimaryContainer
                                      .withValues(alpha: 0.75),
                                ),
                                const SizedBox(width: Insets.xs + 2),
                                Expanded(
                                  child: Text(
                                    a.mode.label,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onPrimaryContainer
                                          .withValues(alpha: 0.75),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  // Countdown, not just a timestamp. "in 2 hours" is the thing
                  // someone glancing at their phone in a waiting room needs;
                  // the exact time is one line up in the date block.
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color:
                            scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: Insets.xs + 2),
                      Expanded(
                        child: Text(
                          Fmt.relative(a.start),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                      Text(
                        '#${a.referenceCode}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              scheme.onPrimaryContainer.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  if (joinable) ...[
                    const SizedBox(height: Insets.lg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.push(
                          '/patient/consultation/${a.consultationId}',
                        ),
                        icon: const Icon(Icons.videocam, size: 20),
                        label: Text(context.l10n.actionJoin),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _modeIcon(ConsultationMode mode) => switch (mode) {
        ConsultationMode.inPerson => Icons.person_outline,
        ConsultationMode.video => Icons.videocam_outlined,
        ConsultationMode.audio => Icons.call_outlined,
      };
}

/// Day-of-month over month, the way a calendar tear-off reads.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: Insets.md),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.65),
        borderRadius: Radii.mdAll,
      ),
      child: Column(
        children: [
          Text(
            Fmt.weekday(date).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            date.day.toString(),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              height: 1.1,
            ),
          ),
          Text(
            Fmt.time(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the hero card when nothing is booked.
///
/// Carries the action rather than only the news: an empty state whose whole
/// content is "nothing here" leaves the user to work out what to do about it.
class _NothingBooked extends StatelessWidget {
  const _NothingBooked();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FadeSlideIn(
      index: 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Insets.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.event_available_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: Insets.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.homeNoUpcoming,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.homeNoUpcomingBody,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go(Routes.doctorSearch),
                  child: Text(context.l10n.actionBook),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tones = context.tones;

    final actions = <_QuickActionData>[
      _QuickActionData(
        icon: Icons.folder_shared_outlined,
        label: l10n.homeQuickRecords,
        tone: tones.info,
        container: tones.infoContainer,
        route: Routes.patientRecords,
        replaceStack: true,
      ),
      _QuickActionData(
        icon: Icons.receipt_long_outlined,
        label: l10n.homeQuickPrescriptions,
        tone: tones.success,
        container: tones.successContainer,
        route: Routes.prescriptions,
        replaceStack: true,
      ),
      _QuickActionData(
        icon: Icons.medication_outlined,
        label: l10n.homeQuickMedicines,
        tone: tones.warning,
        container: tones.warningContainer,
        route: Routes.medications,
        replaceStack: true,
      ),
      _QuickActionData(
        icon: Icons.shield_outlined,
        label: l10n.homeQuickSharing,
        tone: Theme.of(context).colorScheme.primary,
        container: Theme.of(context).colorScheme.primaryContainer,
        route: Routes.sharing,
      ),
      _QuickActionData(
        icon: Icons.support_agent_outlined,
        label: l10n.homeQuickSupport,
        tone: tones.neutral,
        container: tones.neutralContainer,
        route: Routes.supportTickets,
      ),
    ];

    // One column on a very narrow phone. At 320dp two tiles plus the gutters
    // leave 130dp per label, which wraps "Who can see my records" to four
    // lines and pushes it out of the tile.
    final oneColumn = MediaQuery.sizeOf(context).width < Breakpoints.compact;

    // Measured, not guessed. A grid cell is a fixed height, so a hard-coded
    // one is a fixed *overflow* the moment the OS font size goes up — and a
    // widget test caught exactly that at 116. This derives the height from the
    // label's actual line height at the user's current text scale.
    const iconBlock = 40.0;
    final labelBlock =
        MediaQuery.textScalerOf(context).scale(14.5) * 1.45 * _labelLines;
    final extent = oneColumn
        ? Insets.lg * 2 + (labelBlock < iconBlock ? iconBlock : labelBlock)
        : Insets.lg * 2 + iconBlock + Insets.md + labelBlock;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: oneColumn ? 1 : 2,
        mainAxisSpacing: Insets.md,
        crossAxisSpacing: Insets.md,
        mainAxisExtent: extent,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => FadeSlideIn(
          index: 3 + i,
          child: _QuickAction(data: actions[i], horizontal: oneColumn),
        ),
        childCount: actions.length,
      ),
    );
  }
}

/// How many lines a quick-action label is allowed to take.
///
/// Two: "Who can see my records" needs them, and a third would make the grid
/// taller than the section it belongs to.
const _labelLines = 2;

class _QuickActionData {
  const _QuickActionData({
    required this.icon,
    required this.label,
    required this.tone,
    required this.container,
    required this.route,
    this.replaceStack = false,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final Color container;
  final String route;

  /// True for destinations that are shell branches of their own: those switch
  /// the tab rather than stacking a page the back button has to unwind.
  final bool replaceStack;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.data, required this.horizontal});

  final _QuickActionData data;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: data.container, shape: BoxShape.circle),
      child: Icon(data.icon, size: 20, color: data.tone),
    );

    final label = Text(
      data.label,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    return PressableScale(
      child: Card(
        child: InkWell(
          onTap: () => data.replaceStack
              ? context.go(data.route)
              : context.push(data.route),
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: horizontal
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: Insets.lg),
                      Expanded(child: label),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(height: Insets.md),
                      // Flexible as well as measured: the height above is
                      // right for this font, and this is what keeps a
                      // stretched system font from overflowing anyway.
                      Flexible(child: label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The notification entry point, with its unread count.
///
/// Lives on Home rather than in a tab of its own: a fifth tab for something
/// that is usually empty spends permanent screen space on an occasional need,
/// and the bell is where every other app on the phone has taught people to
/// look.
class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Semantics(
      button: true,
      // Counted out loud. A bare "notifications, button" tells a screen-reader
      // user nothing about whether it is worth opening.
      label: unread == 0
          ? l10n.notificationsTitle
          : '${l10n.notificationsTitle}, $unread',
      excludeSemantics: true,
      child: IconButton(
        onPressed: () => context.push(Routes.notifications),
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: Icon(
            unread > 0
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
