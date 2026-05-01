import 'database_factory_initializer_stub.dart'
    if (dart.library.js_interop) 'database_factory_initializer_web.dart'
    as impl;

Future<void> initializeDatabaseFactory() => impl.initializeDatabaseFactory();
