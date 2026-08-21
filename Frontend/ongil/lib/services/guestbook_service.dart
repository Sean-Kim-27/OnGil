import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/guestbook_entry.dart';
import '../models/memory_archive_entry.dart';

/// 방명록 / 아카이브 로컬 저장소.
///
/// 백엔드 guestbook API가 아직 없어서 기기에 JSON으로 저장함.
/// TODO: 서버 API가 생기면 메서드 본문만 http 호출로 교체.
class GuestbookService {
  GuestbookService._();
  static final GuestbookService instance = GuestbookService._();

  static const _storage = FlutterSecureStorage();
  static const _entriesKey = 'guestbook_entries_v1';
  static const _archiveKey = 'guestbook_archive_v1';

  // ---------------------------------------------------------------------------
  // 공용 헬퍼
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _readRaw(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      // 저장 형식이 깨졌으면 빈 목록으로 시작.
      debugPrint('⚠️ [GuestbookService] 저장된 데이터를 읽지 못했습니다($key): $e');
      return [];
    }
  }

  Future<void> _writeRaw(String key, List<Map<String, dynamic>> list) async {
    await _storage.write(key: key, value: jsonEncode(list));
  }

  // ---------------------------------------------------------------------------
  // 방명록
  // ---------------------------------------------------------------------------

  /// 해당 여정에 남긴 글만 최신순으로.
  Future<List<GuestbookEntry>> loadEntries(int scheduleId) async {
    final raw = await _readRaw(_entriesKey);
    final entries = raw
        .map(GuestbookEntry.fromJson)
        .where((e) => e.scheduleId == scheduleId)
        .toList();
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<void> addEntry(GuestbookEntry entry) async {
    final raw = await _readRaw(_entriesKey);
    raw.insert(0, entry.toJson());
    await _writeRaw(_entriesKey, raw);
  }

  /// 같은 id의 글을 새 내용으로 교체(수정). 없으면 새로 추가함.
  Future<void> updateEntry(GuestbookEntry entry) async {
    final raw = await _readRaw(_entriesKey);
    final index = raw.indexWhere((m) => '${m['id']}' == entry.id);
    if (index >= 0) {
      raw[index] = entry.toJson();
    } else {
      raw.insert(0, entry.toJson());
    }
    await _writeRaw(_entriesKey, raw);
  }

  Future<void> removeEntry(String id) async {
    final raw = await _readRaw(_entriesKey);
    raw.removeWhere((m) => '${m['id']}' == id);
    await _writeRaw(_entriesKey, raw);
  }

  // ---------------------------------------------------------------------------
  // 아카이브 (그때-지금 사진)
  // ---------------------------------------------------------------------------

  Future<List<MemoryArchiveEntry>> loadArchive(int scheduleId) async {
    final raw = await _readRaw(_archiveKey);
    final items = raw
        .map(MemoryArchiveEntry.fromJson)
        .where((e) => e.scheduleId == scheduleId)
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> addArchive(MemoryArchiveEntry entry) async {
    final raw = await _readRaw(_archiveKey);
    // 장소마다 한 건만 두고, 같은 장소면 새 것으로 교체.
    raw.removeWhere((m) =>
        '${m['schedule_id']}' == '${entry.scheduleId}' &&
        '${m['place_name']}' == entry.placeName);
    raw.insert(0, entry.toJson());
    await _writeRaw(_archiveKey, raw);
  }

  /// 같은 id의 아카이브를 새 내용으로 교체(수정).
  Future<void> updateArchive(MemoryArchiveEntry entry) async {
    final raw = await _readRaw(_archiveKey);
    final index = raw.indexWhere((m) => '${m['id']}' == entry.id);
    if (index >= 0) {
      raw[index] = entry.toJson();
    } else {
      raw.insert(0, entry.toJson());
    }
    await _writeRaw(_archiveKey, raw);
  }

  Future<void> removeArchive(String id) async {
    final raw = await _readRaw(_archiveKey);
    raw.removeWhere((m) => '${m['id']}' == id);
    await _writeRaw(_archiveKey, raw);
  }
}
