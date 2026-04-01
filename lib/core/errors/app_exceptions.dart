/// Base exception for all app-level errors.
/// Use typed subclasses so callers can catch specific failure modes.
class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Thrown for Firebase Auth or Firestore auth-related failures.
class AuthException extends AppException {
  const AuthException(super.message, {super.code});
}

/// Thrown when a transfer document operation fails.
class TransferException extends AppException {
  const TransferException(super.message, {super.code});
}

/// Thrown for RSA / AES cryptographic failures.
class CryptoException extends AppException {
  const CryptoException(super.message, {super.code});
}

/// Thrown for Firestore / Storage network failures.
class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

/// Thrown when a required key (RSA private/public) is missing.
class KeyNotFoundException extends AppException {
  const KeyNotFoundException(super.message, {super.code});
}
