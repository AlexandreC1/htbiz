import 'dart:js_interop';

@JS('navigator.onLine')
external bool get _browserOnline;

// Browsers do not expose DNS lookup. This is a connection hint, not proof
// that the backend is healthy; individual requests handle server failures.
Future<bool> networkAvailable() async => _browserOnline;
