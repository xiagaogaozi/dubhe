import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_client.dart';

const coreUrlPreferenceKey = 'dubhe.core_url';
const defaultCoreUrl = String.fromEnvironment(
  'DUBHE_CORE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class DubheCompanionApp extends StatelessWidget {
  const DubheCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dubhe Companion',
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F3D31),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F2EA),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _apiController = TextEditingController(text: defaultCoreUrl);
  final _accountController = TextEditingController(text: 'local-demo');
  final _nameController = TextEditingController(text: '本地演示账户');
  final _passwordController = TextEditingController(text: 'Dubhe@2026');
  final _mfaController = TextEditingController(text: '000000');

  _AuthMode _authMode = _AuthMode.register;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedCoreUrl();
  }

  @override
  void dispose() {
    _apiController.dispose();
    _accountController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _mfaController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCoreUrl() async {
    final preferences = await SharedPreferences.getInstance();
    final savedUrl = preferences.getString(coreUrlPreferenceKey);
    if (!mounted || savedUrl == null || savedUrl.isEmpty) return;
    _apiController.text = savedUrl;
  }

  Future<void> _enterWorkspace() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final client = CoreClient(baseUrl: _apiController.text.trim());
    final platform = _mobilePlatform();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        coreUrlPreferenceKey,
        _apiController.text.trim(),
      );
      final session = _authMode == _AuthMode.login
          ? await client.login(
              accountKey: _accountController.text.trim(),
              password: _passwordController.text,
              mfaCode: _mfaController.text.trim(),
              deviceName: 'Dubhe Companion',
              platform: platform,
            )
          : await client.registerAccount(
              accountKey: _accountController.text.trim(),
              accountName: _nameController.text.trim(),
              password: _passwordController.text,
              mfaCode: _mfaController.text.trim(),
              deviceName: 'Dubhe Companion',
              platform: platform,
            );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CompanionHome(client: client, session: session),
        ),
      );
    } catch (error) {
      client.close();
      setState(() {
        _error = error is DubheApiException
            ? error.message
            : '无法连接 Dubhe Core。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 28),
            const _BrandHeader(),
            const SizedBox(height: 28),
            SegmentedButton<_AuthMode>(
              segments: const [
                ButtonSegment(value: _AuthMode.register, label: Text('创建账号')),
                ButtonSegment(value: _AuthMode.login, label: Text('登录')),
              ],
              selected: {_authMode},
              onSelectionChanged: _busy
                  ? null
                  : (selected) => setState(() => _authMode = selected.single),
            ),
            const SizedBox(height: 16),
            _TextInput(controller: _apiController, label: 'Core 地址'),
            _TextInput(controller: _accountController, label: '账号'),
            if (_authMode == _AuthMode.register)
              _TextInput(controller: _nameController, label: '显示名称'),
            _TextInput(
              controller: _passwordController,
              label: '密码',
              obscureText: true,
            ),
            _TextInput(controller: _mfaController, label: 'MFA 验证码'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _enterWorkspace,
              child: Text(
                _busy
                    ? '正在进入...'
                    : _authMode == _AuthMode.login
                    ? '登录工作台'
                    : '创建并进入',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AuthMode { register, login }

enum _MobileSyncConnectionStatus {
  disconnected,
  connecting,
  live,
  polling,
  reconnecting,
  offline,
}

class _AssistantChatMessage {
  const _AssistantChatMessage({
    required this.role,
    required this.text,
    this.citations = const [],
    this.suggestedActions = const [],
  });

  final String role;
  final String text;
  final List<AssistantCitation> citations;
  final List<String> suggestedActions;

  bool get isUser => role == 'user';
}

const _assistantWelcomeMessages = [
  _AssistantChatMessage(
    role: 'assistant',
    text: '可以直接问我新闻影响、策略规则、回测结果和纸面验证路径。',
  ),
];

extension _TakeLastMessages<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) return List<T>.of(this);
    return sublist(length - count);
  }
}

List<_AssistantChatMessage> _assistantMessagesFromTurns(
  List<AssistantConversationTurn> turns,
) {
  if (turns.isEmpty) return _assistantWelcomeMessages;
  final messages = <_AssistantChatMessage>[];
  for (final turn in turns) {
    messages.add(_AssistantChatMessage(role: 'user', text: turn.questionZh));
    messages.add(
      _AssistantChatMessage(
        role: 'assistant',
        text: turn.answerZh,
        citations: turn.citations,
        suggestedActions: turn.suggestedActionsZh,
      ),
    );
  }
  return messages.takeLast(8);
}

class CompanionHome extends StatefulWidget {
  const CompanionHome({required this.client, required this.session, super.key});

  final CoreClient client;
  final DeviceSession session;

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  int _tabIndex = 0;
  bool _loading = false;
  bool _analyzing = false;
  bool _riskBusy = false;
  String? _message;
  String? _approvalMessage;
  NewsFeed? _newsFeed;
  NewsAnalysis? _analysis;
  StrategyDraft? _strategyDraft;
  BacktestResult? _backtestResult;
  PaperOrder? _paperOrder;
  PaperPortfolio? _portfolio;
  SystemStatus? _systemStatus;
  WorkspaceSnapshot? _workspaceSnapshot;
  _MobileSyncConnectionStatus _syncStatus =
      _MobileSyncConnectionStatus.disconnected;
  SyncEvent? _lastPushedSyncEvent;
  WorkspaceSyncConnection? _syncConnection;
  StreamSubscription<SyncEvent>? _syncSubscription;
  Timer? _syncReconnectTimer;
  Timer? _syncPollingTimer;
  bool _syncPollingBusy = false;
  int _syncCursor = 0;
  int _syncRetryCount = 0;
  int _syncConnectGeneration = 0;
  KillSwitchState? _killSwitch;
  List<AuditLogEntry> _auditLogs = const [];
  List<ApprovalRequest> _approvals = const [];
  bool _assistantBusy = false;
  String _assistantQuestion = '这条新闻会影响哪些股票？';
  List<_AssistantChatMessage> _assistantMessages = _assistantWelcomeMessages;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh().whenComplete(_connectWorkspaceSync));
  }

  @override
  void dispose() {
    _syncConnectGeneration += 1;
    _closeWorkspaceSync();
    widget.client.close();
    super.dispose();
  }

  Future<void> _connectWorkspaceSync() async {
    if (!mounted) return;
    final generation = ++_syncConnectGeneration;
    _closeWorkspaceSync();
    setState(() {
      _syncStatus = _syncRetryCount == 0
          ? _MobileSyncConnectionStatus.connecting
          : _MobileSyncConnectionStatus.reconnecting;
    });

    try {
      final connection = await widget.client.connectWorkspaceSyncEvents(
        workspaceId: widget.session.workspaceId,
        sinceSequence: _syncCursor,
      );
      if (!mounted || generation != _syncConnectGeneration) {
        unawaited(connection.close());
        return;
      }
      _syncConnection = connection;
      _stopWorkspaceSyncPolling();
      _syncSubscription = connection.events.listen(
        _handleSyncEvent,
        onError: (_) => _scheduleWorkspaceSyncReconnect(generation),
        onDone: () => _scheduleWorkspaceSyncReconnect(generation),
      );
      _syncRetryCount = 0;
      setState(() {
        _syncStatus = _MobileSyncConnectionStatus.live;
      });
    } catch (_) {
      if (!mounted || generation != _syncConnectGeneration) return;
      setState(() {
        _syncStatus = _MobileSyncConnectionStatus.offline;
      });
      _scheduleWorkspaceSyncReconnect(generation);
    }
  }

  void _closeWorkspaceSync() {
    _syncReconnectTimer?.cancel();
    _syncReconnectTimer = null;
    _stopWorkspaceSyncPolling();
    unawaited(_syncSubscription?.cancel());
    _syncSubscription = null;
    unawaited(_syncConnection?.close());
    _syncConnection = null;
  }

  void _scheduleWorkspaceSyncReconnect(int generation) {
    if (generation != _syncConnectGeneration) return;
    if (!mounted || _syncReconnectTimer != null) return;
    _syncRetryCount += 1;
    setState(() {
      _syncStatus = _MobileSyncConnectionStatus.reconnecting;
    });
    _startWorkspaceSyncPolling(generation);
    final seconds = _syncRetryCount > 15 ? 15 : _syncRetryCount;
    _syncReconnectTimer = Timer(Duration(seconds: seconds), () {
      _syncReconnectTimer = null;
      unawaited(_connectWorkspaceSync());
    });
  }

  void _startWorkspaceSyncPolling(int generation) {
    if (generation != _syncConnectGeneration || _syncPollingTimer != null) {
      return;
    }
    setState(() {
      _syncStatus = _MobileSyncConnectionStatus.polling;
    });
    unawaited(_pollWorkspaceSyncEvents(generation));
    _syncPollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_pollWorkspaceSyncEvents(generation));
    });
  }

  void _stopWorkspaceSyncPolling() {
    _syncPollingTimer?.cancel();
    _syncPollingTimer = null;
    _syncPollingBusy = false;
  }

  Future<void> _pollWorkspaceSyncEvents(int generation) async {
    if (!mounted || generation != _syncConnectGeneration || _syncPollingBusy) {
      return;
    }
    _syncPollingBusy = true;
    try {
      final events = await widget.client.fetchWorkspaceSyncEvents(
        workspaceId: widget.session.workspaceId,
        sinceSequence: _syncCursor,
      );
      if (!mounted || generation != _syncConnectGeneration) return;
      if (events.isNotEmpty) {
        _handleSyncEvents(events);
      }
      if (_syncStatus != _MobileSyncConnectionStatus.live) {
        setState(() {
          _syncStatus = _MobileSyncConnectionStatus.polling;
        });
      }
    } catch (_) {
      if (!mounted || generation != _syncConnectGeneration) return;
      setState(() {
        _syncStatus = _MobileSyncConnectionStatus.reconnecting;
      });
    } finally {
      _syncPollingBusy = false;
    }
  }

  void _handleSyncEvent(SyncEvent event) {
    _handleSyncEvents([event]);
  }

  void _handleSyncEvents(List<SyncEvent> events) {
    if (events.isEmpty) return;
    for (final event in events) {
      if (event.sequence > _syncCursor) {
        _syncCursor = event.sequence;
      }
    }
    if (!mounted) return;
    setState(() {
      _lastPushedSyncEvent = events.last;
    });
    unawaited(_refreshFromSyncEvents(events));
  }

  Future<void> _refreshFromSyncEvents(List<SyncEvent> events) async {
    try {
      final refreshes = <Future<void>>[_refreshWorkspaceSnapshotFromSync()];
      if (events.any(_syncEventTouchesPortfolio)) {
        refreshes.add(_refreshPortfolioFromSync());
      }
      if (events.any(_syncEventTouchesRiskCenter)) {
        refreshes.add(_refreshRiskControls(markBusy: false));
      }
      await Future.wait(refreshes);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error is DubheApiException ? error.message : '实时同步刷新失败。';
      });
    }
  }

  Future<void> _refreshWorkspaceSnapshotFromSync() async {
    final snapshot = await widget.client.fetchWorkspaceSnapshot(
      workspaceId: widget.session.workspaceId,
    );
    if (!mounted) return;
    if (snapshot.serverSequence > _syncCursor) {
      _syncCursor = snapshot.serverSequence;
    }
    final syncedBacktest = latestSyncedBacktest(
      strategyDraft: _strategyDraft,
      backtestResults: snapshot.backtestResults,
    );
    setState(() {
      _workspaceSnapshot = snapshot;
      _assistantMessages = _assistantMessagesFromTurns(snapshot.assistantTurns);
      if (syncedBacktest != null) {
        _backtestResult = syncedBacktest;
      }
    });
  }

  Future<void> _refreshPortfolioFromSync() async {
    final portfolio = await widget.client.fetchPaperPortfolio(
      defaultPaperAccountId,
    );
    if (!mounted) return;
    setState(() {
      _portfolio = portfolio;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final coreResponses = await Future.wait<dynamic>([
        widget.client.fetchSystemStatus(),
        widget.client.fetchNewsFeed(live: false),
        widget.client.fetchPaperPortfolio(defaultPaperAccountId),
        widget.client.fetchWorkspaceSnapshot(
          workspaceId: widget.session.workspaceId,
        ),
      ]);
      final systemStatus = coreResponses[0] as SystemStatus;
      final newsFeed = coreResponses[1] as NewsFeed;
      final portfolio = coreResponses[2] as PaperPortfolio;
      final workspaceSnapshot = coreResponses[3] as WorkspaceSnapshot;
      var approvals = <ApprovalRequest>[];
      KillSwitchState? killSwitch;
      var auditLogs = <AuditLogEntry>[];
      String? approvalMessage;
      if (widget.session.canReviewApprovals) {
        try {
          final riskResponses = await Future.wait<dynamic>([
            widget.client.fetchApprovals(),
            widget.client.fetchKillSwitch(),
            widget.client.fetchAuditLogs(),
          ]);
          approvals = riskResponses[0] as List<ApprovalRequest>;
          killSwitch = riskResponses[1] as KillSwitchState;
          auditLogs = riskResponses[2] as List<AuditLogEntry>;
          approvalMessage = approvals.isEmpty
              ? '当前没有待处理审批。'
              : '当前有 ${approvals.length} 个待处理审批。';
        } on DubheApiException catch (error) {
          approvalMessage = error.statusCode == 403
              ? '当前账号没有审批权限。'
              : error.message;
        }
      } else {
        approvalMessage = '当前账号没有审批权限。管理员或风控管理员登录后可管理审批和 kill switch。';
      }

      if (!mounted) return;
      if (workspaceSnapshot.serverSequence > _syncCursor) {
        _syncCursor = workspaceSnapshot.serverSequence;
      }
      final syncedBacktest = latestSyncedBacktest(
        strategyDraft: _strategyDraft,
        backtestResults: workspaceSnapshot.backtestResults,
      );
      setState(() {
        _systemStatus = systemStatus;
        _newsFeed = newsFeed;
        _portfolio = portfolio;
        _workspaceSnapshot = workspaceSnapshot;
        _assistantMessages = _assistantMessagesFromTurns(
          workspaceSnapshot.assistantTurns,
        );
        if (syncedBacktest != null) {
          _backtestResult = syncedBacktest;
        }
        _approvals = approvals;
        _killSwitch = killSwitch;
        _auditLogs = auditLogs;
        _approvalMessage = approvalMessage;
      });
    } catch (error) {
      setState(() {
        _message = error is DubheApiException
            ? error.message
            : '同步失败，请检查 Core 地址。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _analyzeTopNews() async {
    final events = _newsFeed?.events ?? const <NewsEvent>[];
    final event = events.isEmpty ? null : events.first;
    if (event == null) return;

    setState(() {
      _analyzing = true;
      _message = null;
    });
    try {
      final analysis = await widget.client.analyzeNews(event);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _strategyDraft = null;
        _backtestResult = null;
        _paperOrder = null;
      });
    } catch (error) {
      setState(() {
        _message = error is DubheApiException ? error.message : 'AI 分析失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
        });
      }
    }
  }

  Future<void> _draftStrategy() async {
    final analysis = _analysis;
    final event = _firstNewsEvent;
    if (analysis == null || event == null) {
      setState(() => _message = '请先生成新闻影响分析。');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final draft = await widget.client.draftStrategyFromAnalysis(
        analysis: analysis,
        symbol: _primarySymbol(event),
        market: _primaryMarket(event),
      );
      if (!mounted) return;
      setState(() {
        _strategyDraft = draft;
        _backtestResult = null;
        _paperOrder = null;
      });
    } catch (error) {
      setState(() {
        _message = error is DubheApiException ? error.message : '策略草案生成失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _runBacktest() async {
    final draft = _strategyDraft;
    if (draft == null) {
      setState(() => _message = '请先生成策略草案。');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final backtest = await widget.client.runReplayBacktest(strategy: draft);
      if (!mounted) return;
      setState(() {
        _backtestResult = backtest;
      });
    } catch (error) {
      setState(() {
        _message = error is DubheApiException ? error.message : '回测失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _askAssistant() async {
    final question = _assistantQuestion.trim();
    if (question.isEmpty || _assistantBusy) return;
    final event = _firstNewsEvent;
    setState(() {
      _assistantBusy = true;
      _assistantQuestion = '';
      _assistantMessages = [
        ..._assistantMessages,
        _AssistantChatMessage(role: 'user', text: question),
      ].takeLast(8);
      _message = null;
    });
    try {
      final response = await widget.client.askAssistant(
        questionZh: question,
        newsEvent: event,
        analysis: _analysis,
        strategyDraft: _strategyDraft,
        backtestResult: _backtestResult,
      );
      if (!mounted) return;
      setState(() {
        _assistantMessages = [
          ..._assistantMessages,
          _AssistantChatMessage(
            role: 'assistant',
            text: response.answerZh,
            citations: response.citations,
            suggestedActions: response.suggestedActionsZh,
          ),
        ].takeLast(8);
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is DubheApiException
          ? error.message
          : 'AI 分析师对话失败。';
      setState(() {
        _message = message;
        _assistantMessages = [
          ..._assistantMessages,
          _AssistantChatMessage(role: 'assistant', text: message),
        ].takeLast(8);
      });
    } finally {
      if (mounted) {
        setState(() {
          _assistantBusy = false;
        });
      }
    }
  }

  void _setAssistantPrompt(String prompt) {
    setState(() {
      _assistantQuestion = prompt;
    });
  }

  Future<void> _submitPaperBuy() async {
    final analysis = _analysis;
    final draft = _strategyDraft;
    final event = _firstNewsEvent;
    if (!canSubmitPaperTrade(analysis: analysis, strategyDraft: draft)) {
      setState(() => _message = '请先完成新闻分析或加载同步策略。');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final symbol = paperTradeSymbol(strategyDraft: draft, event: event);
      final market = paperTradeMarket(
        strategyDraft: draft,
        event: event,
        symbol: symbol,
      );
      final order = await widget.client.submitPaperBuy(
        accountId: defaultPaperAccountId,
        strategyVersionId: draft?.strategyVersionId ?? 'mobile_manual_strategy',
        market: market,
        symbol: symbol,
        quantity: 1,
        estimatedPrice: _estimatedPrice(symbol),
        currency: _currencyForMarket(market),
        sourceRefs: [
          paperTradeSourceRef(
            analysis: analysis,
            strategyDraft: draft,
            event: event,
          ),
        ],
      );
      final portfolio = await widget.client.fetchPaperPortfolio(
        defaultPaperAccountId,
      );
      if (!mounted) return;
      setState(() {
        _paperOrder = order;
        _portfolio = portfolio;
      });
    } catch (error) {
      setState(() {
        _message = error is DubheApiException ? error.message : '纸面交易提交失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  NewsEvent? get _firstNewsEvent {
    final events = _newsFeed?.events ?? const <NewsEvent>[];
    return events.isEmpty ? null : events.first;
  }

  Future<void> _decideApproval(ApprovalRequest approval, bool approve) async {
    if (!widget.session.canReviewApprovals) {
      setState(() {
        _approvalMessage = '当前账号没有审批权限。';
      });
      return;
    }

    setState(() {
      _riskBusy = true;
      _approvalMessage = null;
    });
    try {
      await widget.client.decideApproval(
        approvalId: approval.id,
        approve: approve,
        comment: approve ? '移动端通过。' : '移动端拒绝。',
      );
      await _refreshRiskControls(markBusy: false);
    } catch (error) {
      setState(() {
        _approvalMessage = error is DubheApiException
            ? error.message
            : '审批操作失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _riskBusy = false;
        });
      }
    }
  }

  Future<void> _toggleKillSwitch(bool enabled) async {
    if (!widget.session.canReviewApprovals) {
      setState(() {
        _approvalMessage = '当前账号没有急停权限。';
      });
      return;
    }

    setState(() {
      _riskBusy = true;
      _approvalMessage = null;
    });
    try {
      final nextState = await widget.client.setKillSwitch(
        enabled: enabled,
        reason: enabled ? '移动端手动启用 kill switch。' : '移动端解除 kill switch。',
        updatedBy: widget.session.deviceName.isEmpty
            ? 'dubhe-mobile'
            : widget.session.deviceName,
      );
      if (!mounted) return;
      setState(() {
        _killSwitch = nextState;
        _approvalMessage = nextState.reasonZh;
      });
    } catch (error) {
      setState(() {
        _approvalMessage = error is DubheApiException
            ? error.message
            : '更新 kill switch 失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _riskBusy = false;
        });
      }
    }
  }

  Future<void> _createLiveApprovalDemo() async {
    if (!widget.session.canReviewApprovals) {
      setState(() {
        _approvalMessage = '请使用管理员或风控管理员账号创建审批演示。';
      });
      return;
    }

    final event = _firstNewsEvent;
    final draft = _strategyDraft;
    if (event == null && draft == null) {
      setState(() {
        _approvalMessage = '请先同步新闻或加载同步策略后再生成审批演示。';
      });
      return;
    }

    setState(() {
      _riskBusy = true;
      _approvalMessage = null;
    });
    try {
      final symbol = paperTradeSymbol(strategyDraft: draft, event: event);
      final market = paperTradeMarket(
        strategyDraft: draft,
        event: event,
        symbol: symbol,
      );
      final sourceRef = paperTradeSourceRef(
        analysis: _analysis,
        strategyDraft: draft,
        event: event,
      );
      final decision = await widget.client.createLiveApprovalDemo(
        accountId: defaultPaperAccountId,
        strategyVersionId:
            draft?.strategyVersionId ?? 'mobile_live_approval_demo',
        market: market,
        symbol: symbol,
        quantity: 1,
        estimatedPrice: _estimatedPrice(symbol),
        currency: _currencyForMarket(market),
        sourceRefs: [sourceRef],
      );
      await _refreshRiskControls(markBusy: false);
      if (!mounted) return;
      setState(() {
        _approvalMessage = decision.requiresApproval
            ? '已生成实盘审批演示：$symbol，名义金额 ${decision.notional.toStringAsFixed(2)}。'
            : '风控评估完成：${_riskStatusZh(decision.status)}。';
      });
    } catch (error) {
      setState(() {
        _approvalMessage = error is DubheApiException
            ? error.message
            : '实盘审批演示生成失败。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _riskBusy = false;
        });
      }
    }
  }

  Future<void> _refreshRiskControls({bool markBusy = true}) async {
    if (!widget.session.canReviewApprovals) {
      if (!mounted) return;
      setState(() {
        _approvals = const [];
        _killSwitch = null;
        _auditLogs = const [];
        _approvalMessage = '当前账号没有审批权限。管理员或风控管理员登录后可管理审批和 kill switch。';
      });
      return;
    }

    if (markBusy) {
      setState(() {
        _riskBusy = true;
        _approvalMessage = null;
      });
    }
    try {
      final riskResponses = await Future.wait<dynamic>([
        widget.client.fetchApprovals(),
        widget.client.fetchKillSwitch(),
        widget.client.fetchAuditLogs(),
      ]);
      if (!mounted) return;
      final approvals = riskResponses[0] as List<ApprovalRequest>;
      setState(() {
        _approvals = approvals;
        _killSwitch = riskResponses[1] as KillSwitchState;
        _auditLogs = riskResponses[2] as List<AuditLogEntry>;
        _approvalMessage = approvals.isEmpty
            ? '当前没有待处理审批。'
            : '当前有 ${approvals.length} 个待处理审批。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _approvals = const [];
        _killSwitch = null;
        _auditLogs = const [];
        _approvalMessage = error is DubheApiException
            ? error.message
            : '风控中心同步失败。';
      });
    } finally {
      if (mounted && markBusy) {
        setState(() {
          _riskBusy = false;
        });
      }
    }
  }

  void _useSyncedStrategyDraft(StrategyDraft draft) {
    final syncedBacktest = latestSyncedBacktest(
      strategyDraft: draft,
      backtestResults: _workspaceSnapshot?.backtestResults ?? const [],
    );
    setState(() {
      _strategyDraft = draft;
      _backtestResult = syncedBacktest;
      _paperOrder = null;
      _tabIndex = 2;
      _message = '已载入同步策略：${draft.name}。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _TodayPage(
        session: widget.session,
        systemStatus: _systemStatus,
        workspaceSnapshot: _workspaceSnapshot,
        syncStatus: _syncStatus,
        lastPushedSyncEvent: _lastPushedSyncEvent,
        newsFeed: _newsFeed,
        portfolio: _portfolio,
        message: _message,
        loading: _loading,
        onUseStrategyDraft: _useSyncedStrategyDraft,
      ),
      _NewsPage(newsFeed: _newsFeed),
      _AiPage(
        newsFeed: _newsFeed,
        analysis: _analysis,
        strategyDraft: _strategyDraft,
        backtestResult: _backtestResult,
        paperOrder: _paperOrder,
        assistantMessages: _assistantMessages,
        assistantQuestion: _assistantQuestion,
        assistantBusy: _assistantBusy,
        analyzing: _analyzing,
        busy: _loading,
        onAnalyze: _analyzeTopNews,
        onDraftStrategy: _draftStrategy,
        onRunBacktest: _runBacktest,
        onSubmitPaperBuy: _submitPaperBuy,
        onAskAssistant: _askAssistant,
        onAssistantQuestionChanged: (value) {
          setState(() {
            _assistantQuestion = value;
          });
        },
        onSetAssistantPrompt: _setAssistantPrompt,
      ),
      _PortfolioPage(portfolio: _portfolio),
      _ApprovalPage(
        approvals: _approvals,
        killSwitch: _killSwitch,
        auditLogs: _auditLogs,
        message: _approvalMessage,
        canManageRisk: widget.session.canReviewApprovals,
        riskBusy: _riskBusy,
        onToggleKillSwitch: _toggleKillSwitch,
        onCreateLiveApprovalDemo: _createLiveApprovalDemo,
        onDecide: _decideApproval,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dubhe Companion'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _refresh, child: pages[_tabIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), label: '今日'),
          NavigationDestination(icon: Icon(Icons.radar_outlined), label: '雷达'),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: '组合',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            label: '审批',
          ),
        ],
      ),
    );
  }
}

class _TodayPage extends StatelessWidget {
  const _TodayPage({
    required this.session,
    required this.systemStatus,
    required this.workspaceSnapshot,
    required this.syncStatus,
    required this.lastPushedSyncEvent,
    required this.newsFeed,
    required this.portfolio,
    required this.message,
    required this.loading,
    required this.onUseStrategyDraft,
  });

  final DeviceSession session;
  final SystemStatus? systemStatus;
  final WorkspaceSnapshot? workspaceSnapshot;
  final _MobileSyncConnectionStatus syncStatus;
  final SyncEvent? lastPushedSyncEvent;
  final NewsFeed? newsFeed;
  final PaperPortfolio? portfolio;
  final String? message;
  final bool loading;
  final ValueChanged<StrategyDraft> onUseStrategyDraft;

  @override
  Widget build(BuildContext context) {
    final usdEquity = portfolio?.equityByCurrency['USD'] ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (loading) const LinearProgressIndicator(),
        if (message != null) _InfoCard(text: message!, tone: _InfoTone.danger),
        _SectionCard(
          title: '账户状态',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.roleZh,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('设备：${session.deviceName}'),
              Text('工作区：${session.workspaceId}'),
            ],
          ),
        ),
        _MetricGrid(
          metrics: [
            _Metric('新闻', '${newsFeed?.events.length ?? 0} 条'),
            _Metric('USD 权益', _money('USD', usdEquity)),
            _Metric('待审批', session.canReviewApprovals ? '可查看' : '无权限'),
            _Metric(
              '同步',
              workspaceSnapshot == null
                  ? _syncConnectionStatusZh(syncStatus)
                  : '#${workspaceSnapshot!.serverSequence}',
            ),
            _Metric('策略', '${workspaceSnapshot?.strategyDrafts.length ?? 0} 个'),
            _Metric(
              '数据源',
              systemStatus == null
                  ? '--'
                  : '${systemStatus!.enabledAdapterCount}/${systemStatus!.newsAdapters.length}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SyncStatusPanel(
          snapshot: workspaceSnapshot,
          syncStatus: syncStatus,
          lastPushedEvent: lastPushedSyncEvent,
          onUseStrategyDraft: onUseStrategyDraft,
        ),
        _SystemStatusPanel(status: systemStatus),
        _ProviderStatusList(statuses: newsFeed?.providerStatus ?? const []),
      ],
    );
  }
}

class _SyncStatusPanel extends StatelessWidget {
  const _SyncStatusPanel({
    required this.snapshot,
    required this.syncStatus,
    required this.lastPushedEvent,
    required this.onUseStrategyDraft,
  });

  final WorkspaceSnapshot? snapshot;
  final _MobileSyncConnectionStatus syncStatus;
  final SyncEvent? lastPushedEvent;
  final ValueChanged<StrategyDraft> onUseStrategyDraft;

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    if (current == null) {
      return _InfoCard(text: '同步状态：${_syncConnectionStatusZh(syncStatus)}。');
    }

    final recentEvents = current.events.take(3).toList();
    return _SectionCard(
      title: '同步状态',
      trailing: '序号 ${current.serverSequence}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(current.workspaceName),
          const SizedBox(height: 12),
          _MetricGrid(
            metrics: [
              _Metric('自选股', '${current.watchlist.length} 个'),
              _Metric('策略草案', '${current.strategyDrafts.length} 个'),
              _Metric('回测', '${current.backtestResults.length} 个'),
              _Metric('同步事件', '${current.events.length} 条'),
              _Metric('实时连接', _syncConnectionStatusZh(syncStatus)),
              _Metric('工作区', current.workspaceId),
              _Metric(
                '最新事件',
                recentEvents.isEmpty
                    ? '暂无'
                    : _syncEventActionZh(recentEvents.first.action),
              ),
            ],
          ),
          if (lastPushedEvent != null) ...[
            const SizedBox(height: 12),
            _InfoCard(
              text:
                  '最近推送：#${lastPushedEvent!.sequence} ${_syncEntityZh(lastPushedEvent!.entityType)} ${_syncEventActionZh(lastPushedEvent!.action)}。',
              tone: _InfoTone.success,
            ),
          ],
          if (current.backtestResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoCard(
              text:
                  '最新回测：${current.backtestResults.first.symbol}，收益 ${_percent(current.backtestResults.first.totalReturn)}，最大回撤 ${_percent(current.backtestResults.first.maxDrawdown)}。',
              tone: _InfoTone.success,
            ),
          ],
          if (current.strategyDrafts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(current.strategyDrafts.first.name),
              subtitle: Text(
                '版本 ${current.strategyDrafts.first.strategyVersionId}',
              ),
              trailing: Text(
                _shortTimestamp(current.strategyDrafts.first.createdAt),
              ),
              onTap: () => onUseStrategyDraft(current.strategyDrafts.first),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    onUseStrategyDraft(current.strategyDrafts.first),
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('使用同步策略'),
              ),
            ),
          ],
          if (recentEvents.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...recentEvents.map(
              (event) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${_syncEntityZh(event.entityType)} ${_syncEventActionZh(event.action)}',
                ),
                subtitle: Text('序号 ${event.sequence}'),
                trailing: Text(_shortTimestamp(event.createdAt)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewsPage extends StatelessWidget {
  const _NewsPage({required this.newsFeed});

  final NewsFeed? newsFeed;

  @override
  Widget build(BuildContext context) {
    final events = newsFeed?.events ?? const <NewsEvent>[];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final event = events[index];
        return _SectionCard(
          title: event.sourceName,
          trailing: event.tickers.join(' / '),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(event.eventType)),
                  Chip(
                    label: Text('权威度 ${(event.authorityScore * 100).round()}'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: events.length,
    );
  }
}

class _AiPage extends StatelessWidget {
  const _AiPage({
    required this.newsFeed,
    required this.analysis,
    required this.strategyDraft,
    required this.backtestResult,
    required this.paperOrder,
    required this.assistantMessages,
    required this.assistantQuestion,
    required this.assistantBusy,
    required this.analyzing,
    required this.busy,
    required this.onAnalyze,
    required this.onDraftStrategy,
    required this.onRunBacktest,
    required this.onSubmitPaperBuy,
    required this.onAskAssistant,
    required this.onAssistantQuestionChanged,
    required this.onSetAssistantPrompt,
  });

  final NewsFeed? newsFeed;
  final NewsAnalysis? analysis;
  final StrategyDraft? strategyDraft;
  final BacktestResult? backtestResult;
  final PaperOrder? paperOrder;
  final List<_AssistantChatMessage> assistantMessages;
  final String assistantQuestion;
  final bool assistantBusy;
  final bool analyzing;
  final bool busy;
  final VoidCallback onAnalyze;
  final VoidCallback onDraftStrategy;
  final VoidCallback onRunBacktest;
  final VoidCallback onSubmitPaperBuy;
  final VoidCallback onAskAssistant;
  final ValueChanged<String> onAssistantQuestionChanged;
  final ValueChanged<String> onSetAssistantPrompt;

  @override
  Widget build(BuildContext context) {
    final events = newsFeed?.events ?? const <NewsEvent>[];
    final event = events.isEmpty ? null : events.first;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'AI 分析上下文',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event?.title ?? '暂无新闻'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: event == null || analyzing ? null : onAnalyze,
                icon: const Icon(Icons.auto_awesome),
                label: Text(analyzing ? '正在分析...' : '生成中文影响分析'),
              ),
            ],
          ),
        ),
        _SectionCard(
          title: 'AI 分析师对话',
          child: _AssistantChatPanel(
            messages: assistantMessages,
            question: assistantQuestion,
            busy: assistantBusy,
            onQuestionChanged: onAssistantQuestionChanged,
            onSend: onAskAssistant,
            onSetPrompt: onSetAssistantPrompt,
          ),
        ),
        if (analysis != null)
          _SectionCard(
            title: '分析结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(analysis!.summaryZh),
                const SizedBox(height: 12),
                _MetricGrid(
                  metrics: [
                    _Metric('情绪', _sentimentZh(analysis!.sentiment)),
                    _Metric('影响分', '${(analysis!.impactScore * 100).round()}'),
                    _Metric('置信度', '${(analysis!.confidence * 100).round()}%'),
                    _Metric('标的', analysis!.affectedTickers.join(' / ')),
                  ],
                ),
              ],
            ),
          ),
        _SectionCard(
          title: '策略 / 回测 / 纸面交易',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WorkflowStepTile(
                title: '策略草案',
                subtitle: strategyDraft?.explanationZh ?? '把当前分析转换成可回测策略。',
                done: strategyDraft != null,
                buttonLabel: '生成策略',
                onPressed: analysis == null || busy ? null : onDraftStrategy,
              ),
              _WorkflowStepTile(
                title: '回测报告',
                subtitle: backtestResult == null
                    ? '运行 deterministic replay，先看收益、回撤和胜率。'
                    : '收益 ${_percent(backtestResult!.totalReturn)}，最大回撤 ${_percent(backtestResult!.maxDrawdown)}，胜率 ${_percent(backtestResult!.winRate)}。',
                done: backtestResult != null,
                buttonLabel: '运行回测',
                onPressed: strategyDraft == null || busy ? null : onRunBacktest,
              ),
              _WorkflowStepTile(
                title: '纸面交易',
                subtitle: paperOrder?.messageZh ?? '只进入纸面账户，不连接真实券商。',
                done: paperOrder != null,
                buttonLabel: '纸面买入 1 股',
                onPressed:
                    (!canSubmitPaperTrade(
                          analysis: analysis,
                          strategyDraft: strategyDraft,
                        ) ||
                        busy)
                    ? null
                    : onSubmitPaperBuy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssistantChatPanel extends StatefulWidget {
  const _AssistantChatPanel({
    required this.messages,
    required this.question,
    required this.busy,
    required this.onQuestionChanged,
    required this.onSend,
    required this.onSetPrompt,
  });

  final List<_AssistantChatMessage> messages;
  final String question;
  final bool busy;
  final ValueChanged<String> onQuestionChanged;
  final VoidCallback onSend;
  final ValueChanged<String> onSetPrompt;

  @override
  State<_AssistantChatPanel> createState() => _AssistantChatPanelState();
}

class _AssistantChatPanelState extends State<_AssistantChatPanel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.question);
  }

  @override
  void didUpdateWidget(_AssistantChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question != widget.question &&
        _controller.text != widget.question) {
      _controller.value = TextEditingValue(
        text: widget.question,
        selection: TextSelection.collapsed(offset: widget.question.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...widget.messages.map((message) => _AssistantBubble(message: message)),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          enabled: !widget.busy,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '向 AI 分析师提问',
            border: OutlineInputBorder(),
          ),
          onChanged: widget.onQuestionChanged,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: widget.busy
                  ? null
                  : () => widget.onSetPrompt('可以直接实盘买吗？需要哪些风控步骤？'),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('实盘风险'),
            ),
            OutlinedButton.icon(
              onPressed: widget.busy
                  ? null
                  : () => widget.onSetPrompt('请根据当前新闻、策略和回测，给我下一步纸面验证清单。'),
              icon: const Icon(Icons.checklist_outlined),
              label: const Text('验证清单'),
            ),
            FilledButton.icon(
              onPressed: widget.busy || widget.question.trim().isEmpty
                  ? null
                  : widget.onSend,
              icon: Icon(widget.busy ? Icons.hourglass_top : Icons.send),
              label: Text(widget.busy ? '分析中' : '发送'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.message});

  final _AssistantChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = message.isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final alignment = message.isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text),
            if (message.citations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.citations
                    .take(3)
                    .map(
                      (citation) => Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${citation.labelZh} · ${_shortRef(citation.ref)}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (message.suggestedActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...message.suggestedActions
                  .take(3)
                  .map(
                    (action) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right, size: 18),
                          Expanded(child: Text(action)),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowStepTile extends StatelessWidget {
  const _WorkflowStepTile({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final bool done;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 4),
            child: Text(subtitle),
          ),
        ],
      ),
    );
  }
}

class _PortfolioPage extends StatelessWidget {
  const _PortfolioPage({required this.portfolio});

  final PaperPortfolio? portfolio;

  @override
  Widget build(BuildContext context) {
    final current = portfolio;
    if (current == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [_InfoCard(text: '纸面组合尚未同步。')],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: '权益',
          child: _MetricGrid(
            metrics: current.equityByCurrency.entries
                .map(
                  (entry) => _Metric(entry.key, _money(entry.key, entry.value)),
                )
                .toList(),
          ),
        ),
        _SectionCard(
          title: '现金',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: current.cashByCurrency.entries
                .map(
                  (entry) =>
                      Text('${entry.key}：${_money(entry.key, entry.value)}'),
                )
                .toList(),
          ),
        ),
        _SectionCard(
          title: '持仓',
          child: current.positions.isEmpty
              ? const Text('暂无持仓。')
              : Column(
                  children: current.positions
                      .map(
                        (position) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${position.symbol} ${position.quantity.g} 股',
                          ),
                          subtitle: Text(
                            '均价 ${_money(position.currency, position.avgCost)}',
                          ),
                          trailing: Text(
                            _money(position.currency, position.marketValue),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _ApprovalPage extends StatelessWidget {
  const _ApprovalPage({
    required this.approvals,
    required this.killSwitch,
    required this.auditLogs,
    required this.message,
    required this.canManageRisk,
    required this.riskBusy,
    required this.onToggleKillSwitch,
    required this.onCreateLiveApprovalDemo,
    required this.onDecide,
  });

  final List<ApprovalRequest> approvals;
  final KillSwitchState? killSwitch;
  final List<AuditLogEntry> auditLogs;
  final String? message;
  final bool canManageRisk;
  final bool riskBusy;
  final Future<void> Function(bool enabled) onToggleKillSwitch;
  final Future<void> Function() onCreateLiveApprovalDemo;
  final Future<void> Function(ApprovalRequest approval, bool approve) onDecide;

  @override
  Widget build(BuildContext context) {
    final switchEnabled = killSwitch?.enabled ?? false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (riskBusy) const LinearProgressIndicator(),
        if (message != null) _InfoCard(text: message!),
        if (canManageRisk) ...[
          _SectionCard(
            title: '急停开关',
            trailing: switchEnabled ? '已启用' : '未启用',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: switchEnabled,
                  onChanged: riskBusy
                      ? null
                      : (value) {
                          onToggleKillSwitch(value);
                        },
                  title: Text(switchEnabled ? '阻止新订单' : '允许新订单'),
                  subtitle: Text(killSwitch?.reasonZh ?? '状态尚未同步。'),
                ),
                if (killSwitch?.updatedAt.isNotEmpty == true)
                  Text('更新：${killSwitch!.updatedAt}'),
              ],
            ),
          ),
          _SectionCard(
            title: '实盘审批演示',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('只创建审批请求，不连接真实券商或发送真实订单。'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: riskBusy
                      ? null
                      : () {
                          onCreateLiveApprovalDemo();
                        },
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('生成实盘审批演示'),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: '待处理审批',
            child: approvals.isEmpty
                ? const Text('当前没有待处理审批。')
                : Column(
                    children: approvals
                        .map(
                          (approval) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _approvalStatusZh(approval.status),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                    ),
                                    Text(
                                      approval.notional.toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(approval.messageZh),
                                const SizedBox(height: 6),
                                for (final reason in approval.reasonsZh)
                                  Text('• $reason'),
                                if (approval.isPending) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: riskBusy
                                              ? null
                                              : () {
                                                  onDecide(approval, false);
                                                },
                                          child: const Text('拒绝'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: riskBusy
                                              ? null
                                              : () {
                                                  onDecide(approval, true);
                                                },
                                          child: const Text('通过'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          _SectionCard(
            title: '最近审计',
            trailing: '${auditLogs.length} 条',
            child: auditLogs.isEmpty
                ? const Text('暂无审计记录。')
                : Column(
                    children: auditLogs
                        .take(5)
                        .map(
                          (entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_auditActionZh(entry.action)),
                            subtitle: Text(entry.summaryZh),
                            trailing: Text(_shortTimestamp(entry.createdAt)),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ] else if (message == null)
          const _InfoCard(text: '当前账号没有审批权限。'),
      ],
    );
  }
}

String _approvalStatusZh(String status) {
  if (status == 'approved') return '已通过';
  if (status == 'rejected') return '已拒绝';
  return '待审批';
}

String _riskStatusZh(String status) {
  if (status == 'approved') return '已通过';
  if (status == 'rejected') return '已拒绝';
  return '需要审批';
}

String _auditActionZh(String action) {
  const labels = {
    'admin.user_role_updated': '角色更新',
    'approval.approved': '审批通过',
    'approval.rejected': '审批拒绝',
    'auth.account_claimed': '账号认领',
    'auth.account_registered': '账号注册',
    'auth.device_registered': '设备注册',
    'auth.device_revoked': '设备撤销',
    'auth.login_succeeded': '登录成功',
    'assistant.chat_requested': 'AI 分析师对话',
    'risk.kill_switch_updated': '急停更新',
    'risk.order_evaluated': '订单风控评估',
    'simulation.paper_order_submitted': '纸面订单',
  };
  return labels[action] ?? action;
}

String _shortTimestamp(String value) {
  if (value.length >= 16) {
    return value.substring(11, 16);
  }
  return value;
}

String _shortRef(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 36) return trimmed;
  return '${trimmed.substring(0, 18)}...${trimmed.substring(trimmed.length - 12)}';
}

String _syncEntityZh(String entityType) {
  const labels = {
    'workspace': '工作区',
    'watchlist_item': '自选股',
    'news_event': '新闻',
    'news_analysis': 'AI 分析',
    'assistant_turn': 'AI 分析师对话',
    'strategy_draft': '策略草案',
    'backtest_result': '回测',
    'risk_decision': '风控决定',
    'approval_request': '审批',
    'kill_switch': '急停开关',
    'paper_order': '纸面订单',
    'broker_order': '模拟券商订单',
    'paper_portfolio': '纸面组合',
  };
  return labels[entityType] ?? entityType;
}

String _syncEventActionZh(String action) {
  if (action == 'created') return '已创建';
  if (action == 'updated') return '已更新';
  if (action == 'deleted') return '已删除';
  return action;
}

String _syncConnectionStatusZh(_MobileSyncConnectionStatus status) {
  return switch (status) {
    _MobileSyncConnectionStatus.disconnected => '未连接',
    _MobileSyncConnectionStatus.connecting => '连接中',
    _MobileSyncConnectionStatus.live => '实时同步',
    _MobileSyncConnectionStatus.polling => '轮询同步',
    _MobileSyncConnectionStatus.reconnecting => '重连中',
    _MobileSyncConnectionStatus.offline => '离线',
  };
}

bool _syncEventTouchesPortfolio(SyncEvent event) {
  return event.entityType == 'paper_order' ||
      event.entityType == 'broker_order' ||
      event.entityType == 'paper_portfolio';
}

bool _syncEventTouchesRiskCenter(SyncEvent event) {
  return event.entityType == 'approval_request' ||
      event.entityType == 'risk_decision' ||
      event.entityType == 'kill_switch';
}

@visibleForTesting
BacktestResult? latestSyncedBacktest({
  required StrategyDraft? strategyDraft,
  required List<BacktestResult> backtestResults,
}) {
  if (backtestResults.isEmpty) return null;
  final strategyVersionId = strategyDraft?.strategyVersionId.trim();
  if (strategyVersionId != null && strategyVersionId.isNotEmpty) {
    for (final result in backtestResults) {
      if (result.strategyVersionId == strategyVersionId) return result;
    }
    return null;
  }
  return backtestResults.first;
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'D',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dubhe',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              Text('AI 投资研究与风控 companion'),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.label,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) Text(trailing!),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

enum _InfoTone { normal, success, danger }

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text, this.tone = _InfoTone.normal});

  final String text;
  final _InfoTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      _InfoTone.danger => scheme.errorContainer,
      _InfoTone.success => scheme.primaryContainer,
      _InfoTone.normal => scheme.secondaryContainer,
    };
    return Card(
      color: color,
      child: Padding(padding: const EdgeInsets.all(14), child: Text(text)),
    );
  }
}

class _ProviderStatusList extends StatelessWidget {
  const _ProviderStatusList({required this.statuses});

  final List<ProviderStatus> statuses;

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: '新闻源',
      child: Column(
        children: statuses
            .map(
              (status) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(status.provider),
                subtitle: Text(status.messageZh),
                trailing: Text(status.status),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SystemStatusPanel extends StatelessWidget {
  const _SystemStatusPanel({required this.status});

  final SystemStatus? status;

  @override
  Widget build(BuildContext context) {
    final current = status;
    if (current == null) {
      return const _InfoCard(text: '系统状态尚未同步。');
    }

    return _SectionCard(
      title: '系统状态',
      trailing: 'Core v${current.version}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricGrid(
            metrics: [
              _Metric('纸面交易', current.paperBrokerEnabled ? '可用' : '关闭'),
              _Metric('实盘交易', current.liveTradingEnabled ? '开启' : '关闭'),
              _Metric('待配置', '${current.missingConfigCount} 项'),
              _Metric(
                '新闻适配器',
                '${current.enabledAdapterCount}/${current.newsAdapters.length}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(current.tradingMessageZh),
          const SizedBox(height: 8),
          Text(current.storageMessageZh),
          if (current.storagePath.isNotEmpty)
            Text('存储路径：${current.storagePath}'),
          const Divider(height: 24),
          Text('配置项', style: Theme.of(context).textTheme.titleSmall),
          ...current.configItems.map(
            (item) => _ReadinessTile(
              label: item.labelZh,
              value: item.configured ? '已配置' : '未配置',
              ok: item.configured,
              message: item.messageZh,
            ),
          ),
          const SizedBox(height: 8),
          Text('新闻适配器', style: Theme.of(context).textTheme.titleSmall),
          ...current.newsAdapters.map(
            (adapter) => _ReadinessTile(
              label: adapter.labelZh,
              value: adapter.enabled ? '可用' : '跳过',
              ok: adapter.enabled,
              message: adapter.messageZh,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadinessTile extends StatelessWidget {
  const _ReadinessTile({
    required this.label,
    required this.value,
    required this.ok,
    required this.message,
  });

  final String label;
  final String value;
  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
        color: ok ? scheme.primary : scheme.tertiary,
      ),
      title: Text(label),
      subtitle: Text(message),
      trailing: Text(value),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 480 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.35,
          physics: const NeverScrollableScrollPhysics(),
          children: metrics
              .map(
                (metric) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Text(
                          metric.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

String _money(String currency, double value) {
  return '$currency ${value.toStringAsFixed(2)}';
}

String _percent(double value) {
  return '${(value * 100).toStringAsFixed(2)}%';
}

String _sentimentZh(String sentiment) {
  if (sentiment == 'positive') return '正面';
  if (sentiment == 'negative') return '负面';
  return '中性';
}

String _primarySymbol(NewsEvent event) {
  if (event.tickers.isNotEmpty) return event.tickers.first;
  return 'NVDA';
}

String _primaryMarket(NewsEvent event) {
  if (event.marketScope.isNotEmpty) return event.marketScope.first;
  final symbol = _primarySymbol(event);
  if (symbol.endsWith('.HK')) return 'HK';
  if (symbol.endsWith('.SH') || symbol.endsWith('.SZ')) return 'A_SHARE';
  return 'US';
}

@visibleForTesting
bool canSubmitPaperTrade({
  required NewsAnalysis? analysis,
  required StrategyDraft? strategyDraft,
}) {
  return analysis != null || strategyDraft != null;
}

@visibleForTesting
String paperTradeSourceRef({
  required NewsAnalysis? analysis,
  required StrategyDraft? strategyDraft,
  required NewsEvent? event,
}) {
  final candidates = [
    analysis?.id,
    strategyDraft?.sourceAnalysisId,
    strategyDraft?.id,
    strategyDraft?.strategyVersionId,
    event?.id,
  ];
  for (final value in candidates) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) return normalized;
  }
  return 'mobile_paper_trade';
}

@visibleForTesting
String paperTradeSymbol({
  required StrategyDraft? strategyDraft,
  required NewsEvent? event,
}) {
  final assets = strategyDraft?.spec.assetUniverse ?? const <String>[];
  for (final asset in assets) {
    final normalized = asset.trim().toUpperCase();
    if (normalized.isNotEmpty) return normalized;
  }
  if (event != null) return _primarySymbol(event).trim().toUpperCase();
  return 'NVDA';
}

@visibleForTesting
String paperTradeMarket({
  required StrategyDraft? strategyDraft,
  required NewsEvent? event,
  required String symbol,
}) {
  final markets = strategyDraft?.spec.marketScope ?? const <String>[];
  for (final market in markets) {
    final normalized = market.trim().toUpperCase();
    if (normalized.isNotEmpty && normalized != 'GLOBAL') return normalized;
  }
  if (event != null) {
    final eventMarket = _primaryMarket(event).trim().toUpperCase();
    if (eventMarket.isNotEmpty && eventMarket != 'GLOBAL') return eventMarket;
  }
  final normalizedSymbol = symbol.trim().toUpperCase();
  if (normalizedSymbol.endsWith('.HK')) return 'HK';
  if (normalizedSymbol.endsWith('.SH') || normalizedSymbol.endsWith('.SZ')) {
    return 'A_SHARE';
  }
  return 'US';
}

String _currencyForMarket(String market) {
  if (market == 'HK') return 'HKD';
  if (market == 'A_SHARE') return 'CNY';
  return 'USD';
}

double _estimatedPrice(String symbol) {
  final normalized = symbol.toUpperCase();
  if (normalized == 'NVDA') return 120;
  if (normalized == 'AAPL') return 210;
  if (normalized.endsWith('.HK')) return 380;
  if (normalized.endsWith('.SH') || normalized.endsWith('.SZ')) return 1600;
  return 100;
}

String _mobilePlatform() {
  if (defaultTargetPlatform == TargetPlatform.android) return 'android';
  return 'ios';
}

extension _CompactDouble on double {
  String get g {
    if (roundToDouble() == this) return toStringAsFixed(0);
    return toStringAsFixed(4);
  }
}
