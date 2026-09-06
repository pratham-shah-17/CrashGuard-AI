import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class SceneSecurityService {
  /// Generates a 128-bit key based on rounded coordinates and hourly timestamp.
  /// This ensures 'Spatial Privacy' - only people in the same region at the same time can decrypt.
  static String generateSceneKey(double lat, double lng) {
    // Round to ~1.1km precision (2 decimal places)
    final String spatialHash =
        "${lat.toStringAsFixed(2)}:${lng.toStringAsFixed(2)}";
    final int hourStamp =
        DateTime.now().millisecondsSinceEpoch ~/ (1000 * 60 * 60);

    final bytes = utf8.encode("$spatialHash:$hourStamp");
    final digest = sha256.convert(bytes);

    return digest.toString().substring(0, 32); // Use first 32 chars for AES-256
  }

  static final _aead = AesGcm.with256bits();

  /// Encrypts [data] with AES-GCM using a random nonce.
  ///
  /// Output format (base64, URL-safe):
  /// `v1.<nonce_b64>.<cipher_b64>`
  static Future<String> encryptPayload(String data, String keyString) async {
    final keyBytes = utf8.encode(keyString.substring(0, 32));
    final secretKey = SecretKey(keyBytes);
    final nonce = _aead.newNonce();
    final secretBox = await _aead.encrypt(
      utf8.encode(data),
      secretKey: secretKey,
      nonce: nonce,
    );
    final nonceB64 = base64UrlEncode(secretBox.nonce);
    final cipherB64 = base64UrlEncode(<int>[
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return 'v1.$nonceB64.$cipherB64';
  }

  /// Attempts to decrypt an AES-GCM payload created by [encryptPayload].
  ///
  /// Returns `null` if decryption fails (wrong key / corrupted / wrong format).
  static Future<String?> decryptPayload(
    String encoded,
    String keyString,
  ) async {
    try {
      final parts = encoded.split('.');
      if (parts.length != 3 || parts[0] != 'v1') return null;
      final nonce = base64Url.decode(parts[1]);
      final combined = base64Url.decode(parts[2]);
      if (combined.length < 16) return null;
      final cipherText = combined.sublist(0, combined.length - 16);
      final macBytes = combined.sublist(combined.length - 16);

      final keyBytes = utf8.encode(keyString.substring(0, 32));
      final secretKey = SecretKey(keyBytes);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

      final clear = await _aead.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clear);
    } on Object catch (_) {
      return null;
    }
  }
}
