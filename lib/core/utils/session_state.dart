/// Live state of the receiver session.
///
/// Defined in its own file so that [EncryptionService] can import it without
/// creating a circular dependency with [SessionManager].
///
/// Consumers that already import [SessionManager] get this enum for free via
/// its `export` directive — no extra import needed.
enum SessionState {
  /// Mailbox open — normal operation.
  open,

  /// A transfer is in progress; session close is blocked by the PopScope guard.
  locked,

  /// Decryption is running on the receiver side.
  decrypting,

  /// Kill switch fired — keys wiped, session over.
  terminated,
}
