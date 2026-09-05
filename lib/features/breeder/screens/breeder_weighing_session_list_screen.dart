import 'package:hatchaudit/localized_material.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/breeder_weighing_session_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/repositories/breeder_weighing_session_repository.dart';
import '../../../widgets/section_card.dart';
import 'breeder_weighing_session_entry_screen.dart';

/// Weighing-session list for one flock (breeder-flock-performance ticket
/// 13, design doc section 5.1 and 9). A separate workflow from the daily
/// report list — a weighing session is never a row inside a daily report.
class BreederWeighingSessionListScreen extends StatefulWidget {
  final FlockModel flock;
  final BreederWeighingSessionRepository? repository;

  const BreederWeighingSessionListScreen({
    super.key,
    required this.flock,
    this.repository,
  });

  @override
  State<BreederWeighingSessionListScreen> createState() =>
      _BreederWeighingSessionListScreenState();
}

class _BreederWeighingSessionListScreenState
    extends State<BreederWeighingSessionListScreen> {
  late final BreederWeighingSessionRepository _repository =
      widget.repository ?? BreederWeighingSessionRepository();
  late Future<List<BreederWeighingSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _repository.listForFlock(widget.flock.id);
  }

  void _reload() {
    setState(() {
      _sessionsFuture = _repository.listForFlock(widget.flock.id);
    });
  }

  Future<void> _createSession() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BreederWeighingSessionEntryScreen(flock: widget.flock),
      ),
    );
    if (mounted) _reload();
  }

  void _openSession(BreederWeighingSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BreederWeighingSessionEntryScreen(
          flock: widget.flock,
          session: session,
        ),
      ),
    ).then((_) {
      if (mounted) _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Weighing — ${widget.flock.flockId}',
        actions: [
          IconButton(
            tooltip: context.tr('New session'),
            icon: const Icon(Icons.add),
            onPressed: _createSession,
          ),
        ],
      ),
      body: FutureBuilder<List<BreederWeighingSession>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data ?? const [];
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Text(
                  context.tr(
                    'No weighing sessions yet. Tap + to record one.',
                  ),
                  style: AppTextStyles.body,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.cardPadding),
                child: SectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      HatchDateUtils.formatDisplayDate(session.sessionDate),
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${_sexLabel(session.sex)} · ${session.method} · '
                      '${session.sampleSize} birds',
                    ),
                    trailing: session.hasDerivedFigures
                        ? Text('${session.derivedMeanWeightG} g')
                        : Text(context.tr('Summary only')),
                    onTap: () => _openSession(session),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _sexLabel(String sex) => sex == BreederWeighingSessionSex.female
      ? context.tr('Female')
      : context.tr('Male');
}
