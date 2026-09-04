import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate/vrlizate.dart';

void main() {
  group('VrPairingPayload', () {
    test('generates the canonical vrlizate pair URI', () {
      final payload = VrPairingPayload(
        host: '192.168.1.20',
        port: 4242,
        sessionToken: 'session-abc',
        role: VrDeviceRole.parent,
        transportType: VrTransportType.localSocket,
      );

      expect(
        payload.toUri().toString(),
        'vrlizate://pair?host=192.168.1.20&port=4242&token=session-abc'
        '&role=parent&transport=localSocket',
      );
    });

    test('round-trips every URI field and enum', () {
      final original = VrPairingPayload(
        host: 'visor.local',
        port: 8765,
        sessionToken: 'token with spaces/+',
        role: VrDeviceRole.child,
        transportType: VrTransportType.bluetoothLe,
        deviceName: 'Moto G de control',
        bleServiceUuid: '12345678-1234-5678-1234-56789abcdef0',
      );

      final decoded = VrPairingPayload.fromUri(original.toUri());

      expect(decoded, original);
      expect(decoded.host, 'visor.local');
      expect(decoded.port, 8765);
      expect(decoded.sessionToken, 'token with spaces/+');
      expect(decoded.role, VrDeviceRole.child);
      expect(decoded.transportType, VrTransportType.bluetoothLe);
      expect(decoded.deviceName, 'Moto G de control');
      expect(decoded.bleServiceUuid, '12345678-1234-5678-1234-56789abcdef0');
    });

    test('round-trips through JSON', () {
      final original = VrPairingPayload(
        host: '10.0.0.7',
        port: 5555,
        sessionToken: 'secure-token',
        role: VrDeviceRole.parent,
        transportType: VrTransportType.wifiDirect,
        deviceName: 'VRlizate visor',
      );

      expect(VrPairingPayload.fromJson(original.toJson()), original);
    });

    test('rejects malformed scheme and endpoint descriptively', () {
      expect(
        () => VrPairingPayload.fromUri(
          Uri.parse(
            'https://pair?host=127.0.0.1&port=8080&token=t&role=parent'
            '&transport=localSocket',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('scheme'),
          ),
        ),
      );
      expect(
        () => VrPairingPayload.fromUri(
          Uri.parse(
            'vrlizate://connect?host=127.0.0.1&port=8080&token=t'
            '&role=parent&transport=localSocket',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('endpoint'),
          ),
        ),
      );
    });

    test('rejects every missing required URI parameter', () {
      const required = <String>['host', 'port', 'token', 'role', 'transport'];
      const values = <String, String>{
        'host': '127.0.0.1',
        'port': '8080',
        'token': 't',
        'role': 'parent',
        'transport': 'localSocket',
      };

      for (final missing in required) {
        final query = <String, String>{...values}..remove(missing);
        final uri = Uri(
          scheme: VrPairingPayload.uriScheme,
          host: VrPairingPayload.uriEndpoint,
          queryParameters: query,
        );

        expect(
          () => VrPairingPayload.fromUri(uri),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('"$missing"'),
            ),
          ),
          reason: 'Expected missing $missing to be rejected.',
        );
      }
    });

    test('rejects invalid port, role, and transport values', () {
      Uri pairingUri({
        String port = '8080',
        String role = 'parent',
        String transport = 'localSocket',
      }) => Uri(
        scheme: 'vrlizate',
        host: 'pair',
        queryParameters: <String, String>{
          'host': '127.0.0.1',
          'port': port,
          'token': 't',
          'role': role,
          'transport': transport,
        },
      );

      expect(
        () => VrPairingPayload.fromUri(pairingUri(port: 'not-a-port')),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('port'),
          ),
        ),
      );
      expect(
        () => VrPairingPayload.fromUri(pairingUri(role: 'controller')),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('role'),
          ),
        ),
      );
      expect(
        () => VrPairingPayload.fromUri(pairingUri(transport: 'infrared')),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('transport'),
          ),
        ),
      );
    });
  });
}
