import '../prefs_source_repository.dart';
import 'cloud_drive_types.dart';

class CloudDriveSource {
  final String id;
  final String name;
  final CloudDriveProvider provider;
  final String root;
  final String appKey;

  const CloudDriveSource({
    required this.id,
    required this.name,
    required this.provider,
    required this.root,
    this.appKey = '',
  });

  CloudDriveSource copyWith({
    String? id,
    String? name,
    CloudDriveProvider? provider,
    String? root,
    String? appKey,
  }) {
    return CloudDriveSource(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      root: root ?? this.root,
      appKey: appKey ?? this.appKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'provider': provider.name,
    'root': root,
    'appKey': appKey,
  };

  factory CloudDriveSource.fromJson(Map<String, dynamic> json) {
    final providerName = (json['provider'] ?? '').toString();
    final provider = CloudDriveProvider.values.firstWhere(
      (value) => value.name == providerName,
      orElse: () => CloudDriveProvider.baidu,
    );
    return CloudDriveSource(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? provider.displayName).toString(),
      provider: provider,
      root: (json['root'] ?? provider.defaultRoot).toString(),
      appKey: (json['appKey'] ?? '').toString(),
    );
  }
}

extension CloudDriveProviderDisplay on CloudDriveProvider {
  String get displayName => switch (this) {
    CloudDriveProvider.baidu => '百度网盘',
    CloudDriveProvider.quark => '夸克网盘',
  };

  String get sourceIdPrefix => switch (this) {
    CloudDriveProvider.baidu => 'baidu',
    CloudDriveProvider.quark => 'quark',
  };

  String get defaultRoot => switch (this) {
    CloudDriveProvider.baidu => '/',
    CloudDriveProvider.quark => '0',
  };
}

class CloudDriveSourceRepository
    extends PrefsSourceRepository<CloudDriveSource> {
  static final CloudDriveSourceRepository instance =
      CloudDriveSourceRepository._internal();

  CloudDriveSourceRepository._internal();

  @override
  String get prefsKey => 'cloud_drive_sources_v1';

  @override
  String get idPrefix => 'cloud';

  @override
  CloudDriveSource fromJson(Map<String, dynamic> json) =>
      CloudDriveSource.fromJson(json);

  @override
  Map<String, dynamic> toJson(CloudDriveSource source) => source.toJson();

  @override
  String idOf(CloudDriveSource source) => source.id;

  String newIdFor(CloudDriveProvider provider) =>
      '${provider.sourceIdPrefix}-${DateTime.now().millisecondsSinceEpoch}';

  Future<CloudDriveSource?> findById(String id) async {
    final sources = await loadSources();
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }
}
