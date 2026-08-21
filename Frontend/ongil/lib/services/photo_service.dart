import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 저장된 프로필 사진 값(URL 또는 로컬 경로)에 맞는 ImageProvider를 돌려줌.
ImageProvider? resolveProfileImage(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  final isNetworkUrl = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  if (isNetworkUrl) {
    return NetworkImage(value);
  }
  return FileImage(File(value));
}

/// 카메라/갤러리에서 고른 사진을 앱 문서 폴더에 저장하는 서비스.
/// TODO: 이미지 업로드 API가 생기면 서버 URL 저장 방식으로 확장.
class PhotoService {
  PhotoService._();
  static final PhotoService instance = PhotoService._();

  final ImagePicker _picker = ImagePicker();

  /// 선택 취소/실패 시 null, 성공하면 저장된 로컬 파일 경로를 돌려줌.
  Future<String?> pickAndSaveProfilePhoto({required ImageSource source}) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final savedPath = '${dir.path}/profile_photo.jpg';

    final savedFile = File(savedPath);
    if (await savedFile.exists()) {
      await savedFile.delete();
    }
    await File(picked.path).copy(savedPath);

    return savedPath;
  }

  /// 방명록/아카이브용 사진 저장. 여러 장이 남아야 해서 매번 새 파일명을 씀.
  Future<String?> pickAndSaveMemoryPhoto({required ImageSource source}) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1440,
    );
    if (picked == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/memory_photos');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final savedPath =
        '${folder.path}/memory_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(picked.path).copy(savedPath);

    return savedPath;
  }

  /// 즉석 촬영만 허용해야 하는 곳('지금 모습' 사진)에서 씀.
  Future<String?> captureMemoryPhoto() {
    return pickAndSaveMemoryPhoto(source: ImageSource.camera);
  }

  /// 저장해둔 사진 파일을 지움.
  Future<void> deleteSavedPhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('⚠️ 사진 삭제 실패: $e');
    }
  }
}
