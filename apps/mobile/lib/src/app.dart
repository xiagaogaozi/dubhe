import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core_client.dart';

const defaultCoreUrl = String.fromEnvironment(
  'DUBHE_CORE_URL',
  defaultValue: 'http://127.0.0.1:8019',
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
  void dispose() {
    _apiController.dispose();
    _accountController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _mfaController.dispose();
    super.dispose();
  }

  Future<void> _enterWorkspace() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final client = CoreClient(baseUrl: _apiController.text.trim());
    final platform = _mobilePlatform();
    try {
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
        _error = error is DubheApiException ? error.message : '无法连接 Dubhe Core。';
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
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _enterWorkspace,
              child: Text(_busy ? '正在进入...' : _authMode == _AuthMode.login ? '登录工作台' : '创建并进入'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AuthMode { register, login }

class CompanionHome extends StatefulWidget {
  const CompanionHome({
    required this.client,
    required this.session,
    super.key,
  });

  final CoreClient client;
  final DeviceSession session;

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  int _tabIndex = 0;
  bool _loading = false;
  bool _analyzing = false;
  String? _message;
  String? _approvalMessage;
  NewsFeed? _newsFeed;
  NewsAnalysis? _analysis;
  PaperPortfolio? _portfolio;
  List<ApprovalRequest> _approvals = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    widget.client.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final newsFeed = await widget.client.fetchNewsFeed();
      final portfolio = await widget.client.fetchPaperPortfolio(defaultPaperAccountId);
      var approvals = <ApprovalRequest>[];
      String? approvalMessage;
      try {
        approvals = await widget.client.fetchApprovals();
      } on DubheApiException catch (error) {
        approvalMessage = error.statusCode == 403 ? '当前账号没有审批权限。' : error.message;
      }

      if (!mounted) return;
      setState(() {
        _newsFeed = newsFeed;
        _portfolio = portfolio;
        _approvals = approvals;
        _approvalMessage = approvalMessage;
      });
    } catch (error) {
      setState(() {
        _message = error is DubheApiException ? error.message : '同步失败，请检查 Core 地址。';
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

  Future<void> _decideApproval(ApprovalRequest approval, bool approve) async {
    try {
      await widget.client.decideApproval(
        approvalId: approval.id,
        approve: approve,
        comment: approve ? '移动端通过。' : '移动端拒绝。',
      );
      await _refresh();
    } catch (error) {
      setState(() {
        _message = error is DubheApiException ? error.message : '审批操作失败。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _TodayPage(
        session: widget.session,
        newsFeed: _newsFeed,
        portfolio: _portfolio,
        message: _message,
        loading: _loading,
      ),
      _NewsPage(newsFeed: _newsFeed),
      _AiPage(
        newsFeed: _newsFeed,
        analysis: _analysis,
        analyzing: _analyzing,
        onAnalyze: _analyzeTopNews,
      ),
      _PortfolioPage(portfolio: _portfolio),
      _ApprovalPage(
        approvals: _approvals,
        message: _approvalMessage,
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: pages[_tabIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), label: '今日'),
          NavigationDestination(icon: Icon(Icons.radar_outlined), label: '雷达'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: 'AI'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: '组合'),
          NavigationDestination(icon: Icon(Icons.verified_user_outlined), label: '审批'),
        ],
      ),
    );
  }
}

class _TodayPage extends StatelessWidget {
  const _TodayPage({
    required this.session,
    required this.newsFeed,
    required this.portfolio,
    required this.message,
    required this.loading,
  });

  final DeviceSession session;
  final NewsFeed? newsFeed;
  final PaperPortfolio? portfolio;
  final String? message;
  final bool loading;

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
              Text(session.roleZh, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('设备：${session.deviceName}'),
              Text('工作区：${session.workspaceId}'),
            ],
          ),
        ),
        _MetricGrid(metrics: [
          _Metric('新闻', '${newsFeed?.events.length ?? 0} 条'),
          _Metric('USD 权益', _money('USD', usdEquity)),
          _Metric('待审批', session.canReviewApprovals ? '可查看' : '无权限'),
          _Metric('实盘', '默认关闭'),
        ]),
        const SizedBox(height: 12),
        _ProviderStatusList(statuses: newsFeed?.providerStatus ?? const []),
      ],
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
                  Chip(label: Text('权威度 ${(event.authorityScore * 100).round()}')),
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
    required this.analyzing,
    required this.onAnalyze,
  });

  final NewsFeed? newsFeed;
  final NewsAnalysis? analysis;
  final bool analyzing;
  final VoidCallback onAnalyze;

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
        if (analysis != null)
          _SectionCard(
            title: '分析结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(analysis!.summaryZh),
                const SizedBox(height: 12),
                _MetricGrid(metrics: [
                  _Metric('情绪', _sentimentZh(analysis!.sentiment)),
                  _Metric('影响分', '${(analysis!.impactScore * 100).round()}'),
                  _Metric('置信度', '${(analysis!.confidence * 100).round()}%'),
                  _Metric('标的', analysis!.affectedTickers.join(' / ')),
                ]),
              ],
            ),
          ),
      ],
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
                .map((entry) => _Metric(entry.key, _money(entry.key, entry.value)))
                .toList(),
          ),
        ),
        _SectionCard(
          title: '现金',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: current.cashByCurrency.entries
                .map((entry) => Text('${entry.key}：${_money(entry.key, entry.value)}'))
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
                          title: Text('${position.symbol} ${position.quantity.g} 股'),
                          subtitle: Text('均价 ${_money(position.currency, position.avgCost)}'),
                          trailing: Text(_money(position.currency, position.marketValue)),
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
    required this.message,
    required this.onDecide,
  });

  final List<ApprovalRequest> approvals;
  final String? message;
  final Future<void> Function(ApprovalRequest approval, bool approve) onDecide;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (message != null) _InfoCard(text: message!),
        if (approvals.isEmpty && message == null) const _InfoCard(text: '当前没有待处理审批。'),
        ...approvals.map(
          (approval) => _SectionCard(
            title: approval.status,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(approval.messageZh),
                const SizedBox(height: 8),
                Text('名义金额：${approval.notional.toStringAsFixed(2)}'),
                for (final reason in approval.reasonsZh) Text('• $reason'),
                if (approval.isPending) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => onDecide(approval, false),
                          child: const Text('拒绝'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => onDecide(approval, true),
                          child: const Text('通过'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
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
          child: const Text('D', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dubhe', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
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
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

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
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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

enum _InfoTone { normal, danger }

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.text,
    this.tone = _InfoTone.normal,
  });

  final String text;
  final _InfoTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: tone == _InfoTone.danger ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(text),
      ),
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(metric.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        Text(
                          metric.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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

String _sentimentZh(String sentiment) {
  if (sentiment == 'positive') return '正面';
  if (sentiment == 'negative') return '负面';
  return '中性';
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
