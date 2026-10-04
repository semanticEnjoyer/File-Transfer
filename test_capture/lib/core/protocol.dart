/// Network constants shared by the phone and the PC.
class Protocol {
  /// HTTP port the PC hub listens on.
  static const int httpPort = 47800;

  /// UDP port used to discover the PC hub on the local network.
  static const int discoveryPort = 47801;

  static const String discoverMessage = 'TESTCAPTURE_DISCOVER_V1';
  static const String discoverReplyPrefix = 'TESTCAPTURE_HUB_V1';

  static const String tokenHeader = 'x-tc-token';
}

class HubInfo {
  HubInfo({required this.name, required this.host, required this.port});
  final String name;
  final String host;
  final int port;

  String get baseUrl => 'http://$host:$port';

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'port': port};
  factory HubInfo.fromJson(Map<String, dynamic> j) => HubInfo(
        name: j['name'] as String? ?? 'PC',
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? Protocol.httpPort,
      );
}
