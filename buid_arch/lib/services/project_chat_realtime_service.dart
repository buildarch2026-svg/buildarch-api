import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_configuration.dart';
import 'auth_api_service.dart';

class ProjectChatRealtimeService {
  ProjectChatRealtimeService({
    required this.token,
    required this.channelName,
    required this.onMessage,
    required this.onStatusChanged,
    ApiConfiguration? configuration,
  })  : _configuration = configuration ?? ApiConfiguration.fromEnvironment(),
        _appKey = const String.fromEnvironment('REVERB_APP_KEY'),
        _host = const String.fromEnvironment('REVERB_HOST'),
        _port = int.tryParse(const String.fromEnvironment('REVERB_PORT')),
        _scheme = const String.fromEnvironment('REVERB_SCHEME');

  final String token;
  final String channelName;
  final void Function(Map<String, dynamic> message) onMessage;
  final void Function(String? status) onStatusChanged;
  final ApiConfiguration _configuration;
  final String _appKey;
  final String _host;
  final int? _port;
  final String _scheme;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  bool _disposed = false;
  bool _connecting = false;
  bool _subscribed = false;

  Future<void> connect() async {
    if (_disposed || _connecting || _subscribed) return;
    _connecting = true;
    _retryTimer?.cancel();
    try {
      final uri = _configuration.resolveChatSocket(
        appKey: _appKey,
        host: _host,
        port: _port,
        scheme: _scheme,
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 10));
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _subscription = channel.stream.listen(
        _handleEvent,
        onError: (Object error) => _connectionLost(error),
        onDone: () => _connectionLost(null),
        cancelOnError: true,
      );
    } on Object catch (error) {
      _connectionLost(error);
    } finally {
      _connecting = false;
    }
  }

  Future<void> _handleEvent(dynamic rawEvent) async {
    if (rawEvent is! String || _disposed) return;
    try {
      final decoded = jsonDecode(rawEvent);
      if (decoded is! Map) return;
      final event = Map<String, dynamic>.from(decoded);
      final eventName = event['event'];
      final data = _decodeData(event['data']);

      if (eventName == 'pusher:ping') {
        _channel?.sink.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
        return;
      }
      if (eventName == 'pusher:connection_established') {
        final socketId = data['socket_id'];
        if (socketId is! String) {
          throw const FormatException('The WebSocket connection was invalid.');
        }
        final auth = await AuthApiService.instance.authenticateChatChannel(
          token: token,
          socketId: socketId,
          channelName: channelName,
        );
        final signature = auth['auth'];
        if (signature is! String) {
          throw const FormatException('The chat channel response was invalid.');
        }
        _channel?.sink.add(jsonEncode({
          'event': 'pusher:subscribe',
          'data': {'channel': channelName, 'auth': signature},
        }));
        return;
      }
      if (eventName == 'pusher_internal:subscription_succeeded') {
        _subscribed = true;
        onStatusChanged(null);
        return;
      }
      if (eventName == 'chat.message.changed') {
        final message = data['message'];
        if (message is Map) {
          onMessage(Map<String, dynamic>.from(message));
        }
        return;
      }
      if (eventName == 'pusher:error') {
        throw AuthApiException(
          data['message'] is String
              ? data['message'] as String
              : 'The live chat connection was rejected.',
        );
      }
    } on Object catch (error) {
      _connectionLost(error);
    }
  }

  Map<String, dynamic> _decodeData(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }

  void _connectionLost(Object? error) {
    if (_disposed) return;
    _subscribed = false;
    final message = error is AuthApiException
        ? error.message
        : 'Live updates are unavailable; chat will refresh periodically.';
    onStatusChanged(message);
    unawaited(_subscription?.cancel());
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close());
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 10), connect);
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }
}
