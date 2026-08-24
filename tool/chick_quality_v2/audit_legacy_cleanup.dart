import 'dart:io';

import 'legacy_cleanup_audit.dart';

const _registryPath = 'tool/agent_schema/station_registry.json';
const _evidencePath = 'tool/chick_quality_v2/legacy_cleanup_evidence.json';
const _reportPath =
    'docs/reviews/2026-08-24-chick-quality-v2-phase-5-cleanup-audit.md';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      (arguments.single != '--check' && arguments.single != '--write')) {
    stderr.writeln(
      'Usage: dart run tool/chick_quality_v2/audit_legacy_cleanup.dart '
      '--check|--write',
    );
    exitCode = 64;
    return;
  }

  final root = Directory.current;
  final result = await auditLegacyCleanup(
    repositoryRoot: root,
    registryFile: File('${root.path}/$_registryPath'),
    evidenceFile: File('${root.path}/$_evidencePath'),
  );
  final rendered = result.toMarkdown();
  final report = File('${root.path}/$_reportPath');

  if (arguments.single == '--write') {
    await report.parent.create(recursive: true);
    await report.writeAsString(rendered);
    stdout.writeln(
      'Wrote $_reportPath (${result.tokenMentions.length} token mentions; '
      '${result.registryDrivenConsumers.length} registry-driven consumers; '
      'removalEligible=${result.removalEligible}).',
    );
    return;
  }

  if (!report.existsSync() || await report.readAsString() != rendered) {
    stderr.writeln(
      'Chick Quality V2 Phase 5 cleanup report is missing or stale: '
      '$_reportPath',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Chick Quality V2 Phase 5 cleanup report is current '
    '(${result.tokenMentions.length} token mentions; '
    '${result.registryDrivenConsumers.length} registry-driven consumers; '
    'removalEligible=${result.removalEligible}).',
  );
}
