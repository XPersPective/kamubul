/// Depolama arayüzü: arka ucun tek durum kaynağı. Firestore (Google öncelikli)
/// ve dosya (taşınabilir, TR VPS/tek konteyner) uygulamaları aynı sözleşmeyi
/// sağlar; iş ve API yalnızca bu arayüzü bilir.
library;

import 'dart:convert';

import 'package:kamubul_core/kamubul_core.dart';

/// Bir cihazın sunucudaki kaydı. Kişisel kimlik içermez: anonim kimlik,
/// gizli anahtar özeti, FCM jetonu, tercihler ve etiket süzgeçleri.
class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.secretHash,
    required this.registration,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Gizli anahtarın SHA-256 özeti (hex); anahtarın kendisi saklanmaz.
  final String secretHash;
  final DeviceRegistration registration;
  final DevicePushState state;
  final DateTime createdAt;
  final DateTime updatedAt;

  DeviceRecord copyWith({
    DeviceRegistration? registration,
    DevicePushState? state,
    DateTime? updatedAt,
  }) => DeviceRecord(
    id: id,
    secretHash: secretHash,
    registration: registration ?? this.registration,
    state: state ?? this.state,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  String encode() => jsonEncode({
    'id': id,
    'secretHash': secretHash,
    'registration': registration.toJson(),
    'state': state.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  });

  /// Bozuk kayıt [FormatException] fırlatır; çağıran atlar.
  static DeviceRecord decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map) throw const FormatException('cihaz kaydı nesne değil');
    final id = json['id'];
    final hash = json['secretHash'];
    final created = DateTime.tryParse('${json['createdAt']}');
    final updated = DateTime.tryParse('${json['updatedAt']}');
    if (id is! String ||
        hash is! String ||
        created == null ||
        updated == null) {
      throw const FormatException('cihaz kaydı eksik');
    }
    try {
      return DeviceRecord(
        id: id,
        secretHash: hash,
        registration: DeviceRegistration.parse(json['registration']),
        state: DevicePushState.fromJson(json['state']),
        createdAt: created,
        updatedAt: updated,
      );
    } on RegistrationFormatException catch (error) {
      throw FormatException(error.message);
    }
  }
}

abstract class Storage {
  /// Yayınlanmış katalog anlık görüntüsü (JSON gövdesi); yoksa `null`.
  Future<String?> readSnapshot();
  Future<void> writeSnapshot(String body);

  /// İş durumu (ayrıntısı alınmış ilanlar, AI yeniden deneme, bekleyen push).
  Future<Map<String, Object?>?> readState();
  Future<void> writeState(Map<String, Object?> state);

  Future<DeviceRecord?> getDevice(String id);
  Future<void> putDevice(DeviceRecord device);
  Future<void> deleteDevice(String id);

  /// Bozuk kayıtlar sessizce atlanır.
  Stream<DeviceRecord> devices();

  Future<void> close();
}
