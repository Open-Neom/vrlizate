import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../input/vr_input_event_bus.dart';
import 'vr_controller_protocol.dart';
import 'vr_controller_transport.dart';
import 'vr_pairing_payload.dart';

/// Reference parent/child transport over a newline-framed local TCP socket.
///
/// This implementation is intentionally LAN-first. The pairing token is
/// authenticated during the handshake, but traffic is not encrypted; callers
/// that cross an untrusted network must provide a secure tunnel or another
/// [VrControllerTransport].
class VrLocalSocketTransport implements VrControllerTransport {
  static const bool isSupported = true;
  static const int defaultMaxMessageCharacters = 64 * 1024;

  final Duration authenticationTimeout;
  final Duration latencyTimeout;
  final int maxMessageCharacters;
  final VrControllerMessageCodec _codec;

  final StreamController<VrTransportConnectionState> _stateController =
      StreamController<VrTransportConnectionState>.broadcast(sync: true);
  final StreamController<VrControllerProfile> _profileController =
      StreamController<VrControllerProfile>.broadcast(sync: true);
  final StreamController<VrRemotePoseFrame> _poseController =
      StreamController<VrRemotePoseFrame>.broadcast(sync: true);
  final StreamController<VrInputEvent> _eventController =
      StreamController<VrInputEvent>.broadcast(sync: true);
  final StreamController<Duration> _latencyController =
      StreamController<Duration>.broadcast(sync: true);

  ServerSocket? _server;
  Socket? _socket;
  StreamSubscription<Socket>? _acceptSubscription;
  StreamSubscription<String>? _lineSubscription;
  Timer? _authenticationTimer;
  Completer<void>? _readyCompleter;
  String? _expectedSessionToken;
  bool _hostMode = false;
  bool _authenticated = false;
  bool _disposed = false;
  int _nextPingId = 1;
  final Map<int, Completer<Duration>> _pendingPings =
      <int, Completer<Duration>>{};

  VrTransportConnectionState _state = VrTransportConnectionState.disconnected;

  VrLocalSocketTransport({
    this.authenticationTimeout = const Duration(seconds: 5),
    this.latencyTimeout = const Duration(seconds: 2),
    this.maxMessageCharacters = defaultMaxMessageCharacters,
    VrControllerMessageCodec codec = const VrControllerMessageCodec(),
  }) : _codec = codec {
    if (authenticationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        authenticationTimeout,
        'authenticationTimeout',
        'Must be positive.',
      );
    }
    if (latencyTimeout <= Duration.zero) {
      throw ArgumentError.value(
        latencyTimeout,
        'latencyTimeout',
        'Must be positive.',
      );
    }
    if (maxMessageCharacters <= 0) {
      throw ArgumentError.value(
        maxMessageCharacters,
        'maxMessageCharacters',
        'Must be positive.',
      );
    }
  }

  @override
  VrTransportConnectionState get state => _state;

  @override
  Stream<VrTransportConnectionState> get onState => _stateController.stream;

  @override
  Stream<VrControllerProfile> get onProfile => _profileController.stream;

  @override
  Stream<VrRemotePoseFrame> get onPose => _poseController.stream;

  @override
  Stream<VrInputEvent> get onEvent => _eventController.stream;

  @override
  Stream<Duration> get onLatency => _latencyController.stream;

  bool get isListening => _server != null;
  bool get isConnected => _authenticated && _socket != null;

  /// Starts the visor as a single-controller server and returns its invitation.
  Future<VrPairingPayload> listen({
    required String advertisedHost,
    String bindHost = '0.0.0.0',
    int port = 0,
    required String sessionToken,
    String? deviceName,
  }) async {
    _ensureAlive();
    if (_server != null || _socket != null) {
      throw StateError('Transport is already active.');
    }

    // Reuse payload validation before opening a network resource.
    VrPairingPayload(
      host: advertisedHost,
      port: port == 0 ? 1 : port,
      sessionToken: sessionToken,
      role: VrDeviceRole.parent,
      transportType: VrTransportType.localSocket,
      deviceName: deviceName,
    );

    final server = await ServerSocket.bind(bindHost, port);
    _server = server;
    _hostMode = true;
    _expectedSessionToken = sessionToken;
    _setState(VrTransportConnectionState.listening);
    _acceptSubscription = server.listen(
      _acceptClient,
      onError: _handleServerError,
      onDone: () {
        _server = null;
        if (_socket == null && !_disposed) {
          _setState(VrTransportConnectionState.disconnected);
        }
      },
      cancelOnError: false,
    );

    return VrPairingPayload(
      host: advertisedHost,
      port: server.port,
      sessionToken: sessionToken,
      role: VrDeviceRole.parent,
      transportType: VrTransportType.localSocket,
      deviceName: deviceName,
    );
  }

  @override
  Future<void> connect(VrPairingPayload payload) async {
    _ensureAlive();
    if (payload.transportType != VrTransportType.localSocket) {
      throw ArgumentError.value(
        payload.transportType,
        'payload',
        'VrLocalSocketTransport requires localSocket.',
      );
    }
    if (_server != null || _socket != null) {
      throw StateError('Transport is already active.');
    }

    _hostMode = false;
    _setState(VrTransportConnectionState.connecting);
    try {
      final socket = await Socket.connect(
        payload.host,
        payload.port,
        timeout: authenticationTimeout,
      );
      _attachSocket(socket);
      _readyCompleter = Completer<void>();
      _setState(VrTransportConnectionState.authenticating);
      await _sendMessage(
        VrHelloMessage(
          sessionToken: payload.sessionToken,
          role: VrDeviceRole.child,
          deviceName: payload.deviceName,
        ),
      );
      await _readyCompleter!.future.timeout(authenticationTimeout);
    } catch (error) {
      await _dropSocket();
      if (!_disposed) _setState(VrTransportConnectionState.error);
      rethrow;
    } finally {
      _readyCompleter = null;
    }
  }

  void _acceptClient(Socket socket) {
    if (_disposed || _socket != null) {
      socket.destroy();
      return;
    }
    _authenticated = false;
    _attachSocket(socket);
    _setState(VrTransportConnectionState.authenticating);
    _authenticationTimer?.cancel();
    _authenticationTimer = Timer(authenticationTimeout, () {
      if (!_authenticated) {
        _sendMessage(
          VrErrorMessage(
            code: 'authentication_timeout',
            message: 'Controller did not authenticate in time.',
          ),
        ).whenComplete(_dropSocket);
      }
    });
  }

  void _attachSocket(Socket socket) {
    _socket = socket;
    socket.setOption(SocketOption.tcpNoDelay, true);
    _lineSubscription = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: _handleSocketError,
          onDone: _handleSocketDone,
          cancelOnError: false,
        );
  }

  void _handleLine(String line) {
    if (line.length > maxMessageCharacters) {
      _protocolFailure(
        'message_too_large',
        'Message exceeded $maxMessageCharacters characters.',
      );
      return;
    }

    VrControllerMessage message;
    try {
      message = _codec.decode(line);
    } on Object catch (error) {
      _protocolFailure('malformed_message', 'Malformed message: $error');
      return;
    }

    if (!_authenticated) {
      _handleHandshake(message);
      return;
    }
    _handleAuthenticatedMessage(message);
  }

  void _handleHandshake(VrControllerMessage message) {
    if (_hostMode && message is VrHelloMessage) {
      if (message.protocolVersion != vrControllerProtocolVersion) {
        _protocolFailure(
          'unsupported_protocol',
          'Expected protocol $vrControllerProtocolVersion.',
        );
        return;
      }
      if (message.role != VrDeviceRole.child ||
          !_constantTimeEquals(
            message.sessionToken,
            _expectedSessionToken ?? '',
          )) {
        _protocolFailure(
          'authentication_failed',
          'Invalid pairing token or role.',
        );
        return;
      }
      _authenticated = true;
      _authenticationTimer?.cancel();
      _authenticationTimer = null;
      _sendMessage(const VrReadyMessage());
      _setState(VrTransportConnectionState.connected);
      return;
    }

    if (!_hostMode && message is VrReadyMessage) {
      if (message.protocolVersion != vrControllerProtocolVersion) {
        final error = StateError(
          'Unsupported controller protocol ${message.protocolVersion}.',
        );
        _readyCompleter?.completeError(error);
        _dropSocket();
        return;
      }
      _authenticated = true;
      _setState(VrTransportConnectionState.connected);
      _readyCompleter?.complete();
      return;
    }

    if (message is VrErrorMessage) {
      final error = StateError('${message.code}: ${message.message}');
      if (_readyCompleter?.isCompleted == false) {
        _readyCompleter?.completeError(error);
      }
      _dropSocket();
      return;
    }

    _protocolFailure(
      'unexpected_handshake_message',
      'Expected a hello/ready handshake message.',
    );
  }

  void _handleAuthenticatedMessage(VrControllerMessage message) {
    switch (message) {
      case VrProfileMessage(:final profile):
        if (profile.protocolVersion != vrControllerProtocolVersion) {
          _protocolFailure(
            'unsupported_profile',
            'Unsupported profile version ${profile.protocolVersion}.',
          );
          return;
        }
        _profileController.add(profile);
      case VrPoseMessage(:final frame):
        _poseController.add(frame);
      case VrInputMessage(:final event):
        _eventController.add(event.toEvent());
      case VrPingMessage(:final id, :final sentTimestampMicroseconds):
        _sendMessage(
          VrPongMessage(
            id: id,
            sentTimestampMicroseconds: sentTimestampMicroseconds,
            responseTimestampMicroseconds: _nowMicroseconds(),
          ),
        );
      case VrPongMessage(:final id, :final sentTimestampMicroseconds):
        final completer = _pendingPings.remove(id);
        if (completer != null && !completer.isCompleted) {
          final elapsed = Duration(
            microseconds: _nowMicroseconds() - sentTimestampMicroseconds,
          );
          completer.complete(elapsed);
          _latencyController.add(elapsed);
        }
      case VrDisconnectMessage():
        _dropSocket();
      case VrErrorMessage(:final code, :final message):
        _eventController.addError(StateError('$code: $message'));
      case VrHelloMessage() || VrReadyMessage():
        _protocolFailure(
          'unexpected_message',
          'Handshake messages cannot be repeated.',
        );
    }
  }

  void _protocolFailure(String code, String message) {
    final socket = _socket;
    if (socket == null) return;
    final encoded = _codec.encode(VrErrorMessage(code: code, message: message));
    socket.write(encoded);
    socket.write('\n');
    socket.flush().whenComplete(_dropSocket);
  }

  @override
  Future<void> sendProfile(VrControllerProfile profile) =>
      _sendMessage(VrProfileMessage(profile));

  @override
  Future<void> sendPose(VrRemotePoseFrame frame) =>
      _sendMessage(VrPoseMessage(frame));

  @override
  Future<void> sendEvent(VrInputEvent event) {
    // Capture the pooled event synchronously before returning a Future.
    final snapshot = VrInputEventSnapshot.fromEvent(event);
    return _sendMessage(VrInputMessage(snapshot));
  }

  @override
  Future<Duration> measureLatency() {
    _ensureConnected();
    final id = _nextPingId++;
    final completer = Completer<Duration>();
    _pendingPings[id] = completer;
    final sentAt = _nowMicroseconds();
    _sendMessage(
      VrPingMessage(id: id, sentTimestampMicroseconds: sentAt),
    ).catchError((Object error, StackTrace stackTrace) {
      _pendingPings.remove(id);
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });
    return completer.future.timeout(
      latencyTimeout,
      onTimeout: () {
        _pendingPings.remove(id);
        throw TimeoutException('Controller latency measurement timed out.');
      },
    );
  }

  Future<void> _sendMessage(VrControllerMessage message) {
    _ensureConnected(
      allowHandshake:
          message is VrHelloMessage ||
          message is VrReadyMessage ||
          message is VrErrorMessage,
    );
    final socket = _socket!;
    // Encoding occurs before the Future is returned, so no borrowed event or
    // mutable vector crosses the asynchronous boundary.
    final encoded = _codec.encode(message);
    if (encoded.length > maxMessageCharacters) {
      throw StateError(
        'Encoded controller message exceeds $maxMessageCharacters characters.',
      );
    }
    socket.write(encoded);
    socket.write('\n');
    return socket.flush();
  }

  void _handleServerError(Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _setState(VrTransportConnectionState.error);
      _stateController.addError(error, stackTrace);
    }
  }

  void _handleSocketError(Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _eventController.addError(error, stackTrace);
      if (_readyCompleter?.isCompleted == false) {
        _readyCompleter?.completeError(error, stackTrace);
      }
    }
  }

  void _handleSocketDone() {
    if (_readyCompleter?.isCompleted == false) {
      _readyCompleter?.completeError(
        StateError('Socket closed before authentication completed.'),
      );
    }
    _dropSocket();
  }

  Future<void> _dropSocket() async {
    _authenticationTimer?.cancel();
    _authenticationTimer = null;
    _authenticated = false;
    final subscription = _lineSubscription;
    _lineSubscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    socket?.destroy();
    for (final completer in _pendingPings.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Controller disconnected.'));
      }
    }
    _pendingPings.clear();
    if (!_disposed) {
      _setState(
        _server == null
            ? VrTransportConnectionState.disconnected
            : VrTransportConnectionState.listening,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    if (isConnected) {
      try {
        await _sendMessage(
          const VrDisconnectMessage(reason: 'Local disconnect.'),
        );
      } on Object {
        // The peer may already be gone.
      }
    }
    await _dropSocket();
    final acceptSubscription = _acceptSubscription;
    _acceptSubscription = null;
    await acceptSubscription?.cancel();
    final server = _server;
    _server = null;
    await server?.close();
    _hostMode = false;
    _expectedSessionToken = null;
    _setState(VrTransportConnectionState.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await Future.wait<void>(<Future<void>>[
      _stateController.close(),
      _profileController.close(),
      _poseController.close(),
      _eventController.close(),
      _latencyController.close(),
    ]);
  }

  void _setState(VrTransportConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('VrLocalSocketTransport is disposed.');
  }

  void _ensureConnected({bool allowHandshake = false}) {
    _ensureAlive();
    if (_socket == null || (!allowHandshake && !_authenticated)) {
      throw StateError('VrLocalSocketTransport is not connected.');
    }
  }

  static int _nowMicroseconds() => DateTime.now().microsecondsSinceEpoch;

  static bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var difference = leftBytes.length ^ rightBytes.length;
    final length = leftBytes.length > rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var i = 0; i < length; i++) {
      final leftByte = i < leftBytes.length ? leftBytes[i] : 0;
      final rightByte = i < rightBytes.length ? rightBytes[i] : 0;
      difference |= leftByte ^ rightByte;
    }
    return difference == 0;
  }
}
