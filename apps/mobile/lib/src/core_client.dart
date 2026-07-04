import 'dart:convert';

import 'package:http/http.dart' as http;

const defaultPaperAccountId = 'demo_account';

class DubheApiException implements Exception {
  DubheApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'DubheApiException($statusCode): $message';
}

class CoreClient {
  CoreClient({
    required this.baseUrl,
    http.Client? client,
    this.accessToken,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? accessToken;

  Future<DeviceSession> login({
    required String accountKey,
    required String password,
    required String mfaCode,
    required String deviceName,
    String platform = 'ios',
  }) async {
    final json = await _postJson('/v1/auth/login', {
      'account_key': accountKey,
      'password': password,
      'mfa_code': mfaCode,
      'device_name': deviceName,
      'platform': platform,
    }, includeAuth: false);
    final session = DeviceSession.fromJson(_map(json));
    accessToken = session.accessToken;
    return session;
  }

  Future<DeviceSession> registerAccount({
    required String accountKey,
    required String accountName,
    required String password,
    required String mfaCode,
    required String deviceName,
    String platform = 'ios',
  }) async {
    final json = await _postJson('/v1/auth/accounts/register', {
      'account_key': accountKey,
      'account_name': accountName,
      'password': password,
      'mfa_code': mfaCode,
      'device_name': deviceName,
      'platform': platform,
    }, includeAuth: false);
    final session = DeviceSession.fromJson(_map(json));
    accessToken = session.accessToken;
    return session;
  }

  Future<NewsFeed> fetchNewsFeed({
    String market = 'US',
    String symbol = 'NVDA',
    int limit = 8,
  }) async {
    final json = await _getJson('/v1/news/feed', queryParameters: {
      'market': market,
      'symbol': symbol,
      'limit': '$limit',
      'live': 'true',
    });
    return NewsFeed.fromJson(_map(json));
  }

  Future<NewsAnalysis> analyzeNews(NewsEvent event) async {
    final json = await _postJson('/v1/news/analyze', event.toJson());
    return NewsAnalysis.fromJson(_map(json));
  }

  Future<PaperPortfolio> fetchPaperPortfolio(String accountId) async {
    final json = await _getJson('/v1/simulation/paper-portfolio/$accountId');
    return PaperPortfolio.fromJson(_map(json));
  }

  Future<List<ApprovalRequest>> fetchApprovals() async {
    final json = await _getJson('/v1/approvals');
    return _mapList(json).map(ApprovalRequest.fromJson).toList();
  }

  Future<ApprovalRequest> decideApproval({
    required String approvalId,
    required bool approve,
    required String comment,
  }) async {
    final action = approve ? 'approve' : 'reject';
    final json = await _postJson('/v1/approvals/$approvalId/$action', {
      'decided_by': 'dubhe-mobile',
      'decision_comment_zh': comment,
    });
    return ApprovalRequest.fromJson(_map(json));
  }

  void close() => _client.close();

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$cleanBaseUrl$path').replace(
      queryParameters: queryParameters,
    );
  }

  Map<String, String> _headers({bool includeAuth = true}) {
    return {
      'content-type': 'application/json',
      if (includeAuth && accessToken != null)
        'authorization': 'Bearer $accessToken',
    };
  }

  Future<dynamic> _getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await _client.get(
      _uri(path, queryParameters: queryParameters),
      headers: _headers(),
    );
    return _decodeOrThrow(response);
  }

  Future<dynamic> _postJson(
    String path,
    Map<String, dynamic> body, {
    bool includeAuth = true,
  }) async {
    final response = await _client.post(
      _uri(path),
      headers: _headers(includeAuth: includeAuth),
      body: jsonEncode(body),
    );
    return _decodeOrThrow(response);
  }

  dynamic _decodeOrThrow(http.Response response) {
    final body = response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    var message = response.reasonPhrase ?? '请求失败';
    if (body is Map && body['detail'] != null) {
      message = '${body['detail']}';
    }
    throw DubheApiException(response.statusCode, message);
  }
}

class DeviceSession {
  DeviceSession({
    required this.userId,
    required this.deviceId,
    required this.workspaceId,
    required this.accessToken,
    required this.role,
    required this.deviceName,
  });

  final String userId;
  final String deviceId;
  final String workspaceId;
  final String accessToken;
  final String role;
  final String deviceName;

  bool get canReviewApprovals => role == 'admin' || role == 'risk_manager';

  String get roleZh {
    if (role == 'admin') return '管理员';
    if (role == 'risk_manager') return '风控管理员';
    return '普通用户';
  }

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      userId: _string(json['user_id']),
      deviceId: _string(json['device_id']),
      workspaceId: _string(json['workspace_id']),
      accessToken: _string(json['access_token']),
      role: _string(json['role'], fallback: 'user'),
      deviceName: _string(json['device_name']),
    );
  }
}

class NewsFeed {
  NewsFeed({
    required this.events,
    required this.providerStatus,
    required this.generatedAt,
  });

  final List<NewsEvent> events;
  final List<ProviderStatus> providerStatus;
  final String generatedAt;

  factory NewsFeed.fromJson(Map<String, dynamic> json) {
    return NewsFeed(
      events: _mapList(json['events']).map(NewsEvent.fromJson).toList(),
      providerStatus: _mapList(json['provider_status'])
          .map(ProviderStatus.fromJson)
          .toList(),
      generatedAt: _string(json['generated_at']),
    );
  }
}

class ProviderStatus {
  ProviderStatus({
    required this.provider,
    required this.status,
    required this.messageZh,
  });

  final String provider;
  final String status;
  final String messageZh;

  factory ProviderStatus.fromJson(Map<String, dynamic> json) {
    return ProviderStatus(
      provider: _string(json['provider']),
      status: _string(json['status']),
      messageZh: _string(json['message_zh']),
    );
  }
}

class NewsEvent {
  NewsEvent({
    required this.rawJson,
    required this.id,
    required this.sourceName,
    required this.titleOriginal,
    required this.titleZh,
    required this.publishedAt,
    required this.tickers,
    required this.eventType,
    required this.authorityScore,
  });

  final Map<String, dynamic> rawJson;
  final String id;
  final String sourceName;
  final String titleOriginal;
  final String titleZh;
  final String publishedAt;
  final List<String> tickers;
  final String eventType;
  final double authorityScore;

  String get title => titleZh.isNotEmpty ? titleZh : titleOriginal;

  Map<String, dynamic> toJson() => rawJson;

  factory NewsEvent.fromJson(Map<String, dynamic> json) {
    return NewsEvent(
      rawJson: json,
      id: _string(json['id']),
      sourceName: _string(json['source_name']),
      titleOriginal: _string(json['title_original']),
      titleZh: _string(json['title_zh']),
      publishedAt: _string(json['published_at']),
      tickers: _stringList(json['tickers']),
      eventType: _string(json['event_type']),
      authorityScore: _double(json['authority_score']),
    );
  }
}

class NewsAnalysis {
  NewsAnalysis({
    required this.summaryZh,
    required this.sentiment,
    required this.impactScore,
    required this.affectedTickers,
    required this.confidence,
  });

  final String summaryZh;
  final String sentiment;
  final double impactScore;
  final List<String> affectedTickers;
  final double confidence;

  factory NewsAnalysis.fromJson(Map<String, dynamic> json) {
    return NewsAnalysis(
      summaryZh: _string(json['summary_zh']),
      sentiment: _string(json['sentiment']),
      impactScore: _double(json['impact_score']),
      affectedTickers: _stringList(json['affected_tickers']),
      confidence: _double(json['confidence']),
    );
  }
}

class PaperPortfolio {
  PaperPortfolio({
    required this.accountId,
    required this.cashByCurrency,
    required this.equityByCurrency,
    required this.positions,
  });

  final String accountId;
  final Map<String, double> cashByCurrency;
  final Map<String, double> equityByCurrency;
  final List<PaperPosition> positions;

  factory PaperPortfolio.fromJson(Map<String, dynamic> json) {
    return PaperPortfolio(
      accountId: _string(json['account_id']),
      cashByCurrency: _doubleMap(json['cash_by_currency']),
      equityByCurrency: _doubleMap(json['equity_by_currency']),
      positions: _mapList(json['positions']).map(PaperPosition.fromJson).toList(),
    );
  }
}

class PaperPosition {
  PaperPosition({
    required this.market,
    required this.symbol,
    required this.currency,
    required this.quantity,
    required this.avgCost,
    required this.marketValue,
    required this.unrealizedPnl,
  });

  final String market;
  final String symbol;
  final String currency;
  final double quantity;
  final double avgCost;
  final double marketValue;
  final double unrealizedPnl;

  factory PaperPosition.fromJson(Map<String, dynamic> json) {
    return PaperPosition(
      market: _string(json['market']),
      symbol: _string(json['symbol']),
      currency: _string(json['currency']),
      quantity: _double(json['quantity']),
      avgCost: _double(json['avg_cost']),
      marketValue: _double(json['market_value']),
      unrealizedPnl: _double(json['unrealized_pnl']),
    );
  }
}

class ApprovalRequest {
  ApprovalRequest({
    required this.id,
    required this.status,
    required this.messageZh,
    required this.notional,
    required this.reasonsZh,
  });

  final String id;
  final String status;
  final String messageZh;
  final double notional;
  final List<String> reasonsZh;

  bool get isPending => status == 'pending';

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) {
    final riskDecision = _map(json['risk_decision']);
    return ApprovalRequest(
      id: _string(json['id']),
      status: _string(json['status']),
      messageZh: _string(json['message_zh']),
      notional: _double(riskDecision['notional']),
      reasonsZh: _stringList(riskDecision['reasons_zh']),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => '$item').toList();
}

Map<String, double> _doubleMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry('$key', _double(item)));
}

String _string(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return '$value';
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
