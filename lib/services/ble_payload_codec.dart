import 'dart:typed_data';

/// Encodes and decodes the RoadSOS BLE mesh SOS beacon payload.
///
/// Android BLE advertising manufacturer data is capped at 26 bytes
/// (31-byte ADV packet minus 3 bytes for flags minus 2 bytes company ID).
/// The legacy UTF-8 string `LOC:12.97160,77.59461|SEV:4|SVC:AMB,POL`
/// is ~42 bytes — silently truncated by the BLE stack, losing location data.
///
/// This codec encodes the full payload in 12 bytes:
///   [0]      Magic byte 0xRS (0x72 'r' + 0x73 's' as single marker = 0x52)
///   [1]      Version = 0x01
///   [2]      Severity (1–5) packed with services bitmask in upper nibble
///   [3–6]    Latitude  as int32 (degrees × 100_000), big-endian
///   [7–10]   Longitude as int32 (degrees × 100_000), big-endian
///   [11]     Services bitmask (see [ServiceBit])
///
/// Total: 12 bytes — 14 bytes headroom for future extension.
class BlePayloadCodec {
  static const int _magic = 0x52; // 'R'
  static const int _version = 0x01;

  // Service bitmask definitions (matches AiTriageService._allowedServices)
  static const int bitAmbulance = 0x01;
  static const int bitPolice = 0x02;
  static const int bitFire = 0x04;
  static const int bitRescue = 0x08;
  static const int bitTowing = 0x10;
  static const int bitPunctureShop = 0x20;
  static const int bitShowroom = 0x40;

  /// Encode a SOS event to a compact 12-byte BLE payload.
  static Uint8List encode({
    required double latitude,
    required double longitude,
    required int severity,
    required List<String> services,
  }) {
    final buf = ByteData(12);
    buf.setUint8(0, _magic);
    buf.setUint8(1, _version);
    buf.setUint8(2, severity.clamp(1, 5));

    // Lat/lng encoded as fixed-point int32 (5 decimal places = ~1m precision).
    final latFixed = (latitude * 100000).round();
    final lngFixed = (longitude * 100000).round();
    buf.setInt32(3, latFixed, Endian.big);
    buf.setInt32(7, lngFixed, Endian.big);

    buf.setUint8(11, _servicesBitmask(services));
    return buf.buffer.asUint8List();
  }

  /// Decode a received BLE manufacturer data payload.
  /// Returns null if the magic byte or version do not match.
  static BleDecodedPayload? decode(List<int> data) {
    if (data.length < 12) return null;
    final buf = ByteData.sublistView(Uint8List.fromList(data));
    if (buf.getUint8(0) != _magic) return null;
    if (buf.getUint8(1) != _version) return null;

    final severity = buf.getUint8(2).clamp(1, 5);
    final lat = buf.getInt32(3, Endian.big) / 100000.0;
    final lng = buf.getInt32(7, Endian.big) / 100000.0;
    final svcBits = buf.getUint8(11);

    return BleDecodedPayload(
      latitude: lat,
      longitude: lng,
      severity: severity,
      services: _servicesFromBitmask(svcBits),
    );
  }

  static int _servicesBitmask(List<String> services) {
    var bits = 0;
    for (final s in services) {
      switch (s) {
        case 'ambulance':
          bits |= bitAmbulance;
        case 'police':
          bits |= bitPolice;
        case 'fire_department':
          bits |= bitFire;
        case 'rescue':
          bits |= bitRescue;
        case 'towing':
          bits |= bitTowing;
        case 'puncture_shop':
          bits |= bitPunctureShop;
        case 'showroom':
          bits |= bitShowroom;
      }
    }
    return bits == 0 ? bitAmbulance : bits; // Always at least ambulance
  }

  static List<String> _servicesFromBitmask(int bits) {
    final out = <String>[];
    if (bits & bitAmbulance != 0) out.add('ambulance');
    if (bits & bitPolice != 0) out.add('police');
    if (bits & bitFire != 0) out.add('fire_department');
    if (bits & bitRescue != 0) out.add('rescue');
    if (bits & bitTowing != 0) out.add('towing');
    if (bits & bitPunctureShop != 0) out.add('puncture_shop');
    if (bits & bitShowroom != 0) out.add('showroom');
    return out.isEmpty ? ['ambulance'] : out;
  }
}

class BleDecodedPayload {
  final double latitude;
  final double longitude;
  final int severity;
  final List<String> services;

  const BleDecodedPayload({
    required this.latitude,
    required this.longitude,
    required this.severity,
    required this.services,
  });

  /// Human-readable summary for the Mesh Radar / bystander UI.
  String toDisplayString() {
    final svc = services.join(', ');
    return 'SOS SEV:$severity LOC:(${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}) SVC:$svc';
  }
}
