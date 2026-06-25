/// Result of KeyRepository.scanForStaleKeys() — what key material exists
/// for the current account that no longer belongs to an active session.
class StaleKeyScanResult {
  final bool hasStaleRsaSession;
  final List<String> staleTransferIds;

  const StaleKeyScanResult({
    required this.hasStaleRsaSession,
    required this.staleTransferIds,
  });

  bool get isClean => !hasStaleRsaSession && staleTransferIds.isEmpty;
}
