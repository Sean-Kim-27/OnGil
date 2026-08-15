import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 저장된 프로필 사진 값(구글/카카오가 준 http(s) URL이거나, 기기에 저장된 로컬 파일 경로)을 보고
/// 알맞은 ImageProvider를 돌려줌. 값이 없으면 null.
ImageProvider? resolveProfileImage(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  final isNetworkUrl = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  if (isNetworkUrl) {
    return NetworkImage(value);
  }
  return FileImage(File(value));
}

/// 카메라/갤러리에서 사진을 선택해 앱 문서 폴더에 저장하는 서비스.
/// TODO: 백엔드 이미지 업로드 API가 생기면, 로컬 저장 후 서버로 업로드하고 반환된 URL을 photoUrl로 저장하는 방식으로 확장하면 됨.
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
}
