class EggCountCaptureResult {
  const EggCountCaptureResult({required this.count, required this.photos});

  final int count;
  final List<String> photos;

  bool get isEmpty => count <= 0 && photos.isEmpty;
}
