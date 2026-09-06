/// Lifecycle of one emergency dispatch channel shown in honest status UI.
enum DispatchChannelLifecycle { pending, inProgress, success, failed, skipped }

/// One row in the dispatch confirmation list (SMS, mesh, cloud, etc.).
class DispatchChannelRow {
  final String id;
  final String title;
  final DispatchChannelLifecycle lifecycle;

  /// Short line for accessibility and panic readability (WCAG-minded contrast in UI).
  final String detail;

  const DispatchChannelRow({
    required this.id,
    required this.title,
    required this.lifecycle,
    required this.detail,
  });

  factory DispatchChannelRow.fromJson(Map<String, dynamic> json) {
    return DispatchChannelRow(
      id: json['id'] as String,
      title: json['title'] as String,
      lifecycle: DispatchChannelLifecycle.values.firstWhere(
        (e) => e.name == json['lifecycle'],
        orElse: () => DispatchChannelLifecycle.pending,
      ),
      detail: json['detail'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'lifecycle': lifecycle.name,
    'detail': detail,
  };

  DispatchChannelRow copyWith({
    DispatchChannelLifecycle? lifecycle,
    String? detail,
  }) {
    return DispatchChannelRow(
      id: id,
      title: title,
      lifecycle: lifecycle ?? this.lifecycle,
      detail: detail ?? this.detail,
    );
  }
}
