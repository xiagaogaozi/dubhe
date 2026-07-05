import 'dart:convert';
import 'dart:io';

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
  CoreClient({required this.baseUrl, http.Client? client, this.accessToken})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? accessToken;

  Future<bool> checkHealth() async {
    final json = await _getJson('/health', includeAuth: false);
    final body = _map(json);
    return _string(body['status']) == 'ok' &&
        _string(body['service']) == 'dubhe-core';
  }

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
    String? symbol = 'NVDA',
    int limit = 8,
    bool live = false,
  }) async {
    final normalizedSymbol = symbol?.trim().toUpperCase();
    final queryParameters = {
      'market': market,
      'limit': '$limit',
      'live': '$live',
    };
    if (normalizedSymbol != null && normalizedSymbol.isNotEmpty) {
      queryParameters['symbol'] = normalizedSymbol;
    }
    final json = await _getJson(
      '/v1/news/feed',
      queryParameters: queryParameters,
    );
    return NewsFeed.fromJson(_map(json));
  }

  Future<SystemStatus> fetchSystemStatus() async {
    final json = await _getJson('/v1/system/status');
    return SystemStatus.fromJson(_map(json));
  }

  Future<ExternalServiceChecks> fetchExternalServiceChecks({
    bool live = false,
  }) async {
    final json = await _getJson(
      '/v1/system/external-checks',
      queryParameters: {'live': '$live'},
    );
    return ExternalServiceChecks.fromJson(_map(json));
  }

  Future<ProductionReadiness> fetchProductionReadiness() async {
    final json = await _getJson('/v1/system/production-readiness');
    return ProductionReadiness.fromJson(_map(json));
  }

  Future<SmokeWorkflowReport> fetchSmokeWorkflowReport() async {
    final json = await _getJson('/v1/system/smoke-report');
    return SmokeWorkflowReport.fromJson(_map(json));
  }

  Future<LocalRuntimeConfig> fetchLocalRuntimeConfig() async {
    final json = await _getJson('/v1/runtime/local-config');
    return LocalRuntimeConfig.fromJson(_map(json));
  }

  Future<OnboardingChecklist> fetchOnboardingChecklist() async {
    final json = await _getJson('/v1/onboarding/checklist');
    return OnboardingChecklist.fromJson(_map(json));
  }

  Future<LocalRuntimeConfig> updateLocalRuntimeConfig({
    required Map<String, String> values,
  }) async {
    final json = await _putJson('/v1/runtime/local-config', {'values': values});
    return LocalRuntimeConfig.fromJson(_map(json));
  }

  Future<WorkspaceSnapshot> fetchWorkspaceSnapshot({
    required String workspaceId,
    int sinceSequence = 0,
  }) async {
    final json = await _getJson(
      '/v1/workspaces/$workspaceId/snapshot',
      queryParameters: {'since_sequence': '$sinceSequence'},
    );
    return WorkspaceSnapshot.fromJson(_map(json));
  }

  Future<List<SyncEvent>> fetchWorkspaceSyncEvents({
    required String workspaceId,
    int sinceSequence = 0,
  }) async {
    final json = await _getJson(
      '/v1/workspaces/$workspaceId/sync-events',
      queryParameters: {'since_sequence': '$sinceSequence'},
    );
    return _mapList(json).map(SyncEvent.fromJson).toList();
  }

  Future<WorkspaceSyncConnection> connectWorkspaceSyncEvents({
    required String workspaceId,
    int sinceSequence = 0,
  }) async {
    final socket = await WebSocket.connect(
      workspaceSyncEventsUri(
        workspaceId: workspaceId,
        sinceSequence: sinceSequence,
      ).toString(),
    );
    return WorkspaceSyncConnection(socket);
  }

  Uri workspaceSyncEventsUri({
    required String workspaceId,
    int sinceSequence = 0,
  }) {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw DubheApiException(401, '请先登录 Dubhe Core。');
    }
    final uri = _uri(
      '/v1/workspaces/$workspaceId/sync-events/ws',
      queryParameters: {
        'access_token': token,
        'since_sequence': '$sinceSequence',
      },
    );
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
  }

  Future<NewsAnalysis> analyzeNews(NewsEvent event) async {
    final json = await _postJson('/v1/news/analyze', event.toJson());
    return NewsAnalysis.fromJson(_map(json));
  }

  Future<StrategyDraft> draftStrategyFromAnalysis({
    required NewsAnalysis analysis,
    required String symbol,
    required String market,
    double maxOrderNotional = 10000,
  }) async {
    final json = await _postJson('/v1/strategy/drafts/from-analysis', {
      'analysis': analysis.toJson(),
      'symbol': symbol,
      'market': market,
      'max_order_notional': maxOrderNotional,
    });
    return StrategyDraft.fromJson(_map(json));
  }

  Future<BacktestResult> runReplayBacktest({
    required StrategyDraft strategy,
    double initialCash = 100000,
  }) async {
    final json = await _postJson('/v1/backtests/replay', {
      'strategy': strategy.toJson(),
      'initial_cash': initialCash,
      'replay_scenario': 'golden_news_sentiment_v1',
    });
    return BacktestResult.fromJson(_map(json));
  }

  Future<AssistantChatResponse> askAssistant({
    required String questionZh,
    NewsEvent? newsEvent,
    NewsAnalysis? analysis,
    StrategyDraft? strategyDraft,
    BacktestResult? backtestResult,
  }) async {
    final json = await _postJson('/v1/assistant/chat', {
      'question_zh': questionZh,
      'context': {
        'news_event': newsEvent?.toJson(),
        'analysis': analysis?.toJson(),
        'strategy': strategyDraft?.toJson(),
        'backtest': backtestResult?.toJson(),
      },
    });
    return AssistantChatResponse.fromJson(_map(json));
  }

  Future<PaperOrder> submitPaperBuy({
    required String accountId,
    required String strategyVersionId,
    required String market,
    required String symbol,
    required double quantity,
    required double estimatedPrice,
    required String currency,
    required List<String> sourceRefs,
  }) async {
    final json = await _postJson('/v1/simulation/paper-orders', {
      'account_id': accountId,
      'strategy_version_id': strategyVersionId,
      'market': market,
      'symbol': symbol,
      'side': 'buy',
      'order_type': 'market',
      'quantity': quantity,
      'estimated_price': estimatedPrice,
      'currency': currency,
      'created_by': 'user',
      'destination': 'paper',
      'rationale_zh': '移动端根据新闻分析提交纸面交易验证。',
      'source_refs': sourceRefs,
    });
    return PaperOrder.fromJson(_map(json));
  }

  Future<PaperPortfolio> fetchPaperPortfolio(String accountId) async {
    final json = await _getJson('/v1/simulation/paper-portfolio/$accountId');
    return PaperPortfolio.fromJson(_map(json));
  }

  Future<RiskDecision> createLiveApprovalDemo({
    required String accountId,
    required String strategyVersionId,
    required String market,
    required String symbol,
    required double quantity,
    required double estimatedPrice,
    required String currency,
    required List<String> sourceRefs,
  }) async {
    final json = await _postJson('/v1/risk/evaluate', {
      'account_id': accountId,
      'strategy_version_id': strategyVersionId,
      'market': market,
      'symbol': symbol,
      'side': 'buy',
      'order_type': 'market',
      'quantity': quantity,
      'estimated_price': estimatedPrice,
      'currency': currency,
      'created_by': 'ai',
      'destination': 'live',
      'rationale_zh': '移动端风控中心生成的实盘审批演示；仅创建审批请求，不会连接真实券商。',
      'source_refs': sourceRefs,
    });
    return RiskDecision.fromJson(_map(json));
  }

  Future<List<ApprovalRequest>> fetchApprovals({
    String status = 'pending',
  }) async {
    final json = await _getJson(
      '/v1/approvals',
      queryParameters: {'status': status},
    );
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

  Future<KillSwitchState> fetchKillSwitch() async {
    final json = await _getJson('/v1/risk/kill-switch');
    return KillSwitchState.fromJson(_map(json));
  }

  Future<KillSwitchState> setKillSwitch({
    required bool enabled,
    required String reason,
    String updatedBy = 'dubhe-mobile',
  }) async {
    final json = await _postJson('/v1/risk/kill-switch', {
      'enabled': enabled,
      'reason_zh': reason,
      'updated_by': updatedBy,
    });
    return KillSwitchState.fromJson(_map(json));
  }

  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 8}) async {
    final json = await _getJson(
      '/v1/audit/logs',
      queryParameters: {'limit': '$limit'},
    );
    return _mapList(json).map(AuditLogEntry.fromJson).toList();
  }

  void close() => _client.close();

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse(
      '$cleanBaseUrl$path',
    ).replace(queryParameters: queryParameters);
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
    bool includeAuth = true,
  }) async {
    final response = await _client.get(
      _uri(path, queryParameters: queryParameters),
      headers: _headers(includeAuth: includeAuth),
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

  Future<dynamic> _putJson(String path, Map<String, dynamic> body) async {
    final response = await _client.put(
      _uri(path),
      headers: _headers(),
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

class WorkspaceSyncConnection {
  WorkspaceSyncConnection(this._socket);

  final WebSocket _socket;

  Stream<SyncEvent> get events => _socket.expand((message) {
    final event = SyncEvent.tryParseMessage(message);
    return event == null ? const <SyncEvent>[] : [event];
  });

  Future<void> close() => _socket.close();
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

  bool get canEditRuntimeConfig => role == 'admin';

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
      providerStatus: _mapList(
        json['provider_status'],
      ).map(ProviderStatus.fromJson).toList(),
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

class SystemStatus {
  SystemStatus({
    required this.service,
    required this.version,
    required this.storagePath,
    required this.storageMessageZh,
    required this.authMessageZh,
    required this.paperBrokerEnabled,
    required this.liveTradingEnabled,
    required this.tradingMessageZh,
    required this.llm,
    required this.configItems,
    required this.newsAdapters,
    required this.newsCoverage,
    required this.installPackages,
    required this.localLaunchers,
  });

  final String service;
  final String version;
  final String storagePath;
  final String storageMessageZh;
  final String authMessageZh;
  final bool paperBrokerEnabled;
  final bool liveTradingEnabled;
  final String tradingMessageZh;
  final LlmReadiness llm;
  final List<RuntimeConfigItem> configItems;
  final List<NewsAdapterReadiness> newsAdapters;
  final List<NewsMarketCoverage> newsCoverage;
  final List<InstallPackageReadiness> installPackages;
  final List<LocalLauncherReadiness> localLaunchers;

  int get missingConfigCount =>
      configItems.where((item) => !item.configured).length;

  int get enabledAdapterCount =>
      newsAdapters.where((adapter) => adapter.enabled).length;

  int get enabledLicensedAdapterCount => newsAdapters
      .where((adapter) => adapter.requiresLicense && adapter.enabled)
      .length;

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    final storage = _map(json['storage']);
    final auth = _map(json['auth']);
    final trading = _map(json['trading']);
    return SystemStatus(
      service: _string(json['service']),
      version: _string(json['version']),
      storagePath: _string(storage['path']),
      storageMessageZh: _string(storage['message_zh']),
      authMessageZh: _string(auth['message_zh']),
      paperBrokerEnabled: _bool(trading['paper_broker_enabled']),
      liveTradingEnabled: _bool(trading['live_trading_enabled']),
      tradingMessageZh: _string(trading['message_zh']),
      llm: LlmReadiness.fromJson(_map(json['llm'])),
      configItems: _mapList(
        json['config_items'],
      ).map(RuntimeConfigItem.fromJson).toList(),
      newsAdapters: _mapList(
        json['news_adapters'],
      ).map(NewsAdapterReadiness.fromJson).toList(),
      newsCoverage: _mapList(
        json['news_coverage'],
      ).map(NewsMarketCoverage.fromJson).toList(),
      installPackages: _mapList(
        json['install_packages'],
      ).map(InstallPackageReadiness.fromJson).toList(),
      localLaunchers: _mapList(
        json['local_launchers'],
      ).map(LocalLauncherReadiness.fromJson).toList(),
    );
  }
}

class ExternalServiceChecks {
  ExternalServiceChecks({
    required this.live,
    required this.overallStatus,
    required this.readyCount,
    required this.totalCount,
    required this.checks,
    required this.messageZh,
    required this.generatedAt,
  });

  final bool live;
  final String overallStatus;
  final int readyCount;
  final int totalCount;
  final List<ExternalServiceCheck> checks;
  final String messageZh;
  final String generatedAt;

  bool get ready => overallStatus == 'ready';
  bool get actionRequired => overallStatus == 'action_required';

  String get statusZh {
    if (ready) return '全部通过';
    if (actionRequired) return '待配置';
    return '部分可用';
  }

  factory ExternalServiceChecks.fromJson(Map<String, dynamic> json) {
    return ExternalServiceChecks(
      live: _bool(json['live']),
      overallStatus: _string(json['overall_status']),
      readyCount: _int(json['ready_count']),
      totalCount: _int(json['total_count']),
      checks: _mapList(
        json['checks'],
      ).map(ExternalServiceCheck.fromJson).toList(),
      messageZh: _string(json['message_zh']),
      generatedAt: _string(json['generated_at']),
    );
  }
}

class ExternalServiceCheck {
  ExternalServiceCheck({
    required this.service,
    required this.labelZh,
    required this.configured,
    required this.liveChecked,
    required this.status,
    required this.durationMs,
    required this.messageZh,
    required this.nextStepZh,
  });

  final String service;
  final String labelZh;
  final bool configured;
  final bool liveChecked;
  final String status;
  final int durationMs;
  final String messageZh;
  final String nextStepZh;

  bool get ok => status == 'ok';
  bool get skipped => status == 'skipped';

  String get statusZh {
    if (ok) return liveChecked ? '${durationMs}ms' : '可用';
    if (skipped) return configured ? '待 live' : '未配置';
    return '不可用';
  }

  factory ExternalServiceCheck.fromJson(Map<String, dynamic> json) {
    return ExternalServiceCheck(
      service: _string(json['service']),
      labelZh: _string(json['label_zh']),
      configured: _bool(json['configured']),
      liveChecked: _bool(json['live_checked']),
      status: _string(json['status']),
      durationMs: _int(json['duration_ms']),
      messageZh: _string(json['message_zh']),
      nextStepZh: _string(json['next_step_zh']),
    );
  }
}

class ProductionReadiness {
  ProductionReadiness({
    required this.productionReady,
    required this.overallStatus,
    required this.passCount,
    required this.warningCount,
    required this.blockingCount,
    required this.totalCount,
    required this.messageZh,
    required this.items,
    required this.generatedAt,
  });

  final bool productionReady;
  final String overallStatus;
  final int passCount;
  final int warningCount;
  final int blockingCount;
  final int totalCount;
  final String messageZh;
  final List<ProductionReadinessItem> items;
  final String generatedAt;

  String get statusZh => productionReady ? '通过' : '$blockingCount 个阻断';

  factory ProductionReadiness.fromJson(Map<String, dynamic> json) {
    return ProductionReadiness(
      productionReady: _bool(json['production_ready']),
      overallStatus: _string(json['overall_status']),
      passCount: _int(json['pass_count']),
      warningCount: _int(json['warning_count']),
      blockingCount: _int(json['blocking_count']),
      totalCount: _int(json['total_count']),
      messageZh: _string(json['message_zh']),
      items: _mapList(
        json['items'],
      ).map(ProductionReadinessItem.fromJson).toList(),
      generatedAt: _string(json['generated_at']),
    );
  }
}

class ProductionReadinessItem {
  ProductionReadinessItem({
    required this.id,
    required this.categoryZh,
    required this.requirementZh,
    required this.status,
    required this.blocking,
    required this.evidenceZh,
    required this.nextStepZh,
  });

  final String id;
  final String categoryZh;
  final String requirementZh;
  final String status;
  final bool blocking;
  final String evidenceZh;
  final String nextStepZh;

  bool get passed => status == 'pass';
  bool get warning => status == 'warn';

  String get statusZh {
    if (passed) return '通过';
    if (warning) return '警告';
    return blocking ? '阻断' : '失败';
  }

  factory ProductionReadinessItem.fromJson(Map<String, dynamic> json) {
    return ProductionReadinessItem(
      id: _string(json['id']),
      categoryZh: _string(json['category_zh']),
      requirementZh: _string(json['requirement_zh']),
      status: _string(json['status']),
      blocking: _bool(json['blocking']),
      evidenceZh: _string(json['evidence_zh']),
      nextStepZh: _string(json['next_step_zh']),
    );
  }
}

class LocalRuntimeConfig {
  LocalRuntimeConfig({
    required this.editable,
    required this.exists,
    required this.path,
    required this.items,
    required this.messageZh,
  });

  final bool editable;
  final bool exists;
  final String path;
  final List<LocalRuntimeConfigItem> items;
  final String messageZh;

  factory LocalRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return LocalRuntimeConfig(
      editable: _bool(json['editable']),
      exists: _bool(json['exists']),
      path: _string(json['path']),
      items: _mapList(
        json['items'],
      ).map(LocalRuntimeConfigItem.fromJson).toList(),
      messageZh: _string(json['message_zh']),
    );
  }
}

class LocalRuntimeConfigItem {
  LocalRuntimeConfigItem({
    required this.key,
    required this.labelZh,
    required this.descriptionZh,
    required this.groupZh,
    required this.placeholder,
    required this.setupHintZh,
    required this.configured,
    required this.secret,
    required this.source,
    required this.maskedValue,
    required this.restartRequired,
  });

  final String key;
  final String labelZh;
  final String descriptionZh;
  final String groupZh;
  final String placeholder;
  final String setupHintZh;
  final bool configured;
  final bool secret;
  final String source;
  final String maskedValue;
  final bool restartRequired;

  factory LocalRuntimeConfigItem.fromJson(Map<String, dynamic> json) {
    return LocalRuntimeConfigItem(
      key: _string(json['key']),
      labelZh: _string(json['label_zh']),
      descriptionZh: _string(json['description_zh']),
      groupZh: _string(json['group_zh']),
      placeholder: _string(json['placeholder']),
      setupHintZh: _string(json['setup_hint_zh']),
      configured: _bool(json['configured']),
      secret: _bool(json['secret']),
      source: _string(json['source']),
      maskedValue: _string(json['masked_value']),
      restartRequired: _bool(json['restart_required']),
    );
  }
}

class OnboardingChecklist {
  OnboardingChecklist({
    required this.completeCount,
    required this.totalCount,
    required this.nextActionZh,
    required this.steps,
  });

  final int completeCount;
  final int totalCount;
  final String nextActionZh;
  final List<OnboardingStep> steps;

  factory OnboardingChecklist.fromJson(Map<String, dynamic> json) {
    return OnboardingChecklist(
      completeCount: _int(json['complete_count']),
      totalCount: _int(json['total_count']),
      nextActionZh: _string(json['next_action_zh']),
      steps: _mapList(json['steps']).map(OnboardingStep.fromJson).toList(),
    );
  }
}

class OnboardingStep {
  OnboardingStep({
    required this.id,
    required this.labelZh,
    required this.status,
    required this.messageZh,
    required this.actionZh,
  });

  final String id;
  final String labelZh;
  final String status;
  final String messageZh;
  final String actionZh;

  bool get complete => status == 'complete';
  bool get warning => status == 'warning';

  factory OnboardingStep.fromJson(Map<String, dynamic> json) {
    return OnboardingStep(
      id: _string(json['id']),
      labelZh: _string(json['label_zh']),
      status: _string(json['status']),
      messageZh: _string(json['message_zh']),
      actionZh: _string(json['action_zh']),
    );
  }
}

class SmokeWorkflowReport {
  SmokeWorkflowReport({
    required this.available,
    required this.status,
    required this.messageZh,
    required this.generatedAt,
    required this.coreUrl,
    required this.market,
    required this.symbol,
    required this.failure,
    required this.reportPath,
    required this.artifacts,
    required this.steps,
  });

  final bool available;
  final String status;
  final String messageZh;
  final String generatedAt;
  final String coreUrl;
  final String market;
  final String symbol;
  final String failure;
  final String reportPath;
  final Map<String, dynamic> artifacts;
  final List<SmokeWorkflowStep> steps;

  bool get passed => status == 'passed';
  bool get missing => status == 'missing';

  factory SmokeWorkflowReport.fromJson(Map<String, dynamic> json) {
    return SmokeWorkflowReport(
      available: _bool(json['available']),
      status: _string(json['status']),
      messageZh: _string(json['message_zh']),
      generatedAt: _string(json['generated_at']),
      coreUrl: _string(json['core_url']),
      market: _string(json['market']),
      symbol: _string(json['symbol']),
      failure: _string(json['failure']),
      reportPath: _string(json['report_path']),
      artifacts: _map(json['artifacts']),
      steps: _mapList(json['steps']).map(SmokeWorkflowStep.fromJson).toList(),
    );
  }
}

class SmokeWorkflowStep {
  SmokeWorkflowStep({
    required this.name,
    required this.status,
    required this.durationMs,
    required this.message,
  });

  final String name;
  final String status;
  final int durationMs;
  final String message;

  bool get passed => status == 'passed';

  factory SmokeWorkflowStep.fromJson(Map<String, dynamic> json) {
    return SmokeWorkflowStep(
      name: _string(json['name']),
      status: _string(json['status']),
      durationMs: _int(json['duration_ms']),
      message: _string(json['message']),
    );
  }
}

class LlmReadiness {
  LlmReadiness({
    required this.provider,
    required this.model,
    required this.configured,
    required this.enabled,
    required this.fallbackAvailable,
    required this.messageZh,
  });

  final String provider;
  final String model;
  final bool configured;
  final bool enabled;
  final bool fallbackAvailable;
  final String messageZh;

  String get displayName {
    if (enabled && model.isNotEmpty) return model;
    return fallbackAvailable ? '本地兜底' : '未启用';
  }

  factory LlmReadiness.fromJson(Map<String, dynamic> json) {
    return LlmReadiness(
      provider: _string(json['provider']),
      model: _string(json['model']),
      configured: _bool(json['configured']),
      enabled: _bool(json['enabled']),
      fallbackAvailable: _bool(json['fallback_available'], fallback: true),
      messageZh: _string(json['message_zh']),
    );
  }
}

class RuntimeConfigItem {
  RuntimeConfigItem({
    required this.key,
    required this.labelZh,
    required this.configured,
    required this.messageZh,
  });

  final String key;
  final String labelZh;
  final bool configured;
  final String messageZh;

  factory RuntimeConfigItem.fromJson(Map<String, dynamic> json) {
    return RuntimeConfigItem(
      key: _string(json['key']),
      labelZh: _string(json['label_zh']),
      configured: _bool(json['configured']),
      messageZh: _string(json['message_zh']),
    );
  }
}

class NewsAdapterReadiness {
  NewsAdapterReadiness({
    required this.provider,
    required this.labelZh,
    required this.configured,
    required this.enabled,
    required this.requiresLicense,
    required this.messageZh,
  });

  final String provider;
  final String labelZh;
  final bool configured;
  final bool enabled;
  final bool requiresLicense;
  final String messageZh;

  factory NewsAdapterReadiness.fromJson(Map<String, dynamic> json) {
    return NewsAdapterReadiness(
      provider: _string(json['provider']),
      labelZh: _string(json['label_zh']),
      configured: _bool(json['configured']),
      enabled: _bool(json['enabled']),
      requiresLicense: _bool(json['requires_license']),
      messageZh: _string(json['message_zh']),
    );
  }
}

class NewsMarketCoverage {
  NewsMarketCoverage({
    required this.market,
    required this.labelZh,
    required this.demoReady,
    required this.licensedSourceReady,
    required this.productionReady,
    required this.availableSourcesZh,
    required this.missingSourcesZh,
    required this.messageZh,
    required this.nextStepZh,
  });

  final String market;
  final String labelZh;
  final bool demoReady;
  final bool licensedSourceReady;
  final bool productionReady;
  final List<String> availableSourcesZh;
  final List<String> missingSourcesZh;
  final String messageZh;
  final String nextStepZh;

  factory NewsMarketCoverage.fromJson(Map<String, dynamic> json) {
    return NewsMarketCoverage(
      market: _string(json['market']),
      labelZh: _string(json['label_zh']),
      demoReady: _bool(json['demo_ready']),
      licensedSourceReady: _bool(json['licensed_source_ready']),
      productionReady: _bool(json['production_ready']),
      availableSourcesZh: _stringList(json['available_sources_zh']),
      missingSourcesZh: _stringList(json['missing_sources_zh']),
      messageZh: _string(json['message_zh']),
      nextStepZh: _string(json['next_step_zh']),
    );
  }
}

class InstallPackageReadiness {
  InstallPackageReadiness({
    required this.platform,
    required this.labelZh,
    required this.artifactType,
    required this.available,
    required this.localPath,
    required this.sizeBytes,
    required this.buildChannelZh,
    required this.messageZh,
    required this.nextStepZh,
  });

  final String platform;
  final String labelZh;
  final String artifactType;
  final bool available;
  final String localPath;
  final int sizeBytes;
  final String buildChannelZh;
  final String messageZh;
  final String nextStepZh;

  factory InstallPackageReadiness.fromJson(Map<String, dynamic> json) {
    return InstallPackageReadiness(
      platform: _string(json['platform']),
      labelZh: _string(json['label_zh']),
      artifactType: _string(json['artifact_type']),
      available: _bool(json['available']),
      localPath: _string(json['local_path']),
      sizeBytes: _int(json['size_bytes']),
      buildChannelZh: _string(json['build_channel_zh']),
      messageZh: _string(json['message_zh']),
      nextStepZh: _string(json['next_step_zh']),
    );
  }
}

class LocalLauncherReadiness {
  LocalLauncherReadiness({
    required this.id,
    required this.labelZh,
    required this.descriptionZh,
    required this.localPath,
    required this.available,
    required this.messageZh,
    required this.nextStepZh,
  });

  final String id;
  final String labelZh;
  final String descriptionZh;
  final String localPath;
  final bool available;
  final String messageZh;
  final String nextStepZh;

  factory LocalLauncherReadiness.fromJson(Map<String, dynamic> json) {
    return LocalLauncherReadiness(
      id: _string(json['id']),
      labelZh: _string(json['label_zh']),
      descriptionZh: _string(json['description_zh']),
      localPath: _string(json['local_path']),
      available: _bool(json['available']),
      messageZh: _string(json['message_zh']),
      nextStepZh: _string(json['next_step_zh']),
    );
  }
}

class WorkspaceSnapshot {
  WorkspaceSnapshot({
    required this.workspaceId,
    required this.workspaceName,
    required this.watchlist,
    required this.strategyDrafts,
    required this.backtestResults,
    required this.assistantTurns,
    required this.events,
    required this.serverSequence,
  });

  final String workspaceId;
  final String workspaceName;
  final List<WatchlistItem> watchlist;
  final List<StrategyDraft> strategyDrafts;
  final List<BacktestResult> backtestResults;
  final List<AssistantConversationTurn> assistantTurns;
  final List<SyncEvent> events;
  final int serverSequence;

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final workspace = _map(json['workspace']);
    return WorkspaceSnapshot(
      workspaceId: _string(workspace['id']),
      workspaceName: _string(workspace['name']),
      watchlist: _mapList(
        json['watchlist'],
      ).map(WatchlistItem.fromJson).toList(),
      strategyDrafts: _mapList(
        json['strategy_drafts'],
      ).map(StrategyDraft.fromJson).toList(),
      backtestResults: _mapList(
        json['backtest_results'],
      ).map(BacktestResult.fromJson).toList(),
      assistantTurns: _mapList(
        json['assistant_turns'],
      ).map(AssistantConversationTurn.fromJson).toList(),
      events: _mapList(json['events']).map(SyncEvent.fromJson).toList(),
      serverSequence: _int(json['server_sequence']),
    );
  }
}

class WatchlistItem {
  WatchlistItem({
    required this.symbol,
    required this.name,
    required this.market,
    required this.notesZh,
  });

  final String symbol;
  final String name;
  final String market;
  final String notesZh;

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      symbol: _string(json['symbol']),
      name: _string(json['name']),
      market: _string(json['market']),
      notesZh: _string(json['notes_zh']),
    );
  }
}

class SyncEvent {
  SyncEvent({
    required this.sequence,
    required this.entityType,
    required this.action,
    required this.createdAt,
  });

  final int sequence;
  final String entityType;
  final String action;
  final String createdAt;

  factory SyncEvent.fromJson(Map<String, dynamic> json) {
    return SyncEvent(
      sequence: _int(json['sequence']),
      entityType: _string(json['entity_type']),
      action: _string(json['action']),
      createdAt: _string(json['created_at']),
    );
  }

  static SyncEvent? tryParseMessage(dynamic message) {
    try {
      final raw = message is List<int> ? utf8.decode(message) : '$message';
      return SyncEvent.fromJson(_map(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
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
    required this.marketScope,
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
  final List<String> marketScope;
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
      marketScope: _stringList(json['market_scope']),
      tickers: _stringList(json['tickers']),
      eventType: _string(json['event_type']),
      authorityScore: _double(json['authority_score']),
    );
  }
}

class NewsAnalysis {
  NewsAnalysis({
    required this.id,
    required this.newsEventId,
    required this.summaryZh,
    required this.sentiment,
    required this.impactScore,
    required this.affectedTickers,
    required this.sourceRefs,
    required this.confidence,
    required this.generatedAt,
  });

  final String id;
  final String newsEventId;
  final String summaryZh;
  final String sentiment;
  final double impactScore;
  final List<String> affectedTickers;
  final List<String> sourceRefs;
  final double confidence;
  final String generatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'news_event_id': newsEventId,
      'summary_zh': summaryZh,
      'sentiment': sentiment,
      'impact_score': impactScore,
      'affected_tickers': affectedTickers,
      'source_refs': sourceRefs,
      'confidence': confidence,
      'generated_at': generatedAt,
    };
  }

  factory NewsAnalysis.fromJson(Map<String, dynamic> json) {
    return NewsAnalysis(
      id: _string(json['id']),
      newsEventId: _string(json['news_event_id']),
      summaryZh: _string(json['summary_zh']),
      sentiment: _string(json['sentiment']),
      impactScore: _double(json['impact_score']),
      affectedTickers: _stringList(json['affected_tickers']),
      sourceRefs: _stringList(json['source_refs']),
      confidence: _double(json['confidence']),
      generatedAt: _string(json['generated_at']),
    );
  }
}

class StrategyDraft {
  StrategyDraft({
    required this.id,
    required this.strategyVersionId,
    required this.name,
    required this.spec,
    required this.explanationZh,
    required this.generatedCode,
    required this.sourceAnalysisId,
    required this.createdAt,
  });

  final String id;
  final String strategyVersionId;
  final String name;
  final StrategySpec spec;
  final String explanationZh;
  final String generatedCode;
  final String sourceAnalysisId;
  final String createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'strategy_version_id': strategyVersionId,
      'name': name,
      'spec': spec.toJson(),
      'explanation_zh': explanationZh,
      'generated_code': generatedCode,
      'source_analysis_id': sourceAnalysisId,
      'created_at': createdAt,
    };
  }

  factory StrategyDraft.fromJson(Map<String, dynamic> json) {
    return StrategyDraft(
      id: _string(json['id']),
      strategyVersionId: _string(json['strategy_version_id']),
      name: _string(json['name']),
      spec: StrategySpec.fromJson(_map(json['spec'])),
      explanationZh: _string(json['explanation_zh']),
      generatedCode: _string(json['generated_code']),
      sourceAnalysisId: _string(json['source_analysis_id']),
      createdAt: _string(json['created_at']),
    );
  }
}

class StrategySpec {
  StrategySpec({
    required this.strategyName,
    required this.marketScope,
    required this.assetUniverse,
    required this.entryRules,
    required this.exitRules,
    required this.riskLimits,
    required this.timeframe,
    required this.rebalanceRule,
    required this.dataDependencies,
    required this.brokerPermissions,
  });

  final String strategyName;
  final List<String> marketScope;
  final List<String> assetUniverse;
  final List<String> entryRules;
  final List<String> exitRules;
  final Map<String, double> riskLimits;
  final String timeframe;
  final String rebalanceRule;
  final List<String> dataDependencies;
  final List<String> brokerPermissions;

  Map<String, dynamic> toJson() {
    return {
      'strategy_name': strategyName,
      'market_scope': marketScope,
      'asset_universe': assetUniverse,
      'entry_rules': entryRules,
      'exit_rules': exitRules,
      'risk_limits': riskLimits,
      'timeframe': timeframe,
      'rebalance_rule': rebalanceRule,
      'data_dependencies': dataDependencies,
      'broker_permissions': brokerPermissions,
    };
  }

  factory StrategySpec.fromJson(Map<String, dynamic> json) {
    return StrategySpec(
      strategyName: _string(json['strategy_name']),
      marketScope: _stringList(json['market_scope']),
      assetUniverse: _stringList(json['asset_universe']),
      entryRules: _stringList(json['entry_rules']),
      exitRules: _stringList(json['exit_rules']),
      riskLimits: _doubleMap(json['risk_limits']),
      timeframe: _string(json['timeframe']),
      rebalanceRule: _string(json['rebalance_rule']),
      dataDependencies: _stringList(json['data_dependencies']),
      brokerPermissions: _stringList(json['broker_permissions']),
    );
  }
}

class BacktestResult {
  BacktestResult({
    required this.id,
    required this.strategyVersionId,
    required this.replayScenario,
    required this.symbol,
    required this.market,
    required this.initialCash,
    required this.finalEquity,
    required this.totalReturn,
    required this.benchmarkReturn,
    required this.maxDrawdown,
    required this.winRate,
    required this.tradeCount,
    required this.riskNotesZh,
  });

  final String id;
  final String strategyVersionId;
  final String replayScenario;
  final String symbol;
  final String market;
  final double initialCash;
  final double finalEquity;
  final double totalReturn;
  final double benchmarkReturn;
  final double maxDrawdown;
  final double winRate;
  final int tradeCount;
  final List<String> riskNotesZh;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'strategy_version_id': strategyVersionId,
      'replay_scenario': replayScenario,
      'symbol': symbol,
      'market': market,
      'initial_cash': initialCash,
      'final_equity': finalEquity,
      'total_return': totalReturn,
      'benchmark_return': benchmarkReturn,
      'max_drawdown': maxDrawdown,
      'win_rate': winRate,
      'trade_count': tradeCount,
      'risk_notes_zh': riskNotesZh,
      'equity_curve': const [],
    };
  }

  factory BacktestResult.fromJson(Map<String, dynamic> json) {
    return BacktestResult(
      id: _string(json['id']),
      strategyVersionId: _string(json['strategy_version_id']),
      replayScenario: _string(json['replay_scenario']),
      symbol: _string(json['symbol']),
      market: _string(json['market']),
      initialCash: _double(json['initial_cash']),
      finalEquity: _double(json['final_equity']),
      totalReturn: _double(json['total_return']),
      benchmarkReturn: _double(json['benchmark_return']),
      maxDrawdown: _double(json['max_drawdown']),
      winRate: _double(json['win_rate']),
      tradeCount: _int(json['trade_count']),
      riskNotesZh: _stringList(json['risk_notes_zh']),
    );
  }
}

class AssistantCitation {
  AssistantCitation({required this.labelZh, required this.ref});

  final String labelZh;
  final String ref;

  factory AssistantCitation.fromJson(Map<String, dynamic> json) {
    return AssistantCitation(
      labelZh: _string(json['label_zh']),
      ref: _string(json['ref']),
    );
  }
}

class AssistantChatResponse {
  AssistantChatResponse({
    required this.id,
    required this.answerZh,
    required this.citations,
    required this.suggestedActionsZh,
    required this.safetyNotesZh,
    required this.modelProvider,
    required this.modelName,
    required this.fallbackUsed,
    required this.generatedAt,
  });

  final String id;
  final String answerZh;
  final List<AssistantCitation> citations;
  final List<String> suggestedActionsZh;
  final List<String> safetyNotesZh;
  final String modelProvider;
  final String modelName;
  final bool fallbackUsed;
  final String generatedAt;

  factory AssistantChatResponse.fromJson(Map<String, dynamic> json) {
    return AssistantChatResponse(
      id: _string(json['id']),
      answerZh: _string(json['answer_zh']),
      citations: _mapList(
        json['citations'],
      ).map(AssistantCitation.fromJson).toList(),
      suggestedActionsZh: _stringList(json['suggested_actions_zh']),
      safetyNotesZh: _stringList(json['safety_notes_zh']),
      modelProvider: _string(json['model_provider']),
      modelName: _string(json['model_name']),
      fallbackUsed: _bool(json['fallback_used'], fallback: true),
      generatedAt: _string(json['generated_at']),
    );
  }
}

class AssistantConversationTurn {
  AssistantConversationTurn({
    required this.id,
    required this.questionZh,
    required this.answerZh,
    required this.citations,
    required this.suggestedActionsZh,
    required this.safetyNotesZh,
    required this.modelProvider,
    required this.modelName,
    required this.fallbackUsed,
    required this.generatedAt,
  });

  final String id;
  final String questionZh;
  final String answerZh;
  final List<AssistantCitation> citations;
  final List<String> suggestedActionsZh;
  final List<String> safetyNotesZh;
  final String modelProvider;
  final String modelName;
  final bool fallbackUsed;
  final String generatedAt;

  factory AssistantConversationTurn.fromJson(Map<String, dynamic> json) {
    return AssistantConversationTurn(
      id: _string(json['id']),
      questionZh: _string(json['question_zh']),
      answerZh: _string(json['answer_zh']),
      citations: _mapList(
        json['citations'],
      ).map(AssistantCitation.fromJson).toList(),
      suggestedActionsZh: _stringList(json['suggested_actions_zh']),
      safetyNotesZh: _stringList(json['safety_notes_zh']),
      modelProvider: _string(json['model_provider']),
      modelName: _string(json['model_name']),
      fallbackUsed: _bool(json['fallback_used'], fallback: true),
      generatedAt: _string(json['generated_at']),
    );
  }
}

class PaperOrder {
  PaperOrder({required this.id, required this.status, required this.messageZh});

  final String id;
  final String status;
  final String messageZh;

  factory PaperOrder.fromJson(Map<String, dynamic> json) {
    return PaperOrder(
      id: _string(json['id']),
      status: _string(json['status']),
      messageZh: _string(json['message_zh']),
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
      positions: _mapList(
        json['positions'],
      ).map(PaperPosition.fromJson).toList(),
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

class RiskDecision {
  RiskDecision({
    required this.id,
    required this.orderIntentId,
    required this.status,
    required this.allowedDestination,
    required this.notional,
    required this.reasonsZh,
    required this.evaluatedAt,
  });

  final String id;
  final String orderIntentId;
  final String status;
  final String allowedDestination;
  final double notional;
  final List<String> reasonsZh;
  final String evaluatedAt;

  bool get requiresApproval => status == 'requires_approval';

  factory RiskDecision.fromJson(Map<String, dynamic> json) {
    return RiskDecision(
      id: _string(json['id']),
      orderIntentId: _string(json['order_intent_id']),
      status: _string(json['status']),
      allowedDestination: _string(json['allowed_destination']),
      notional: _double(json['notional']),
      reasonsZh: _stringList(json['reasons_zh']),
      evaluatedAt: _string(json['evaluated_at']),
    );
  }
}

class KillSwitchState {
  KillSwitchState({
    required this.enabled,
    required this.reasonZh,
    required this.updatedBy,
    required this.updatedAt,
  });

  final bool enabled;
  final String reasonZh;
  final String updatedBy;
  final String updatedAt;

  factory KillSwitchState.fromJson(Map<String, dynamic> json) {
    return KillSwitchState(
      enabled: _bool(json['enabled']),
      reasonZh: _string(json['reason_zh']),
      updatedBy: _string(json['updated_by']),
      updatedAt: _string(json['updated_at']),
    );
  }
}

class AuditLogEntry {
  AuditLogEntry({
    required this.id,
    required this.actorRole,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.summaryZh,
    required this.createdAt,
  });

  final String id;
  final String actorRole;
  final String action;
  final String targetType;
  final String targetId;
  final String summaryZh;
  final String createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: _string(json['id']),
      actorRole: _string(json['actor_role']),
      action: _string(json['action']),
      targetType: _string(json['target_type']),
      targetId: _string(json['target_id']),
      summaryZh: _string(json['summary_zh']),
      createdAt: _string(json['created_at']),
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
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
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

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

bool _bool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return '$value'.toLowerCase() == 'true';
}
