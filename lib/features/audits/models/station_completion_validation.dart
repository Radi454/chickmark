enum StationCompletionStatus {
  complete,
  savedButIncomplete,
  emptyOrDiscarded,
  failed,
}

class StationCompletionValidation {
  final StationCompletionStatus status;
  final String stationKey;
  final String message;

  const StationCompletionValidation({
    required this.status,
    required this.stationKey,
    required this.message,
  });

  bool get canNavigate => status != StationCompletionStatus.failed;
  bool get shouldMarkCompleted => status == StationCompletionStatus.complete;
  bool get needsIncompleteConfirmation =>
      status == StationCompletionStatus.savedButIncomplete ||
      status == StationCompletionStatus.emptyOrDiscarded;

  static StationCompletionValidation complete(String stationKey) =>
      StationCompletionValidation(
        status: StationCompletionStatus.complete,
        stationKey: stationKey,
        message: 'Station complete.',
      );

  static StationCompletionValidation savedButIncomplete(
    String stationKey,
  ) => StationCompletionValidation(
    status: StationCompletionStatus.savedButIncomplete,
    stationKey: stationKey,
    message:
        'This station has saved data but not enough core data to mark complete.',
  );

  static StationCompletionValidation emptyOrDiscarded(
    String stationKey,
  ) => StationCompletionValidation(
    status: StationCompletionStatus.emptyOrDiscarded,
    stationKey: stationKey,
    message:
        'This station has no core data to mark complete. Blank rows were cleared.',
  );

  static StationCompletionValidation failed(String stationKey) =>
      StationCompletionValidation(
        status: StationCompletionStatus.failed,
        stationKey: stationKey,
        message: 'Could not save station. Try again.',
      );
}
