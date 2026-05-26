// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

bool get isAdminMode {
  final url = html.window.location.href;
  final port = html.window.location.port;
  return port == '3001' || url.contains('/admin');
}

void clearWebHistory() {
  try {
    html.window.history.replaceState(null, '', '/');
  } catch (e) {
    // Ignore error
  }
}
