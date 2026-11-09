/// Where the cast code writes its log lines. The app sends them to its
/// journal (debugPrint); the cast test tool (`tool/cast_test.dart`) to the
/// console. Kept free of Flutter so that tool compiles on its own.
void Function(String line) castLog = print;
