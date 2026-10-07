import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What went wrong, in terms the UI can branch on.
enum AppErrorKind {
  /// No usable connection, DNS failure, or the request exceeded its deadline.
  network,

  /// Nobody is signed in, or the session expired and could not be refreshed.
  unauthenticated,

  /// Signed in, but not allowed to do this.
  forbidden,

  /// The row is gone (or was never visible to this user).
  notFound,

  /// The write collides with something that already exists.
  duplicate,

  /// The server rejected the payload — a CHECK constraint, a bad value.
  invalid,

  /// A file was too large or of an unsupported type.
  tooLarge,

  /// Anything we could not classify.
  unknown,
}

/// A failure that is safe to show to a user.
///
/// The whole app used to render `'Error: $e'`, which put raw PostgREST
/// payloads ("new row violates row-level security policy for table
/// \"businesses\"") in front of end users. Services throw this instead, so
/// those same call sites now read correctly without touching every screen.
class AppException implements Exception {
  const AppException(this.kind, this.message, {this.cause, this.code});

  final AppErrorKind kind;

  /// Already user-facing. Do not prefix it with "Error:" — it reads as a
  /// sentence on its own.
  final String message;

  /// The original throwable, for logging. Never shown.
  final Object? cause;

  /// Postgres SQLSTATE or HTTP status, when we have one. Useful for logs.
  final String? code;

  bool get isRetryable => kind == AppErrorKind.network;

  @override
  String toString() => message;

  /// Map anything thrown by the Supabase client into an [AppException].
  factory AppException.from(Object error, {String? whileDoing}) {
    if (error is AppException) return error;

    if (error is TimeoutException) {
      return AppException(
        AppErrorKind.network,
        'HTBiz took too long to respond. Please try again.',
        cause: error,
      );
    }

    if (error is SocketException ||
        error is HttpException ||
        error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return AppException(
        AppErrorKind.network,
        'Could not reach HTBiz. Check your connection or try again shortly.',
        cause: error,
      );
    }

    if (error is GoogleSignInException) {
      return AppException(
        AppErrorKind.unknown,
        'Google sign-in is unavailable right now. Please try again or use email.',
        cause: error,
      );
    }

    if (error is AuthException) {
      final message = switch (error.code) {
        'invalid_credentials' => 'The email or password is incorrect.',
        'email_not_confirmed' => 'Please verify your email before signing in.',
        'weak_password' => 'Please choose a stronger password.',
        'over_request_rate_limit' ||
        'over_email_send_rate_limit' =>
          'Please wait a moment before trying again.',
        'session_expired' ||
        'refresh_token_not_found' ||
        'refresh_token_already_used' =>
          'Your session has expired. Please sign in again.',
        _ => 'We could not complete that request. Please try again shortly.',
      };
      return AppException(
        AppErrorKind.unauthenticated,
        message,
        cause: error,
        code: error.code ?? error.statusCode,
      );
    }

    if (error is StorageException) {
      final status = error.statusCode;
      if (status == '413' || error.message.contains('exceeded the maximum')) {
        return AppException(
          AppErrorKind.tooLarge,
          'That file is too large. Please choose a smaller image.',
          cause: error,
          code: status,
        );
      }
      if (status == '403' || status == '401') {
        return AppException(
          AppErrorKind.forbidden,
          'You do not have permission to upload that file.',
          cause: error,
          code: status,
        );
      }
      if (error.message.contains('mime type')) {
        return AppException(
          AppErrorKind.invalid,
          'That file type is not supported. Use a JPG, PNG or WEBP image.',
          cause: error,
          code: status,
        );
      }
      return AppException(
        AppErrorKind.unknown,
        'The upload failed. Please try again.',
        cause: error,
        code: status,
      );
    }

    if (error is PostgrestException) {
      final code = error.code ?? '';
      switch (code) {
        case '23505': // unique_violation
          return AppException(
            AppErrorKind.duplicate,
            'That has already been saved.',
            cause: error,
            code: code,
          );
        case '23503': // foreign_key_violation
          return AppException(
            AppErrorKind.notFound,
            'That item no longer exists.',
            cause: error,
            code: code,
          );
        case '23514': // check_violation
          return AppException(
            AppErrorKind.invalid,
            'Some of that information is not valid. Please review and try again.',
            cause: error,
            code: code,
          );
        case '42501': // insufficient_privilege — our RLS + guard triggers
          return AppException(
            AppErrorKind.forbidden,
            'You do not have permission to do that.',
            cause: error,
            code: code,
          );
        case 'PGRST116': // .single() matched zero rows
          return AppException(
            AppErrorKind.notFound,
            'That item could not be found.',
            cause: error,
            code: code,
          );
        case 'PGRST301': // JWT expired
          return AppException(
            AppErrorKind.unauthenticated,
            'Your session has expired. Please sign in again.',
            cause: error,
            code: code,
          );
      }

      // RLS denials arrive as 42501 above, but an INSERT blocked by a missing
      // policy comes back as a plain message with no code.
      if (error.message.contains('row-level security')) {
        return AppException(
          AppErrorKind.forbidden,
          'You do not have permission to do that.',
          cause: error,
          code: code,
        );
      }

      return AppException(
        AppErrorKind.unknown,
        whileDoing == null
            ? 'Something went wrong. Please try again.'
            : 'Could not $whileDoing. Please try again.',
        cause: error,
        code: code,
      );
    }

    return AppException(
      AppErrorKind.unknown,
      whileDoing == null
          ? 'Something went wrong. Please try again.'
          : 'Could not $whileDoing. Please try again.',
      cause: error,
    );
  }
}

/// Wraps every outbound call with a deadline, bounded retries and error
/// translation.
///
/// Connections in Haiti are frequently slow rather than absent: without a
/// deadline the Supabase client waits on the OS socket timeout, which is
/// minutes, and the user sits on a spinner that never resolves.
class Net {
  Net._();

  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(seconds: 60);
  // Requests default to one attempt because a timed-out write may already have
  // committed. Safe reads opt into retries at their call sites.
  static const int defaultAttempts = 1;

  /// Run [action], retrying only failures that a retry can actually fix.
  ///
  /// A 403 or a constraint violation is deterministic — retrying it just makes
  /// the user wait three times as long for the same error.
  static Future<T> call<T>(
    Future<T> Function() action, {
    Duration timeout = defaultTimeout,
    int attempts = defaultAttempts,
    String? whileDoing,
  }) async {
    if (attempts < 1) {
      throw ArgumentError.value(attempts, 'attempts', 'Must be at least 1');
    }

    AppException? last;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await action().timeout(timeout);
      } catch (error, stack) {
        final failure = AppException.from(error, whileDoing: whileDoing);
        last = failure;

        if (!failure.isRetryable || attempt == attempts) {
          if (kDebugMode) {
            debugPrint('[Net] ${failure.kind.name} (${failure.code}): $error');
            debugPrintStack(stackTrace: stack, maxFrames: 6);
          }
          throw failure;
        }

        // 400ms, 800ms, 1600ms — short enough not to feel stuck.
        await Future<void>.delayed(
            Duration(milliseconds: 400 * (1 << (attempt - 1))));
      }
    }

    throw last ??
        const AppException(AppErrorKind.unknown, 'Something went wrong.');
  }

  /// Same as [call], but returns [fallback] instead of throwing.
  ///
  /// Use only where a failure genuinely has no consequence (like a like count),
  /// never to hide a failed write.
  static Future<T> callOr<T>(
    Future<T> Function() action,
    T fallback, {
    Duration timeout = defaultTimeout,
    int attempts = 2,
  }) async {
    try {
      return await call(action, timeout: timeout, attempts: attempts);
    } on AppException {
      return fallback;
    }
  }
}
