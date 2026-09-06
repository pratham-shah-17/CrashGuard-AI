import 'dispatch_channel_status.dart';

/// Immutable snapshot of what RoadSOS attempted during one SOS dispatch (trust + claims evidence).
class SosActivityRecord {
  final String incidentId;
  final DateTime completedAtUtc;
  final double latitude;
  final double longitude;
  final double accuracyM;
  final String locationSource;
  final int triageSeverity;
  final String triageSourceName;
  final List<String> requiredServices;
  final List<DispatchChannelRow> channels;
  final String syncStatusLine;
  final bool isBystander;

  const SosActivityRecord({
    required this.incidentId,
    required this.completedAtUtc,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.locationSource,
    required this.triageSeverity,
    required this.triageSourceName,
    required this.requiredServices,
    required this.channels,
    required this.syncStatusLine,
    required this.isBystander,
  });

  factory SosActivityRecord.fromJson(Map<String, dynamic> json) {
    final ch = (json['channels'] as List<dynamic>? ?? [])
        .map((e) => DispatchChannelRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return SosActivityRecord(
      incidentId: json['incident_id'] as String,
      completedAtUtc: DateTime.parse(json['completed_at'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble() ?? 0,
      locationSource: json['location_source'] as String? ?? '',
      triageSeverity: json['triage_severity'] as int? ?? 0,
      triageSourceName: json['triage_source'] as String? ?? '',
      requiredServices:
          (json['required_services'] as List<dynamic>?)?.cast<String>() ?? [],
      channels: ch,
      syncStatusLine: json['sync_status'] as String? ?? '',
      isBystander: json['is_bystander'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'incident_id': incidentId,
    'completed_at': completedAtUtc.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracyM,
    'location_source': locationSource,
    'triage_severity': triageSeverity,
    'triage_source': triageSourceName,
    'required_services': requiredServices,
    'channels': channels.map((e) => e.toJson()).toList(),
    'sync_status': syncStatusLine,
    'is_bystander': isBystander,
  };

  String formattedGpsIndia() =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)} '
      '(±${accuracyM.round()} m • $locationSource)';
}
