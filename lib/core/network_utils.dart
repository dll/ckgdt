import 'dart:io';

import 'error_handler.dart';

class NetworkUtils {
  static Future<String> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'NetworkUtils', stack: st);
    }
    return '127.0.0.1';
  }
}
