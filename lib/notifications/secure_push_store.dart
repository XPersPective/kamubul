import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:napp_core/napp_core.dart';

import 'push_registration.dart';

/// Android Keystore/no-backup dosyası; iOS ThisDeviceOnly Keychain.
class SecurePushStore implements PushStateStore {
  SecurePushStore._(this._channel, this._values);

  final MethodChannel _channel;
  Map<String, String> _values;
  Future<void> _pending = Future.value();

  static Future<SecurePushStore> load(
    SettingsStore legacy, {
    MethodChannel channel = const MethodChannel('kamubul/secure_push'),
  }) async {
    final source = await channel.invokeMethod<String>('read');
    if (source != null && utf8.encode(source).length > 131072) {
      throw const FormatException('push_state_oversize');
    }
    final values = <String, String>{};
    if (source != null) {
      final raw = jsonDecode(source);
      if (raw is! Map ||
          raw.keys.any((key) => !kPushStateKeys.contains(key)) ||
          raw.values.any((value) => value is! String)) {
        throw const FormatException('secure_push_state');
      }
      values.addAll(Map<String, String>.from(raw));
    } else {
      for (final key in kPushStateKeys) {
        final value = legacy.getString(key);
        if (value != null && value.isNotEmpty) values[key] = value;
      }
      // Write the complete legacy identity before removing any plaintext copy.
      if (values.isNotEmpty) {
        await channel.invokeMethod<void>('write', jsonEncode(values));
      }
    }
    for (final key in kPushStateKeys) {
      legacy.remove(key);
    }
    await legacy.flush();
    return SecurePushStore._(channel, values);
  }

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(Map<String, String?> values) {
    if (values.keys.any((key) => !kPushStateKeys.contains(key))) {
      throw ArgumentError('push_state_key');
    }
    final operation = _pending.then((_) async {
      final next = {..._values};
      for (final entry in values.entries) {
        if (entry.value == null) {
          next.remove(entry.key);
        } else {
          next[entry.key] = entry.value!;
        }
      }
      final encoded = jsonEncode(next);
      if (utf8.encode(encoded).length > 131072) {
        throw const FormatException('push_state_oversize');
      }
      await _channel.invokeMethod<void>('write', encoded);
      _values = next;
    });
    // A failed write reaches its caller; later writes may retry from the last durable state.
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
