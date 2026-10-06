import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:htbiz/services/app_exception.dart';

void main() {
  test('failed token refresh over the network does not become session expiry',
      () {
    final error = AppException.from(AuthRetryableFetchException(
      message:
          'SocketException: Failed host lookup: private-project.supabase.co',
    ));
    expect(error.kind, AppErrorKind.network);
    expect(error.isRetryable, isTrue);
    expect(error.message, isNot(contains('expired')));
    expect(error.message, isNot(contains('supabase.co')));
  });

  test('Google configuration details never reach user-facing copy', () {
    final error = AppException.from(const GoogleSignInException(
      code: GoogleSignInExceptionCode.clientConfigurationError,
      description: 'serverClientId=internal-client; SHA certificate mismatch',
    ));
    expect(error.message, contains('use email'));
    expect(error.message, isNot(contains('serverClientId')));
    expect(error.message, isNot(contains('SHA')));
  });

  test('incorrect credentials get actionable text', () {
    final error = AppException.from(const AuthException(
      'Internal auth payload',
      code: 'invalid_credentials',
    ));
    expect(error.message, 'The email or password is incorrect.');
  });

  test('unclassified failures are not retried as if they were network errors',
      () {
    expect(
      const AppException(AppErrorKind.unknown, 'Something went wrong.')
          .isRetryable,
      isFalse,
    );
  });

  test('ambiguous writes are attempted once unless retries are opted into',
      () async {
    var calls = 0;
    await expectLater(
      Net.call<void>(() async {
        calls++;
        throw const SocketException('connection dropped after request');
      }),
      throwsA(isA<AppException>()),
    );
    expect(calls, 1);
  });
}
