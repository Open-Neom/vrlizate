import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/core/network/vr_controller_transport.dart';
import 'package:vrlizate/core/network/vr_local_socket_transport.dart';

void main() {
  test(
    'VrLocalSocketTransport drops hostile unauthenticated stream exceeding maxMessageCharacters without newline',
    () async {
      final cappedVisor = VrLocalSocketTransport(maxMessageCharacters: 256);
      try {
        final invitation = await cappedVisor.listen(
          advertisedHost: '127.0.0.1',
          bindHost: '127.0.0.1',
          sessionToken: 'token',
        );
        final rawSocket = await Socket.connect(
          invitation.host,
          invitation.port,
        );
        try {
          rawSocket.add(utf8.encode('A' * 1024));
          await rawSocket.flush();
          final deadline = DateTime.now().add(const Duration(seconds: 2));
          while (cappedVisor.state != VrTransportConnectionState.listening) {
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException('Condition was not reached.');
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(cappedVisor.isListening, isTrue);
          expect(cappedVisor.isConnected, isFalse);
        } finally {
          await rawSocket.close();
        }
      } finally {
        await cappedVisor.dispose();
      }
    },
  );
}
