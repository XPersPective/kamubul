/// Dosya tabanlı depolama: hesap ya da bulut gerektirmez; tek konteyner/VPS
/// için taşınabilir yol. Yazımlar geçici dosya + yeniden adlandırma ile
/// atomiktir. Tek sürecin (iş + API aynı birimi paylaşır) kullanımı içindir.
library;

import 'dart:convert';
import 'dart:io';

import 'package:kamubul_core/kamubul_core.dart';

import 'storage.dart';

class FileStorage implements Storage {
  FileStorage(String dir) : _root = Directory(dir) {
    _devices.createSync(recursive: true);
  }

  final Directory _root;

  Directory get _devices => Directory('${_root.path}/devices');
  File get _snapshot => File('${_root.path}/snapshot.json');
  File get _state => File('${_root.path}/state.json');

  Future<void> _atomicWrite(File file, String body) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(file.path);
  }

  File _device(String id) {
    if (!isValidDeviceId(id)) throw ArgumentError.value(id, 'id');
    return File('${_devices.path}/$id.json');
  }

  @override
  Future<String?> readSnapshot() async =>
      await _snapshot.exists() ? _snapshot.readAsString() : null;

  @override
  Future<void> writeSnapshot(String body) => _atomicWrite(_snapshot, body);

  @override
  Future<Map<String, Object?>?> readState() async {
    if (!await _state.exists()) return null;
    try {
      final decoded = jsonDecode(await _state.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeState(Map<String, Object?> state) =>
      _atomicWrite(_state, jsonEncode(state));

  @override
  Future<DeviceRecord?> getDevice(String id) async {
    final file = _device(id);
    if (!await file.exists()) return null;
    try {
      return DeviceRecord.decode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> putDevice(DeviceRecord device) =>
      _atomicWrite(_device(device.id), device.encode());

  @override
  Future<void> deleteDevice(String id) async {
    final file = _device(id);
    if (await file.exists()) await file.delete();
  }

  @override
  Stream<DeviceRecord> devices() async* {
    await for (final entity in _devices.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        yield DeviceRecord.decode(await entity.readAsString());
      } on FormatException {
        continue;
      }
    }
  }

  @override
  Future<void> close() async {}
}
