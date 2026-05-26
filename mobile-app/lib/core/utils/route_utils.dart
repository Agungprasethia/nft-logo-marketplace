export 'route_utils_stub.dart'
    if (dart.library.html) 'route_utils_web.dart'
    if (dart.library.io) 'route_utils_mobile.dart';
