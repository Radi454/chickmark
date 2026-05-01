import 'dart:js_interop';

import 'audit_numeric_browser_policy.dart';

@JS('window')
external JSObject get _windowObject;

extension type _Window._(JSObject _) implements JSObject {
  external _Navigator get navigator;

  external _MediaQueryList matchMedia(String query);
}

extension type _Navigator._(JSObject _) implements JSObject {
  external String get platform;

  external String get userAgent;
}

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

bool auditNumericWebPrefersSystemKeyboard() {
  try {
    final window = _Window._(_windowObject);
    return auditNumericBrowserPrefersSystemKeyboard(
      platform: window.navigator.platform,
      userAgent: window.navigator.userAgent,
      hasDesktopPointer: window
          .matchMedia('(hover: hover) and (pointer: fine)')
          .matches,
    );
  } catch (_) {
    return false;
  }
}
