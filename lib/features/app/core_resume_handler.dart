/// Desktop platforms keep its foreground core alive while another window has focus.
class CoreResumeHandler {
  CoreResumeHandler({required this.isDesktop});

  final bool isDesktop;
  Future<void>? _initialization;

  Future<void> resume(Future<void> Function() initialize) {
    if (!isDesktop) return initialize();
    return _initialization ??= Future<void>.sync(initialize);
  }
}
