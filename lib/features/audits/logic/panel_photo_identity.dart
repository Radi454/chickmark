/// Returns the real panel-row id used by photo records.
///
/// A freshly-created station sample has its own short id, so the save path
/// composes the full row id. After reopening, reconstruction deliberately
/// stores the already-persisted row id on the station sample; reusing it here
/// keeps photos stable even though the UI draft id is regenerated.
String panelRowIdForPhoto({
  required String sessionId,
  required String panelName,
  required String draftId,
  required String stationSampleId,
}) {
  final persistedPrefix = '$sessionId:$panelName:';
  if (stationSampleId.startsWith(persistedPrefix)) return stationSampleId;
  return '$persistedPrefix$draftId:$stationSampleId';
}
