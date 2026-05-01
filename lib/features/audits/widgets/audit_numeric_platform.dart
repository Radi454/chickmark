import 'audit_numeric_platform_stub.dart'
    if (dart.library.html) 'audit_numeric_platform_web.dart'
    as impl;

bool auditNumericWebPrefersSystemKeyboard() =>
    impl.auditNumericWebPrefersSystemKeyboard();
