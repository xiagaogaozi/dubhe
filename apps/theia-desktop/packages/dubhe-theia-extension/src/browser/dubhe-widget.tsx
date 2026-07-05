import React = require('@theia/core/shared/react');
import { Message } from '@theia/core/shared/@lumino/messaging';
import { injectable, postConstruct } from '@theia/core/shared/inversify';
import { ReactWidget } from '@theia/core/lib/browser/widgets/react-widget';

export const DUBHE_WIDGET_ID = 'dubhe.workbench';

const DEFAULT_CORE_URL = 'http://127.0.0.1:8000';
const PROTOTYPE_URL = 'http://127.0.0.1:5173';
const DEVICE_SESSION_STORAGE_KEY = 'dubhe.theia.deviceSession';
const CORE_URL_STORAGE_KEY = 'dubhe.theia.coreUrl';
const DEFAULT_PAPER_ACCOUNT_ID = 'demo_account';

type ApiStatus = '未连接' | '请求中' | '已连接' | '离线';
type AuthMode = 'register' | 'login';
type DevicePlatform = 'windows' | 'macos' | 'ios' | 'android';
type Market = 'A_SHARE' | 'HK' | 'US' | 'GLOBAL';
type Sentiment = 'positive' | 'neutral' | 'negative';
type Tone = 'positive' | 'negative' | 'neutral' | 'warning';
type UserRole = 'user' | 'risk_manager' | 'admin';

type AuthForm = {
  account_key: string;
  account_name: string;
  password: string;
  mfa_code: string;
};

type DeviceSession = {
  user_id: string;
  device_id: string;
  workspace_id: string;
  access_token: string;
  role: UserRole;
  platform: DevicePlatform;
  device_name: string;
  created_at: string;
};

type NewsEvent = {
  id: string;
  provider: string;
  provider_event_id?: string | null;
  source_name: string;
  market_scope: Market[];
  language: string;
  title_original: string;
  title_zh?: string | null;
  published_at: string;
  received_at?: string;
  url?: string | null;
  tickers: string[];
  entities: string[];
  event_type: string;
  authority_score: number;
  duplicate_group_id?: string | null;
  license_flags: string[];
};

type NewsProviderStatus = {
  provider: string;
  status: 'ok' | 'skipped' | 'unavailable';
  fetched_count: number;
  message_zh: string;
};

type NewsFeedResponse = {
  events: NewsEvent[];
  provider_status: NewsProviderStatus[];
  generated_at: string;
};

type RuntimeConfigStatus = {
  key: string;
  label_zh: string;
  configured: boolean;
  required_for: string;
  message_zh: string;
};

type NewsAdapterRuntimeStatus = {
  provider: string;
  label_zh: string;
  market_coverage: Market[];
  configured: boolean;
  enabled: boolean;
  requires_license: boolean;
  message_zh: string;
};

type StorageRuntimeStatus = {
  backend: 'sqlite';
  path: string;
  persistent: boolean;
  message_zh: string;
};

type AuthRuntimeStatus = {
  mode: 'local_dev';
  mfa_mode: 'local_placeholder';
  message_zh: string;
};

type TradingRuntimeStatus = {
  paper_broker_enabled: boolean;
  live_trading_enabled: boolean;
  message_zh: string;
};

type SystemStatusResponse = {
  service: string;
  version: string;
  language: string;
  storage: StorageRuntimeStatus;
  auth: AuthRuntimeStatus;
  config_items: RuntimeConfigStatus[];
  news_adapters: NewsAdapterRuntimeStatus[];
  trading: TradingRuntimeStatus;
  generated_at: string;
};

type NewsAnalysis = {
  id: string;
  news_event_id: string;
  summary_zh: string;
  sentiment: Sentiment;
  impact_score: number;
  affected_tickers: string[];
  source_refs: string[];
  confidence: number;
  generated_at: string;
};

type StrategySpec = {
  strategy_name: string;
  market_scope: Market[];
  asset_universe: string[];
  entry_rules: string[];
  exit_rules: string[];
  risk_limits: Record<string, number>;
  timeframe: string;
  rebalance_rule: string;
  data_dependencies: string[];
  broker_permissions: string[];
};

type StrategyDraft = {
  id: string;
  strategy_version_id: string;
  name: string;
  spec: StrategySpec;
  explanation_zh: string;
  generated_code: string;
  source_analysis_id: string;
  created_at: string;
};

type BacktestResult = {
  id: string;
  strategy_version_id: string;
  replay_scenario: string;
  symbol: string;
  market: Market;
  initial_cash: number;
  final_equity: number;
  total_return: number;
  benchmark_return: number;
  max_drawdown: number;
  win_rate: number;
  trade_count: number;
  risk_notes_zh: string[];
  generated_at: string;
};

type RiskDecision = {
  id: string;
  order_intent_id: string;
  status: 'approved' | 'requires_approval' | 'rejected';
  allowed_destination: 'none' | 'paper' | 'live_after_approval';
  notional: number;
  reasons_zh: string[];
  evaluated_at: string;
};

type ApprovalRequest = {
  id: string;
  order_intent_id: string;
  risk_decision: RiskDecision;
  status: 'pending' | 'approved' | 'rejected';
  requested_by: 'ai' | 'strategy' | 'user';
  decided_by?: string | null;
  decision_comment_zh?: string | null;
  created_at: string;
  decided_at?: string | null;
  message_zh: string;
};

type KillSwitchState = {
  enabled: boolean;
  reason_zh: string;
  updated_by: string;
  updated_at: string;
};

type PaperOrder = {
  id: string;
  order_intent_id: string;
  status: 'accepted' | 'blocked';
  risk_decision: RiskDecision;
  message_zh: string;
  submitted_at: string;
};

type PaperPortfolioPosition = {
  market: Market;
  symbol: string;
  currency: string;
  quantity: number;
  avg_cost: number;
  last_price: number;
  market_value: number;
  unrealized_pnl: number;
  updated_at: string;
};

type PaperPortfolioSnapshot = {
  account_id: string;
  cash_by_currency: Record<string, number>;
  equity_by_currency: Record<string, number>;
  realized_pnl_by_currency: Record<string, number>;
  positions: PaperPortfolioPosition[];
  updated_at: string;
};

type LogEntry = {
  id: string;
  time: string;
  tone: Tone;
  text: string;
};

const marketOptions: Array<{ value: Market; label: string }> = [
  { value: 'US', label: '美股' },
  { value: 'HK', label: '港股' },
  { value: 'A_SHARE', label: 'A 股' },
  { value: 'GLOBAL', label: '全球' },
];

const navItems = [
  { label: '今日市场', glyph: '今' },
  { label: '新闻雷达', glyph: '新', active: true },
  { label: 'AI 分析师', glyph: '智' },
  { label: '策略工坊', glyph: '策' },
  { label: '回测中心', glyph: '回' },
  { label: '纸面交易', glyph: '纸' },
  { label: '风控中心', glyph: '控' },
];

const fallbackWatchlist = [
  { symbol: 'NVDA', name: '英伟达', market: '美股', move: '+2.8%', tone: 'positive' as Tone },
  { symbol: '0700.HK', name: '腾讯控股', market: '港股', move: '-0.4%', tone: 'negative' as Tone },
  { symbol: '600519.SH', name: '贵州茅台', market: 'A 股', move: '+0.6%', tone: 'positive' as Tone },
  { symbol: 'AAPL', name: '苹果', market: '美股', move: '+1.1%', tone: 'positive' as Tone },
];

const fallbackNewsEvent: NewsEvent = {
  id: 'news_local_demo',
  provider: 'fixture',
  provider_event_id: 'theia-news-001',
  source_name: '本地演示新闻源',
  market_scope: ['US'],
  language: 'zh-CN',
  title_original: '英伟达业绩超预期并宣布回购',
  title_zh: '英伟达业绩超预期并宣布回购',
  published_at: new Date().toISOString(),
  url: 'https://example.com/news/theia-news-001',
  tickers: ['NVDA'],
  entities: ['英伟达'],
  event_type: 'earnings',
  authority_score: 0.75,
  license_flags: ['fixture'],
};

@injectable()
export class DubheWidget extends ReactWidget {
  @postConstruct()
  protected init(): void {
    this.id = DUBHE_WIDGET_ID;
    this.title.label = 'Dubhe';
    this.title.caption = 'Dubhe AI 投资研究与受控量化工作台';
    this.title.closable = false;
    this.update();
  }

  protected override onActivateRequest(message: Message): void {
    super.onActivateRequest(message);
    this.node.tabIndex = 0;
    this.node.focus();
  }

  protected render(): React.ReactNode {
    return <DubheWorkbench />;
  }
}

function DubheWorkbench(): React.ReactElement {
  const [coreUrlInput, setCoreUrlInput] = React.useState(readStoredCoreUrl);
  const [coreUrl, setCoreUrl] = React.useState(readStoredCoreUrl);
  const [session, setSession] = React.useState<DeviceSession | null>(readStoredSession);
  const [authMode, setAuthMode] = React.useState<AuthMode>('login');
  const [authForm, setAuthForm] = React.useState<AuthForm>({
    account_key: 'local-demo',
    account_name: '本地演示账户',
    password: 'Dubhe@2026',
    mfa_code: '000000',
  });
  const [apiStatus, setApiStatus] = React.useState<ApiStatus>('未连接');
  const [isBusy, setBusy] = React.useState(false);
  const [market, setMarket] = React.useState<Market>('US');
  const [symbol, setSymbol] = React.useState('NVDA');
  const [liveNews, setLiveNews] = React.useState(false);
  const [newsEvents, setNewsEvents] = React.useState<NewsEvent[]>([fallbackNewsEvent]);
  const [selectedNewsId, setSelectedNewsId] = React.useState(fallbackNewsEvent.id);
  const [providerStatus, setProviderStatus] = React.useState<NewsProviderStatus[]>([]);
  const [systemStatus, setSystemStatus] = React.useState<SystemStatusResponse | null>(null);
  const [analysis, setAnalysis] = React.useState<NewsAnalysis | null>(null);
  const [strategyDraft, setStrategyDraft] = React.useState<StrategyDraft | null>(null);
  const [backtestResult, setBacktestResult] = React.useState<BacktestResult | null>(null);
  const [paperOrder, setPaperOrder] = React.useState<PaperOrder | null>(null);
  const [portfolio, setPortfolio] = React.useState<PaperPortfolioSnapshot | null>(null);
  const [approvals, setApprovals] = React.useState<ApprovalRequest[]>([]);
  const [killSwitch, setKillSwitch] = React.useState<KillSwitchState | null>(null);
  const [riskMessage, setRiskMessage] = React.useState('登录后显示审批和急停状态。');
  const [riskBusy, setRiskBusy] = React.useState(false);
  const [logs, setLogs] = React.useState<LogEntry[]>([
    createLog('neutral', '工作台已载入。先连接 Dubhe Core，再刷新新闻源。'),
    createLog('warning', '实盘交易保持关闭：AI 不能直接下真实订单。'),
  ]);

  const selectedNews = React.useMemo(
    () => newsEvents.find((event) => event.id === selectedNewsId) ?? newsEvents[0] ?? fallbackNewsEvent,
    [newsEvents, selectedNewsId],
  );
  const selectedMarketLabel = marketOptions.find((option) => option.value === market)?.label ?? market;
  const canManageRisk = session?.role === 'admin' || session?.role === 'risk_manager';
  const enabledAdapterCount = systemStatus?.news_adapters.filter((adapter) => adapter.enabled).length ?? 0;
  const adapterStatusMeta = systemStatus ? `${enabledAdapterCount}/${systemStatus.news_adapters.length} 可用` : '待检查';
  const missingConfigCount = systemStatus?.config_items.filter((item) => !item.configured).length ?? 0;

  React.useEffect(() => {
    void checkHealth();
  }, [coreUrl]);

  React.useEffect(() => {
    if (!session) {
      setApprovals([]);
      setKillSwitch(null);
      setPortfolio(null);
      setRiskMessage('登录后显示审批和急停状态。');
      return;
    }
    void loadSessionData(session);
  }, [coreUrl, session?.access_token, session?.role]);

  function appendLog(tone: Tone, text: string): void {
    setLogs((current) => [createLog(tone, text), ...current].slice(0, 5));
  }

  function updateAuthField(field: keyof AuthForm, value: string): void {
    setAuthForm((current) => ({ ...current, [field]: value }));
  }

  function saveCoreUrl(): void {
    const nextUrl = normalizeCoreUrl(coreUrlInput);
    setCoreUrlInput(nextUrl);
    setCoreUrl(nextUrl);
    localStorage.setItem(CORE_URL_STORAGE_KEY, nextUrl);
    appendLog('neutral', `Core 地址已切换到 ${nextUrl}。`);
  }

  async function withBusy(action: () => Promise<void>): Promise<void> {
    setBusy(true);
    try {
      await action();
    } finally {
      setBusy(false);
    }
  }

  async function checkHealth(): Promise<void> {
    setApiStatus('请求中');
    try {
      const [, nextSystemStatus] = await Promise.all([
        getJson<Record<string, string>>(coreUrl, '/health'),
        getJson<SystemStatusResponse>(coreUrl, '/v1/system/status'),
      ]);
      setSystemStatus(nextSystemStatus);
      setApiStatus('已连接');
      appendLog('positive', 'Dubhe Core 健康检查和系统状态读取通过。');
    } catch (error) {
      setSystemStatus(null);
      setApiStatus('离线');
      appendLog('warning', `Core 暂不可用：${errorMessage(error)}。`);
    }
  }

  async function submitAuth(event: React.FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    await withBusy(async () => {
      const payload = {
        ...authForm,
        device_name: navigator.platform || 'Dubhe Theia Desktop',
        platform: detectPlatform(),
      };
      const nextSession = await postJson<DeviceSession>(
        coreUrl,
        authMode === 'register' ? '/v1/auth/accounts/register' : '/v1/auth/login',
        authMode === 'register'
          ? payload
          : {
              account_key: payload.account_key,
              password: payload.password,
              mfa_code: payload.mfa_code,
              device_name: payload.device_name,
              platform: payload.platform,
            },
      );
      localStorage.setItem(DEVICE_SESSION_STORAGE_KEY, JSON.stringify(nextSession));
      setSession(nextSession);
      setApiStatus('已连接');
      appendLog('positive', `已登录：${roleLabel(nextSession.role)}，工作区 ${nextSession.workspace_id}。`);
    }).catch((error: unknown) => {
      setApiStatus('离线');
      appendLog('negative', `登录失败：${errorMessage(error)}。`);
    });
  }

  async function signOut(): Promise<void> {
    await withBusy(async () => {
      if (session) {
        try {
          await postJson(coreUrl, '/v1/auth/devices/current/revoke', {}, session.access_token);
        } catch {
          // 本地退出优先，服务端撤销失败也清理本机令牌。
        }
      }
      localStorage.removeItem(DEVICE_SESSION_STORAGE_KEY);
      setSession(null);
      setPortfolio(null);
      setApprovals([]);
      setKillSwitch(null);
      setRiskMessage('登录后显示审批和急停状态。');
      appendLog('warning', '已退出当前设备。');
    });
  }

  async function refreshNewsFeed(): Promise<void> {
    await withBusy(async () => {
      setApiStatus('请求中');
      const query = new URLSearchParams({
        market,
        symbol: symbol.trim().toUpperCase(),
        limit: '8',
        live: String(liveNews),
      });
      const feed = await getJson<NewsFeedResponse>(coreUrl, `/v1/news/feed?${query.toString()}`);
      const nextEvents = feed.events.length > 0 ? feed.events : [fallbackNewsEvent];
      setNewsEvents(nextEvents);
      setSelectedNewsId(nextEvents[0].id);
      setProviderStatus(feed.provider_status);
      setAnalysis(null);
      setStrategyDraft(null);
      setBacktestResult(null);
      setPaperOrder(null);
      setApiStatus('已连接');
      appendLog('positive', `已刷新 ${nextEvents.length} 条新闻事件。`);
    }).catch((error: unknown) => {
      setApiStatus('离线');
      appendLog('negative', `刷新新闻失败：${errorMessage(error)}。`);
    });
  }

  async function analyzeSelectedNews(): Promise<void> {
    await withBusy(async () => {
      const result = await postJson<NewsAnalysis>(coreUrl, '/v1/news/analyze', selectedNews);
      setAnalysis(result);
      setApiStatus('已连接');
      appendLog('positive', `AI 分析完成：影响分 ${Math.round(result.impact_score * 100)}。`);
    }).catch((error: unknown) => {
      setApiStatus('离线');
      appendLog('negative', `新闻分析失败：${errorMessage(error)}。`);
    });
  }

  async function draftStrategy(): Promise<void> {
    if (!analysis) {
      appendLog('warning', '请先完成新闻分析，再生成策略草案。');
      return;
    }
    await withBusy(async () => {
      const draft = await postJson<StrategyDraft>(coreUrl, '/v1/strategy/drafts/from-analysis', {
        analysis,
        symbol: symbol.trim().toUpperCase(),
        market,
        max_order_notional: 10000,
      });
      setStrategyDraft(draft);
      setBacktestResult(null);
      setPaperOrder(null);
      appendLog('positive', `策略草案已生成：${draft.name}。`);
    }).catch((error: unknown) => {
      appendLog('negative', `生成策略草案失败：${errorMessage(error)}。`);
    });
  }

  async function runBacktest(): Promise<void> {
    if (!strategyDraft) {
      appendLog('warning', '请先生成策略草案，再运行回测。');
      return;
    }
    await withBusy(async () => {
      const result = await postJson<BacktestResult>(coreUrl, '/v1/backtests/replay', {
        strategy: strategyDraft,
        initial_cash: 100000,
        replay_scenario: 'golden_news_sentiment_v1',
      });
      setBacktestResult(result);
      appendLog('positive', `回测完成：策略收益 ${percentLabel(result.total_return)}。`);
    }).catch((error: unknown) => {
      appendLog('negative', `回测失败：${errorMessage(error)}。`);
    });
  }

  async function submitPaperOrder(): Promise<void> {
    if (!session) {
      appendLog('warning', '请先登录账号，再提交纸面交易。');
      return;
    }
    if (!analysis) {
      appendLog('warning', '请先完成新闻分析，纸面订单需要来源引用。');
      return;
    }
    await withBusy(async () => {
      const order = await postJson<PaperOrder>(
        coreUrl,
        '/v1/simulation/paper-orders',
        {
          account_id: DEFAULT_PAPER_ACCOUNT_ID,
          strategy_version_id: strategyDraft?.strategy_version_id ?? 'manual_theia_strategy',
          market,
          symbol: symbol.trim().toUpperCase(),
          side: 'buy',
          order_type: 'market',
          quantity: 1,
          estimated_price: estimatePrice(symbol),
          currency: market === 'HK' ? 'HKD' : market === 'A_SHARE' ? 'CNY' : 'USD',
          created_by: 'user',
          destination: 'paper',
          rationale_zh: 'Theia 工作台根据新闻分析提交纸面交易验证。',
          source_refs: [analysis.id],
        },
        session.access_token,
      );
      setPaperOrder(order);
      appendLog(order.status === 'accepted' ? 'positive' : 'warning', order.message_zh);
      await loadPortfolio(session);
    }).catch((error: unknown) => {
      appendLog('negative', `纸面交易失败：${errorMessage(error)}。`);
    });
  }

  async function loadSessionData(activeSession: DeviceSession): Promise<void> {
    try {
      await Promise.all([loadPortfolio(activeSession), loadRiskControls(activeSession)]);
    } catch (error) {
      appendLog('warning', `会话数据同步失败：${errorMessage(error)}。`);
    }
  }

  async function loadPortfolio(activeSession = session): Promise<void> {
    if (!activeSession) return;
    const snapshot = await getJson<PaperPortfolioSnapshot>(
      coreUrl,
      `/v1/simulation/paper-portfolio/${DEFAULT_PAPER_ACCOUNT_ID}`,
      activeSession.access_token,
    );
    setPortfolio(snapshot);
  }

  async function loadRiskControls(activeSession = session): Promise<void> {
    if (!activeSession) {
      setApprovals([]);
      setKillSwitch(null);
      setRiskMessage('登录后显示审批和急停状态。');
      return;
    }
    if (activeSession.role !== 'admin' && activeSession.role !== 'risk_manager') {
      setApprovals([]);
      setKillSwitch(null);
      setRiskMessage('当前账号没有审批权限。管理员或风控管理员登录后可管理审批和 kill switch。');
      return;
    }

    setRiskBusy(true);
    try {
      const [nextApprovals, nextKillSwitch] = await Promise.all([
        getJson<ApprovalRequest[]>(coreUrl, '/v1/approvals?status=pending', activeSession.access_token),
        getJson<KillSwitchState>(coreUrl, '/v1/risk/kill-switch', activeSession.access_token),
      ]);
      setApprovals(nextApprovals);
      setKillSwitch(nextKillSwitch);
      setRiskMessage(nextApprovals.length > 0 ? `当前有 ${nextApprovals.length} 个待处理审批。` : '当前没有待处理审批。');
    } catch (error) {
      setApprovals([]);
      setRiskMessage(`风控中心同步失败：${errorMessage(error)}。`);
    } finally {
      setRiskBusy(false);
    }
  }

  async function decideApproval(approval: ApprovalRequest, approve: boolean): Promise<void> {
    if (!session || !canManageRisk) {
      appendLog('warning', '当前账号没有审批权限。');
      return;
    }

    setRiskBusy(true);
    try {
      const action = approve ? 'approve' : 'reject';
      const decided = await postJson<ApprovalRequest>(
        coreUrl,
        `/v1/approvals/${approval.id}/${action}`,
        {
          decided_by: session.device_name || 'dubhe-theia',
          decision_comment_zh: approve ? '桌面端通过审批。' : '桌面端拒绝审批。',
        },
        session.access_token,
      );
      appendLog(approve ? 'positive' : 'warning', `审批请求已${approve ? '通过' : '拒绝'}：${decided.order_intent_id}。`);
      await loadRiskControls(session);
    } catch (error) {
      appendLog('negative', `审批操作失败：${errorMessage(error)}。`);
    } finally {
      setRiskBusy(false);
    }
  }

  async function toggleKillSwitch(nextEnabled: boolean): Promise<void> {
    if (!session || !canManageRisk) {
      appendLog('warning', '当前账号没有急停权限。');
      return;
    }

    setRiskBusy(true);
    try {
      const nextState = await postJson<KillSwitchState>(
        coreUrl,
        '/v1/risk/kill-switch',
        {
          enabled: nextEnabled,
          reason_zh: nextEnabled ? '桌面端手动启用 kill switch。' : '桌面端解除 kill switch。',
          updated_by: session.device_name || 'dubhe-theia',
        },
        session.access_token,
      );
      setKillSwitch(nextState);
      appendLog(nextEnabled ? 'warning' : 'positive', nextState.reason_zh);
    } catch (error) {
      appendLog('negative', `更新 kill switch 失败：${errorMessage(error)}。`);
    } finally {
      setRiskBusy(false);
    }
  }

  async function createLiveApprovalDemo(): Promise<void> {
    if (!session || !canManageRisk) {
      appendLog('warning', '请使用管理员或风控管理员账号创建审批演示。');
      return;
    }

    const nextSymbol = symbol.trim().toUpperCase();
    const sourceRef = analysis?.id ?? selectedNews.url ?? selectedNews.provider_event_id ?? selectedNews.id;
    setRiskBusy(true);
    try {
      const decision = await postJson<RiskDecision>(
        coreUrl,
        '/v1/risk/evaluate',
        {
          account_id: DEFAULT_PAPER_ACCOUNT_ID,
          strategy_version_id: strategyDraft?.strategy_version_id ?? 'manual_live_approval_demo',
          market,
          symbol: nextSymbol,
          side: 'buy',
          order_type: 'market',
          quantity: 1,
          estimated_price: estimatePrice(nextSymbol),
          currency: market === 'HK' ? 'HKD' : market === 'A_SHARE' ? 'CNY' : 'USD',
          created_by: 'ai',
          destination: 'live',
          rationale_zh: '桌面端风控中心生成的实盘审批演示；仅创建审批请求，不会连接真实券商。',
          source_refs: [sourceRef],
        },
        session.access_token,
      );
      if (decision.status === 'requires_approval') {
        appendLog('warning', `已生成实盘审批演示：${nextSymbol}，名义金额 ${notionalLabel(decision.notional)}。`);
      } else {
        appendLog(decision.status === 'approved' ? 'positive' : 'negative', `风控评估完成：${riskStatusLabel(decision.status)}。`);
      }
      await loadRiskControls(session);
    } catch (error) {
      appendLog('negative', `创建审批演示失败：${errorMessage(error)}。`);
    } finally {
      setRiskBusy(false);
    }
  }

  return (
    <main style={styles.shell}>
      <section style={styles.workbench}>
        <aside style={styles.activityRail} aria-label="主导航">
          <div style={styles.brandMark}>D</div>
          {navItems.map((item) => (
            <button
              key={item.label}
              style={{ ...styles.railButton, ...(item.active ? styles.railButtonActive : undefined) }}
              title={item.label}
              aria-label={item.label}
              type="button"
            >
              {item.glyph}
            </button>
          ))}
        </aside>

        <aside style={styles.leftSidebar}>
          <header style={styles.sidebarHeader}>
            <div>
              <strong style={styles.sidebarTitle}>Dubhe</strong>
              <p style={styles.sidebarMeta}>
                {session ? `${roleLabel(session.role)} · ${session.workspace_id}` : '未登录 · 本地工作台'}
              </p>
            </div>
            <StatusPill value={apiStatus} />
          </header>

          <PanelTitle title="Core 连接" meta={apiStatus} />
          <div style={styles.connectionBox}>
            <label style={styles.fieldLabel}>
              Core 地址
              <input
                style={styles.textInput}
                value={coreUrlInput}
                onChange={(event) => setCoreUrlInput(event.target.value)}
              />
            </label>
            <div style={styles.buttonRow}>
              <button style={styles.smallButton} type="button" onClick={saveCoreUrl} disabled={isBusy}>
                保存
              </button>
              <button style={styles.smallButton} type="button" onClick={() => void checkHealth()} disabled={isBusy}>
                检查
              </button>
            </div>
          </div>

          <PanelTitle title={session ? '当前账号' : '账号登录'} meta={session ? roleLabel(session.role) : authModeLabel(authMode)} />
          {session ? (
            <div style={styles.accountCard}>
              <p style={styles.bodyText}>设备：{session.device_name}</p>
              <p style={styles.bodyText}>平台：{session.platform}</p>
              <button style={styles.fullWidthButton} type="button" onClick={() => void signOut()} disabled={isBusy}>
                退出当前设备
              </button>
            </div>
          ) : (
            <form style={styles.authForm} onSubmit={(event) => void submitAuth(event)}>
              <div style={styles.segmented}>
                <button
                  type="button"
                  style={{ ...styles.segmentButton, ...(authMode === 'login' ? styles.segmentButtonActive : undefined) }}
                  onClick={() => setAuthMode('login')}
                >
                  登录
                </button>
                <button
                  type="button"
                  style={{ ...styles.segmentButton, ...(authMode === 'register' ? styles.segmentButtonActive : undefined) }}
                  onClick={() => setAuthMode('register')}
                >
                  创建
                </button>
              </div>
              <label style={styles.fieldLabel}>
                账号
                <input
                  style={styles.textInput}
                  value={authForm.account_key}
                  onChange={(event) => updateAuthField('account_key', event.target.value)}
                />
              </label>
              {authMode === 'register' && (
                <label style={styles.fieldLabel}>
                  显示名称
                  <input
                    style={styles.textInput}
                    value={authForm.account_name}
                    onChange={(event) => updateAuthField('account_name', event.target.value)}
                  />
                </label>
              )}
              <label style={styles.fieldLabel}>
                密码
                <input
                  style={styles.textInput}
                  type="password"
                  value={authForm.password}
                  onChange={(event) => updateAuthField('password', event.target.value)}
                />
              </label>
              <label style={styles.fieldLabel}>
                MFA 验证码
                <input
                  style={styles.textInput}
                  value={authForm.mfa_code}
                  onChange={(event) => updateAuthField('mfa_code', event.target.value)}
                />
              </label>
              <button style={styles.fullWidthButton} type="submit" disabled={isBusy}>
                {authMode === 'register' ? '创建并进入' : '登录工作台'}
              </button>
            </form>
          )}

          <PanelTitle title="自选列表" meta="演示" />
          <div style={styles.watchlist}>
            {fallbackWatchlist.map((item) => (
              <button
                key={item.symbol}
                type="button"
                style={{ ...styles.watchRow, ...(item.symbol === symbol ? styles.watchRowSelected : undefined) }}
                onClick={() => {
                  setSymbol(item.symbol);
                  setMarket(marketFromSymbol(item.symbol));
                }}
              >
                <span>
                  <strong style={styles.watchSymbol}>{item.symbol}</strong>
                  <small style={styles.watchMeta}>{item.name} · {item.market}</small>
                </span>
                <Move value={item.move} tone={item.tone} />
              </button>
            ))}
          </div>
        </aside>

        <section style={styles.centerWorkspace}>
          <header style={styles.topbar}>
            <div>
              <p style={styles.crumb}>新闻雷达 / AI 分析标签页</p>
              <h1 style={styles.pageTitle}>把新闻变成可验证的策略线索</h1>
            </div>
            <div style={styles.topbarActions}>
              <a style={styles.linkButton} href={PROTOTYPE_URL}>原型</a>
              <a style={styles.linkButton} href={`${coreUrl}/docs`}>Core API</a>
              <button style={styles.primaryButton} type="button" onClick={() => void refreshNewsFeed()} disabled={isBusy}>
                刷新新闻
              </button>
              <button style={styles.primaryButton} type="button" onClick={() => void analyzeSelectedNews()} disabled={isBusy}>
                分析
              </button>
              <button style={styles.primaryButton} type="button" onClick={() => void draftStrategy()} disabled={isBusy}>
                策略
              </button>
              <button style={styles.primaryButton} type="button" onClick={() => void runBacktest()} disabled={isBusy}>
                回测
              </button>
            </div>
          </header>

          <div style={styles.queryBar}>
            <label style={styles.inlineField}>
              市场
              <select style={styles.selectInput} value={market} onChange={(event) => setMarket(event.target.value as Market)}>
                {marketOptions.map((option) => (
                  <option key={option.value} value={option.value}>{option.label}</option>
                ))}
              </select>
            </label>
            <label style={styles.inlineField}>
              标的
              <input
                style={styles.symbolInput}
                value={symbol}
                onChange={(event) => setSymbol(event.target.value.toUpperCase())}
              />
            </label>
            <label style={styles.inlineToggle}>
              <input
                type="checkbox"
                checked={liveNews}
                onChange={(event) => setLiveNews(event.target.checked)}
              />
              尝试实时公共源
            </label>
            <span style={styles.queryHint}>默认使用确定性 fixture，适合本地演示和打包烟测。</span>
          </div>

          <div style={styles.tabStrip} role="tablist" aria-label="工作区标签">
            {['新闻原文', 'AI 分析', '策略草案', '回测报告', '纸面交易'].map((tab, index) => (
              <button
                key={tab}
                style={{ ...styles.tab, ...(index === 0 ? styles.tabActive : undefined) }}
                type="button"
              >
                {tab}
              </button>
            ))}
          </div>

          <article style={styles.document}>
            <div style={styles.documentTitle}>
              <span style={styles.sourceChip}>{selectedNews.source_name}</span>
              <span>{selectedMarketLabel} / {symbol.trim().toUpperCase()}</span>
            </div>
            <h2 style={styles.newsTitle}>{selectedNews.title_zh || selectedNews.title_original}</h2>
            <p style={styles.summaryText}>
              {analysis?.summary_zh ??
                '刷新新闻源后选择新闻，再点击“分析”。AI 输出会在这里变成中文摘要、情绪、影响分、关联标的和来源引用。'}
            </p>

            <section style={styles.newsFeedPanel}>
              <header style={styles.panelHeader}>
                <h3 style={styles.panelHeading}>新闻源事件</h3>
                <span style={styles.smallMeta}>{newsEvents.length} 条</span>
              </header>
              <div style={styles.newsEventList}>
                {newsEvents.map((event) => (
                  <button
                    key={event.id}
                    type="button"
                    style={{ ...styles.newsEvent, ...(event.id === selectedNews.id ? styles.newsEventSelected : undefined) }}
                    onClick={() => setSelectedNewsId(event.id)}
                  >
                    <span style={styles.newsEventSource}>{event.source_name} · {shortTime(event.published_at)}</span>
                    <strong style={styles.newsEventTitle}>{event.title_zh || event.title_original}</strong>
                    <span style={styles.newsEventScore}>权威度 {Math.round(event.authority_score * 100)}</span>
                  </button>
                ))}
              </div>
            </section>

            <div style={styles.metricGrid}>
              <Metric label="情绪" value={analysis ? sentimentLabel(analysis.sentiment) : '待分析'} tone={analysisTone(analysis)} />
              <Metric label="影响分" value={analysis ? String(Math.round(analysis.impact_score * 100)) : '--'} tone={analysisTone(analysis)} />
              <Metric label="置信度" value={analysis ? `${Math.round(analysis.confidence * 100)}%` : '--'} tone="neutral" />
              <Metric label="关联标的" value={analysis?.affected_tickers.join('、') || symbol.trim().toUpperCase()} tone="neutral" />
            </div>

            <section style={styles.workflowPanel}>
              <div>
                <h3 style={styles.panelHeading}>可执行闭环</h3>
                <p style={styles.bodyText}>当前 Theia 壳已能调用 Core 完成：新闻源刷新、中文分析、策略草案、回测和纸面订单。</p>
              </div>
              <div style={styles.workflowSteps}>
                <StepPill label="新闻" done={newsEvents.length > 0} />
                <StepPill label="AI 分析" done={Boolean(analysis)} />
                <StepPill label="策略草案" done={Boolean(strategyDraft)} />
                <StepPill label="回测" done={Boolean(backtestResult)} />
                <StepPill label="纸面交易" done={Boolean(paperOrder)} />
              </div>
            </section>

            <section style={styles.splitPanels}>
              <div style={styles.flatPanel}>
                <header style={styles.panelHeader}>
                  <h3 style={styles.panelHeading}>策略草案</h3>
                  <span style={styles.smallMeta}>{strategyDraft?.strategy_version_id ?? '待生成'}</span>
                </header>
                <p style={styles.bodyText}>
                  {strategyDraft?.explanation_zh ?? '点击“策略”后，Core 会把当前新闻分析转换成可校验的策略规格。'}
                </p>
                <div style={styles.ruleList}>
                  {(strategyDraft?.spec.entry_rules ?? ['新闻情绪过滤', '最大名义金额 10000', '仅允许纸面验证']).map((rule) => (
                    <span key={rule} style={styles.rulePill}>{rule}</span>
                  ))}
                </div>
              </div>

              <div style={styles.flatPanel}>
                <header style={styles.panelHeader}>
                  <h3 style={styles.panelHeading}>回测报告</h3>
                  <span style={styles.smallMeta}>{backtestResult?.replay_scenario ?? '待运行'}</span>
                </header>
                <div style={styles.backtestMetrics}>
                  <Metric label="策略收益" value={backtestResult ? percentLabel(backtestResult.total_return) : '--'} tone="positive" compact />
                  <Metric label="最大回撤" value={backtestResult ? percentLabel(backtestResult.max_drawdown) : '--'} tone="warning" compact />
                  <Metric label="胜率" value={backtestResult ? percentLabel(backtestResult.win_rate) : '--'} tone="neutral" compact />
                </div>
                <p style={styles.bodyText}>{backtestResult?.risk_notes_zh[0] ?? '运行回测后会展示 deterministic replay 的关键指标。'}</p>
              </div>
            </section>
          </article>
        </section>

        <aside style={styles.rightPanel}>
          <header style={styles.rightHeader}>
            <div>
              <h2 style={styles.rightTitle}>AI 分析师</h2>
              <p style={styles.sidebarMeta}>中文上下文 · Core tool calls</p>
            </div>
            <span style={styles.safePill}>只读建议</span>
          </header>

          <div style={styles.chatList}>
            <div style={styles.chatUser}>这条新闻会影响哪些股票？</div>
            <div style={styles.chatAssistant}>
              {analysis
                ? `当前关联 ${analysis.affected_tickers.join('、') || symbol}，影响分 ${Math.round(analysis.impact_score * 100)}。`
                : '请先运行新闻分析，我会给出中文摘要、影响分和来源引用。'}
            </div>
            <div style={styles.chatUser}>可以直接实盘买吗？</div>
            <div style={styles.chatAssistant}>不可以。AI 只能生成订单意图；真实订单必须经过确定性风控、审计和人工审批。</div>
          </div>

          <SidePanel title="系统状态" meta={systemStatus ? `Core v${systemStatus.version}` : '待检查'}>
            {systemStatus ? (
              <div style={styles.statusList}>
                <StatusRow
                  label="本地存储"
                  value={systemStatus.storage.persistent ? '持久化' : '临时'}
                  tone={systemStatus.storage.persistent ? 'positive' : 'warning'}
                  message={`${systemStatus.storage.message_zh} 路径：${systemStatus.storage.path}`}
                />
                <StatusRow label="认证模式" value="本地开发" tone="warning" message={systemStatus.auth.message_zh} />
                <StatusRow
                  label="交易模式"
                  value={systemStatus.trading.live_trading_enabled ? '实盘开启' : '实盘关闭'}
                  tone={systemStatus.trading.live_trading_enabled ? 'negative' : 'positive'}
                  message={systemStatus.trading.message_zh}
                />
              </div>
            ) : (
              <p style={styles.bodyText}>点击左侧“检查”后显示 Core、存储、认证和交易开关状态。</p>
            )}
          </SidePanel>

          <SidePanel title="数据源配置" meta={systemStatus ? `${missingConfigCount} 项待配置` : adapterStatusMeta}>
            {systemStatus ? (
              <div style={styles.statusList}>
                {systemStatus.config_items.map((item) => (
                  <StatusRow
                    key={item.key}
                    label={item.label_zh}
                    value={item.configured ? '已配置' : '未配置'}
                    tone={item.configured ? 'positive' : 'warning'}
                    message={item.message_zh}
                  />
                ))}
                {systemStatus.news_adapters.map((adapter) => (
                  <StatusRow
                    key={adapter.provider}
                    label={adapter.label_zh}
                    value={adapter.enabled ? '可用' : '跳过'}
                    tone={adapter.enabled ? 'positive' : 'warning'}
                    message={adapter.message_zh}
                  />
                ))}
              </div>
            ) : (
              <p style={styles.bodyText}>尚未读取 Core 配置体检。</p>
            )}
          </SidePanel>

          <SidePanel title="新闻源状态" meta={liveNews ? 'live' : 'fixture'}>
            {providerStatus.length > 0 ? (
              providerStatus.slice(0, 4).map((status) => (
                <p key={status.provider} style={styles.bodyText}>
                  {status.provider}：{status.message_zh}
                </p>
              ))
            ) : (
              <p style={styles.bodyText}>尚未刷新新闻源。</p>
            )}
          </SidePanel>

          <SidePanel title="风控中心" meta={canManageRisk ? `${approvals.length} 待审批` : '只读'}>
            <div style={styles.riskHeaderRow}>
              <p style={{ ...styles.safeStatus, ...(killSwitch?.enabled ? styles.killSwitchOnText : undefined) }}>
                {killSwitch?.enabled ? 'Kill switch 已启用' : '实盘交易关闭'}
              </p>
              <button
                style={styles.inlineTextButton}
                type="button"
                onClick={() => void loadRiskControls(session)}
                disabled={riskBusy || !session}
              >
                刷新
              </button>
            </div>
            <p style={styles.bodyText}>{riskMessage}</p>
            {canManageRisk && (
              <>
                <div style={styles.riskButtonRow}>
                  <button
                    style={styles.smallButton}
                    type="button"
                    onClick={() => void toggleKillSwitch(true)}
                    disabled={riskBusy || killSwitch?.enabled === true}
                  >
                    启用急停
                  </button>
                  <button
                    style={styles.smallButton}
                    type="button"
                    onClick={() => void toggleKillSwitch(false)}
                    disabled={riskBusy || killSwitch?.enabled === false}
                  >
                    解除急停
                  </button>
                </div>
                <button
                  style={styles.fullWidthButton}
                  type="button"
                  onClick={() => void createLiveApprovalDemo()}
                  disabled={riskBusy || !session}
                >
                  生成实盘审批演示
                </button>
                <p style={styles.statusMessage}>只创建审批请求，不会连接真实券商或发送真实订单。</p>
                {killSwitch && <p style={styles.bodyText}>原因：{killSwitch.reason_zh}</p>}
                <div style={styles.approvalList}>
                  {approvals.length === 0 ? (
                    <p style={styles.bodyText}>没有待处理审批。</p>
                  ) : (
                    approvals.slice(0, 4).map((approval) => (
                      <div style={styles.approvalRow} key={approval.id}>
                        <div style={styles.approvalTopLine}>
                          <strong style={styles.statusName}>名义金额 {notionalLabel(approval.risk_decision.notional)}</strong>
                          <span style={{ ...styles.miniPill, ...styles.warningPill }}>{approvalStatusLabel(approval.status)}</span>
                        </div>
                        <p style={styles.statusMessage}>{approval.message_zh}</p>
                        {approval.risk_decision.reasons_zh.slice(0, 2).map((reason) => (
                          <p style={styles.statusMessage} key={reason}>· {reason}</p>
                        ))}
                        <div style={styles.riskButtonRow}>
                          <button
                            style={styles.smallButton}
                            type="button"
                            onClick={() => void decideApproval(approval, false)}
                            disabled={riskBusy || approval.status !== 'pending'}
                          >
                            拒绝
                          </button>
                          <button
                            style={styles.fullWidthButtonInline}
                            type="button"
                            onClick={() => void decideApproval(approval, true)}
                            disabled={riskBusy || approval.status !== 'pending'}
                          >
                            通过
                          </button>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </>
            )}
          </SidePanel>

          <SidePanel title="纸面交易" meta={paperOrder?.status ?? '待提交'}>
            <p style={styles.bodyText}>{paperOrder?.message_zh ?? '登录并完成分析后，可提交 1 股纸面买入验证账本链路。'}</p>
            <button style={styles.fullWidthButton} type="button" onClick={() => void submitPaperOrder()} disabled={isBusy}>
              提交纸面买入
            </button>
          </SidePanel>

          <SidePanel title="纸面组合" meta={DEFAULT_PAPER_ACCOUNT_ID}>
            {portfolio ? (
              <>
                <div style={styles.portfolioMetric}>
                  <span>权益</span>
                  <strong>{formatCurrencyMap(portfolio.equity_by_currency)}</strong>
                </div>
                <div style={styles.portfolioMetric}>
                  <span>现金</span>
                  <strong>{formatCurrencyMap(portfolio.cash_by_currency)}</strong>
                </div>
                {portfolio.positions.slice(0, 4).map((position) => (
                  <div style={styles.positionRow} key={`${position.market}-${position.symbol}-${position.currency}`}>
                    <span>{position.symbol} · {position.quantity.toLocaleString('zh-CN')} 股</span>
                    <strong>{moneyLabel(position.currency, position.market_value)}</strong>
                  </div>
                ))}
              </>
            ) : (
              <p style={styles.bodyText}>登录后会读取纸面组合。</p>
            )}
          </SidePanel>
        </aside>

        <footer style={styles.bottomPanel}>
          <strong style={styles.bottomTitle}>任务日志 / 风控告警</strong>
          <div style={styles.logList}>
            {logs.map((entry) => (
              <div style={styles.logEntry} key={entry.id}>
                <span style={styles.logTime}>{entry.time}</span>
                <p style={{ ...styles.logText, ...toneTextStyle(entry.tone) }}>{entry.text}</p>
              </div>
            ))}
          </div>
        </footer>
      </section>
    </main>
  );
}

function readStoredCoreUrl(): string {
  try {
    return normalizeCoreUrl(localStorage.getItem(CORE_URL_STORAGE_KEY) || DEFAULT_CORE_URL);
  } catch {
    return DEFAULT_CORE_URL;
  }
}

function readStoredSession(): DeviceSession | null {
  try {
    const raw = localStorage.getItem(DEVICE_SESSION_STORAGE_KEY);
    return raw ? (JSON.parse(raw) as DeviceSession) : null;
  } catch {
    localStorage.removeItem(DEVICE_SESSION_STORAGE_KEY);
    return null;
  }
}

function normalizeCoreUrl(value: string): string {
  const trimmed = value.trim() || DEFAULT_CORE_URL;
  return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
}

async function getJson<T>(baseUrl: string, path: string, accessToken?: string): Promise<T> {
  return requestJson<T>(baseUrl, path, { accessToken });
}

async function postJson<T>(baseUrl: string, path: string, body: unknown, accessToken?: string): Promise<T> {
  return requestJson<T>(baseUrl, path, { method: 'POST', body, accessToken });
}

async function requestJson<T>(
  baseUrl: string,
  path: string,
  options: { method?: string; body?: unknown; accessToken?: string } = {},
): Promise<T> {
  const headers: Record<string, string> = {};
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  if (options.accessToken) {
    headers.Authorization = `Bearer ${options.accessToken}`;
  }

  const response = await fetch(`${normalizeCoreUrl(baseUrl)}${path}`, {
    method: options.method ?? 'GET',
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(readApiError(text) || `${response.status} ${response.statusText}`);
  }

  return response.json() as Promise<T>;
}

function readApiError(text: string): string {
  try {
    const parsed = JSON.parse(text) as { detail?: unknown };
    if (typeof parsed.detail === 'string') return parsed.detail;
    if (Array.isArray(parsed.detail)) return parsed.detail.map((item) => JSON.stringify(item)).join('；');
  } catch {
    // Fall through to raw response text.
  }
  return text;
}

function detectPlatform(): DevicePlatform {
  const userAgent = navigator.userAgent.toLowerCase();
  const platform = navigator.platform.toLowerCase();
  if (userAgent.includes('android')) return 'android';
  if (userAgent.includes('iphone') || userAgent.includes('ipad')) return 'ios';
  if (platform.includes('mac')) return 'macos';
  return 'windows';
}

function createLog(tone: Tone, text: string): LogEntry {
  return {
    id: `log_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    time: new Intl.DateTimeFormat('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    }).format(new Date()),
    tone,
    text,
  };
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '未知错误';
}

function marketFromSymbol(value: string): Market {
  if (value.endsWith('.HK')) return 'HK';
  if (value.endsWith('.SH') || value.endsWith('.SZ')) return 'A_SHARE';
  return 'US';
}

function roleLabel(role: UserRole): string {
  if (role === 'admin') return '管理员';
  if (role === 'risk_manager') return '风控管理员';
  return '普通用户';
}

function authModeLabel(mode: AuthMode): string {
  return mode === 'register' ? '创建账号' : '登录';
}

function approvalStatusLabel(status: ApprovalRequest['status']): string {
  if (status === 'approved') return '已通过';
  if (status === 'rejected') return '已拒绝';
  return '待审批';
}

function riskStatusLabel(status: RiskDecision['status']): string {
  if (status === 'approved') return '已通过';
  if (status === 'rejected') return '已拒绝';
  return '需要审批';
}

function sentimentLabel(sentiment: Sentiment): string {
  if (sentiment === 'positive') return '正面';
  if (sentiment === 'negative') return '负面';
  return '中性';
}

function analysisTone(analysis: NewsAnalysis | null): Tone {
  if (!analysis) return 'neutral';
  if (analysis.sentiment === 'positive') return 'positive';
  if (analysis.sentiment === 'negative') return 'negative';
  return 'neutral';
}

function estimatePrice(value: string): number {
  const symbol = value.trim().toUpperCase();
  if (symbol === 'NVDA') return 120;
  if (symbol === 'AAPL') return 210;
  if (symbol.endsWith('.HK')) return 380;
  if (symbol.endsWith('.SH') || symbol.endsWith('.SZ')) return 1600;
  return 100;
}

function percentLabel(value: number): string {
  return `${(value * 100).toFixed(2)}%`;
}

function moneyLabel(currency: string, value: number): string {
  try {
    return new Intl.NumberFormat('zh-CN', {
      currency,
      maximumFractionDigits: 2,
      style: 'currency',
    }).format(value);
  } catch {
    return `${currency} ${value.toLocaleString('zh-CN')}`;
  }
}

function notionalLabel(value: number): string {
  return value.toLocaleString('zh-CN', {
    maximumFractionDigits: 2,
  });
}

function formatCurrencyMap(values: Record<string, number>): string {
  const entries = Object.entries(values);
  if (entries.length === 0) return '--';
  return entries.map(([currency, value]) => moneyLabel(currency, value)).join(' / ');
}

function shortTime(value: string): string {
  try {
    return new Intl.DateTimeFormat('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
    }).format(new Date(value));
  } catch {
    return '--:--';
  }
}

function PanelTitle(props: { title: string; meta: string }): React.ReactElement {
  return (
    <header style={styles.panelTitleRow}>
      <h2 style={styles.sidebarSectionTitle}>{props.title}</h2>
      <span style={styles.smallMeta}>{props.meta}</span>
    </header>
  );
}

function StatusPill(props: { value: ApiStatus }): React.ReactElement {
  const tone: Tone = props.value === '已连接' ? 'positive' : props.value === '离线' ? 'negative' : 'neutral';
  return <span style={{ ...styles.onlinePill, ...tonePillStyle(tone) }}>{props.value}</span>;
}

function StatusRow(props: { label: string; value: string; tone: Tone; message: string }): React.ReactElement {
  return (
    <div style={styles.statusRow}>
      <div style={styles.statusRowHeader}>
        <strong style={styles.statusName}>{props.label}</strong>
        <span style={{ ...styles.miniPill, ...tonePillStyle(props.tone) }}>{props.value}</span>
      </div>
      <p style={styles.statusMessage}>{props.message}</p>
    </div>
  );
}

function StepPill(props: { label: string; done: boolean }): React.ReactElement {
  return <span style={{ ...styles.workflowStep, ...(props.done ? styles.workflowStepDone : undefined) }}>{props.label}</span>;
}

function Move(props: { value: string; tone: Tone }): React.ReactElement {
  return <span style={{ ...styles.move, ...toneTextStyle(props.tone) }}>{props.value}</span>;
}

function Metric(props: { label: string; value: string; tone: Tone; compact?: boolean }): React.ReactElement {
  return (
    <div style={props.compact ? styles.metricCompact : styles.metric}>
      <span style={styles.metricLabel}>{props.label}</span>
      <strong style={{ ...styles.metricValue, ...toneTextStyle(props.tone) }}>{props.value}</strong>
    </div>
  );
}

function SidePanel(props: { title: string; meta: string; children: React.ReactNode }): React.ReactElement {
  return (
    <section style={styles.sidePanel}>
      <header style={styles.panelHeader}>
        <h3 style={styles.panelHeading}>{props.title}</h3>
        <span style={styles.smallMeta}>{props.meta}</span>
      </header>
      {props.children}
    </section>
  );
}

function toneTextStyle(tone: Tone): React.CSSProperties {
  if (tone === 'positive') return styles.positiveText;
  if (tone === 'negative') return styles.negativeText;
  if (tone === 'warning') return styles.warningText;
  return styles.neutralText;
}

function tonePillStyle(tone: Tone): React.CSSProperties {
  if (tone === 'positive') return styles.positivePill;
  if (tone === 'negative') return styles.negativePill;
  if (tone === 'warning') return styles.warningPill;
  return styles.neutralPill;
}

const styles = {
  shell: {
    minHeight: '100%',
    padding: 16,
    color: '#17231f',
    background: '#eef2ef',
    boxSizing: 'border-box',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    overflow: 'auto',
  } as React.CSSProperties,
  workbench: {
    minWidth: 1240,
    minHeight: 820,
    display: 'grid',
    gridTemplateColumns: '64px 280px minmax(540px, 1fr) 340px',
    gridTemplateRows: 'minmax(0, 1fr) 120px',
    gap: 10,
  } as React.CSSProperties,
  activityRail: {
    gridRow: '1 / 3',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 10,
    padding: '12px 8px',
    borderRadius: 8,
    background: '#17231f',
  } as React.CSSProperties,
  brandMark: {
    width: 40,
    height: 40,
    display: 'grid',
    placeItems: 'center',
    borderRadius: 8,
    background: '#8bd6ba',
    color: '#0d1a16',
    fontWeight: 800,
    fontSize: 20,
  } as React.CSSProperties,
  railButton: {
    width: 40,
    height: 40,
    border: '1px solid transparent',
    borderRadius: 8,
    background: 'transparent',
    color: '#b6c9c0',
    cursor: 'pointer',
    fontWeight: 800,
  } as React.CSSProperties,
  railButtonActive: {
    background: '#f6fbf8',
    color: '#123329',
  } as React.CSSProperties,
  leftSidebar: {
    padding: 14,
    border: '1px solid #d9e0dc',
    borderRadius: 8,
    background: '#ffffff',
    overflow: 'auto',
  } as React.CSSProperties,
  sidebarHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 12,
    paddingBottom: 14,
    borderBottom: '1px solid #e6ebe8',
  } as React.CSSProperties,
  sidebarTitle: {
    display: 'block',
    fontSize: 18,
  } as React.CSSProperties,
  sidebarMeta: {
    margin: '3px 0 0',
    color: '#687a72',
    fontSize: 12,
    lineHeight: 1.45,
  } as React.CSSProperties,
  onlinePill: {
    padding: '5px 8px',
    borderRadius: 8,
    fontSize: 12,
    fontWeight: 800,
    whiteSpace: 'nowrap',
  } as React.CSSProperties,
  positivePill: {
    background: '#e4f5ec',
    color: '#14613f',
  } as React.CSSProperties,
  negativePill: {
    background: '#fff0ea',
    color: '#9b3721',
  } as React.CSSProperties,
  warningPill: {
    background: '#fff6df',
    color: '#80550f',
  } as React.CSSProperties,
  neutralPill: {
    background: '#eef4ff',
    color: '#2452a1',
  } as React.CSSProperties,
  panelTitleRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
    marginTop: 16,
  } as React.CSSProperties,
  sidebarSectionTitle: {
    margin: 0,
    fontSize: 13,
    color: '#41514b',
  } as React.CSSProperties,
  smallMeta: {
    color: '#76877f',
    fontSize: 12,
    whiteSpace: 'nowrap',
  } as React.CSSProperties,
  connectionBox: {
    display: 'grid',
    gap: 8,
    marginTop: 8,
  } as React.CSSProperties,
  authForm: {
    display: 'grid',
    gap: 8,
    marginTop: 8,
  } as React.CSSProperties,
  accountCard: {
    marginTop: 8,
    padding: 10,
    border: '1px solid #e3eae6',
    borderRadius: 8,
    background: '#fbfcfb',
  } as React.CSSProperties,
  fieldLabel: {
    display: 'grid',
    gap: 5,
    color: '#45584f',
    fontSize: 12,
    fontWeight: 700,
  } as React.CSSProperties,
  textInput: {
    width: '100%',
    boxSizing: 'border-box',
    padding: '8px 9px',
    border: '1px solid #ccd8d2',
    borderRadius: 8,
    background: '#ffffff',
    color: '#17231f',
  } as React.CSSProperties,
  buttonRow: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 8,
  } as React.CSSProperties,
  segmented: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    padding: 3,
    borderRadius: 8,
    background: '#eef3f0',
  } as React.CSSProperties,
  segmentButton: {
    padding: '7px 8px',
    border: 0,
    borderRadius: 7,
    background: 'transparent',
    color: '#4e6158',
    cursor: 'pointer',
    fontWeight: 800,
  } as React.CSSProperties,
  segmentButtonActive: {
    background: '#ffffff',
    color: '#174a3a',
  } as React.CSSProperties,
  watchlist: {
    display: 'grid',
    gap: 6,
    marginTop: 8,
  } as React.CSSProperties,
  watchRow: {
    width: '100%',
    minHeight: 54,
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 10,
    padding: '9px 10px',
    border: '1px solid #e5ebe8',
    borderRadius: 8,
    background: '#fbfcfb',
    color: '#17231f',
    textAlign: 'left',
    cursor: 'pointer',
  } as React.CSSProperties,
  watchRowSelected: {
    borderColor: '#72b595',
    background: '#f1fbf5',
  } as React.CSSProperties,
  watchSymbol: {
    display: 'block',
    fontSize: 13,
  } as React.CSSProperties,
  watchMeta: {
    display: 'block',
    marginTop: 3,
    color: '#6f8179',
    fontSize: 12,
  } as React.CSSProperties,
  move: {
    fontWeight: 800,
    fontSize: 13,
    whiteSpace: 'nowrap',
  } as React.CSSProperties,
  centerWorkspace: {
    minWidth: 0,
    display: 'grid',
    gridTemplateRows: 'auto auto auto minmax(0, 1fr)',
    border: '1px solid #d9e0dc',
    borderRadius: 8,
    background: '#ffffff',
    overflow: 'hidden',
  } as React.CSSProperties,
  topbar: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 16,
    padding: '14px 18px',
    borderBottom: '1px solid #e6ebe8',
  } as React.CSSProperties,
  crumb: {
    margin: 0,
    color: '#667971',
    fontSize: 12,
  } as React.CSSProperties,
  pageTitle: {
    margin: '4px 0 0',
    fontSize: 22,
    lineHeight: 1.2,
  } as React.CSSProperties,
  topbarActions: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 8,
    flexWrap: 'wrap',
  } as React.CSSProperties,
  linkButton: {
    padding: '8px 10px',
    border: '1px solid #cdd8d3',
    borderRadius: 8,
    color: '#174a3a',
    textDecoration: 'none',
    fontSize: 13,
    fontWeight: 800,
  } as React.CSSProperties,
  primaryButton: {
    padding: '9px 12px',
    border: 0,
    borderRadius: 8,
    background: '#174a3a',
    color: '#ffffff',
    cursor: 'pointer',
    fontSize: 13,
    fontWeight: 800,
  } as React.CSSProperties,
  queryBar: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '10px 14px',
    borderBottom: '1px solid #e6ebe8',
    background: '#fbfcfb',
    flexWrap: 'wrap',
  } as React.CSSProperties,
  inlineField: {
    display: 'flex',
    alignItems: 'center',
    gap: 7,
    color: '#4f6259',
    fontSize: 12,
    fontWeight: 800,
  } as React.CSSProperties,
  inlineToggle: {
    display: 'flex',
    alignItems: 'center',
    gap: 6,
    color: '#4f6259',
    fontSize: 12,
    fontWeight: 800,
  } as React.CSSProperties,
  selectInput: {
    padding: '7px 8px',
    border: '1px solid #ccd8d2',
    borderRadius: 8,
    background: '#ffffff',
  } as React.CSSProperties,
  symbolInput: {
    width: 110,
    padding: '7px 8px',
    border: '1px solid #ccd8d2',
    borderRadius: 8,
    background: '#ffffff',
  } as React.CSSProperties,
  queryHint: {
    color: '#7a8c84',
    fontSize: 12,
  } as React.CSSProperties,
  tabStrip: {
    display: 'flex',
    gap: 2,
    padding: '8px 14px 0',
    borderBottom: '1px solid #e6ebe8',
    background: '#f8faf9',
  } as React.CSSProperties,
  tab: {
    padding: '9px 12px',
    border: 0,
    borderRadius: '8px 8px 0 0',
    background: 'transparent',
    color: '#53675e',
    cursor: 'pointer',
    fontWeight: 700,
  } as React.CSSProperties,
  tabActive: {
    background: '#ffffff',
    color: '#17231f',
    boxShadow: 'inset 0 2px 0 #43a978',
  } as React.CSSProperties,
  document: {
    minHeight: 0,
    overflow: 'auto',
    padding: 18,
  } as React.CSSProperties,
  documentTitle: {
    display: 'flex',
    justifyContent: 'space-between',
    gap: 12,
    color: '#667971',
    fontSize: 13,
  } as React.CSSProperties,
  sourceChip: {
    color: '#174a3a',
    fontWeight: 800,
  } as React.CSSProperties,
  newsTitle: {
    margin: '10px 0 8px',
    fontSize: 26,
    lineHeight: 1.22,
  } as React.CSSProperties,
  summaryText: {
    margin: 0,
    color: '#33443d',
    fontSize: 15,
    lineHeight: 1.7,
  } as React.CSSProperties,
  newsFeedPanel: {
    marginTop: 16,
    paddingTop: 14,
    borderTop: '1px solid #e6ebe8',
  } as React.CSSProperties,
  panelHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  } as React.CSSProperties,
  panelHeading: {
    margin: 0,
    fontSize: 14,
  } as React.CSSProperties,
  newsEventList: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
    gap: 8,
    marginTop: 8,
  } as React.CSSProperties,
  newsEvent: {
    minHeight: 112,
    display: 'grid',
    alignContent: 'start',
    gap: 6,
    padding: 12,
    border: '1px solid #e2e9e5',
    borderRadius: 8,
    background: '#fbfcfb',
    color: '#17231f',
    textAlign: 'left',
    cursor: 'pointer',
  } as React.CSSProperties,
  newsEventSelected: {
    borderColor: '#70b693',
    background: '#f0fbf5',
  } as React.CSSProperties,
  newsEventSource: {
    color: '#6b7f76',
    fontSize: 12,
  } as React.CSSProperties,
  newsEventTitle: {
    fontSize: 13,
    lineHeight: 1.35,
  } as React.CSSProperties,
  newsEventScore: {
    color: '#174a3a',
    fontSize: 12,
    fontWeight: 800,
  } as React.CSSProperties,
  metricGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(4, minmax(0, 1fr))',
    gap: 8,
    marginTop: 14,
  } as React.CSSProperties,
  metric: {
    padding: 12,
    border: '1px solid #e3eae6',
    borderRadius: 8,
    background: '#fbfcfb',
  } as React.CSSProperties,
  metricCompact: {
    padding: 0,
  } as React.CSSProperties,
  metricLabel: {
    display: 'block',
    color: '#6d8178',
    fontSize: 12,
  } as React.CSSProperties,
  metricValue: {
    display: 'block',
    marginTop: 4,
    fontSize: 19,
  } as React.CSSProperties,
  workflowPanel: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 18,
    marginTop: 14,
    padding: 14,
    border: '1px solid #e0e7e3',
    borderRadius: 8,
    background: '#f8faf9',
  } as React.CSSProperties,
  bodyText: {
    margin: '8px 0 0',
    color: '#4f6259',
    fontSize: 13,
    lineHeight: 1.55,
  } as React.CSSProperties,
  workflowSteps: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 6,
    justifyContent: 'flex-end',
  } as React.CSSProperties,
  workflowStep: {
    padding: '6px 8px',
    border: '1px solid #d6e0db',
    borderRadius: 8,
    color: '#60746b',
    background: '#ffffff',
    fontSize: 12,
    fontWeight: 800,
  } as React.CSSProperties,
  workflowStepDone: {
    borderColor: '#8acbad',
    color: '#15533b',
    background: '#ecf8f1',
  } as React.CSSProperties,
  splitPanels: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)',
    gap: 10,
    marginTop: 14,
  } as React.CSSProperties,
  flatPanel: {
    padding: 14,
    border: '1px solid #e1e8e4',
    borderRadius: 8,
    background: '#ffffff',
  } as React.CSSProperties,
  ruleList: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 6,
    marginTop: 10,
  } as React.CSSProperties,
  rulePill: {
    padding: '6px 8px',
    borderRadius: 8,
    background: '#eef5f2',
    color: '#31564a',
    fontSize: 12,
    fontWeight: 700,
  } as React.CSSProperties,
  backtestMetrics: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
    gap: 10,
    marginTop: 12,
  } as React.CSSProperties,
  rightPanel: {
    minWidth: 0,
    padding: 14,
    border: '1px solid #d9e0dc',
    borderRadius: 8,
    background: '#ffffff',
    overflow: 'auto',
  } as React.CSSProperties,
  rightHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    gap: 12,
    alignItems: 'flex-start',
  } as React.CSSProperties,
  rightTitle: {
    margin: 0,
    fontSize: 18,
  } as React.CSSProperties,
  safePill: {
    padding: '5px 8px',
    borderRadius: 8,
    background: '#eef4ff',
    color: '#2452a1',
    fontSize: 12,
    fontWeight: 800,
  } as React.CSSProperties,
  chatList: {
    display: 'grid',
    gap: 8,
    marginTop: 14,
  } as React.CSSProperties,
  chatUser: {
    justifySelf: 'end',
    maxWidth: '88%',
    padding: '9px 10px',
    borderRadius: 8,
    background: '#174a3a',
    color: '#ffffff',
    fontSize: 13,
    lineHeight: 1.45,
  } as React.CSSProperties,
  chatAssistant: {
    justifySelf: 'start',
    maxWidth: '92%',
    padding: '9px 10px',
    borderRadius: 8,
    background: '#f0f4f2',
    color: '#26362f',
    fontSize: 13,
    lineHeight: 1.45,
  } as React.CSSProperties,
  sidePanel: {
    marginTop: 12,
    padding: 12,
    border: '1px solid #e1e8e4',
    borderRadius: 8,
    background: '#fbfcfb',
  } as React.CSSProperties,
  statusList: {
    display: 'grid',
    gap: 8,
    marginTop: 10,
  } as React.CSSProperties,
  statusRow: {
    padding: '8px 0',
    borderTop: '1px solid #e5ebe8',
  } as React.CSSProperties,
  statusRowHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  } as React.CSSProperties,
  statusName: {
    minWidth: 0,
    color: '#26362f',
    fontSize: 13,
    lineHeight: 1.35,
  } as React.CSSProperties,
  statusMessage: {
    margin: '5px 0 0',
    color: '#65786f',
    fontSize: 12,
    lineHeight: 1.45,
    overflowWrap: 'anywhere',
  } as React.CSSProperties,
  miniPill: {
    flex: '0 0 auto',
    padding: '4px 7px',
    borderRadius: 8,
    fontSize: 11,
    fontWeight: 800,
    whiteSpace: 'nowrap',
  } as React.CSSProperties,
  safeStatus: {
    margin: '10px 0 0',
    color: '#16623f',
    fontWeight: 800,
  } as React.CSSProperties,
  killSwitchOnText: {
    color: '#b13d2c',
  } as React.CSSProperties,
  riskHeaderRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  } as React.CSSProperties,
  inlineTextButton: {
    marginTop: 8,
    padding: 0,
    border: 0,
    background: 'transparent',
    color: '#174a3a',
    cursor: 'pointer',
    fontSize: 12,
    fontWeight: 800,
  } as React.CSSProperties,
  riskButtonRow: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 8,
    marginTop: 10,
  } as React.CSSProperties,
  approvalList: {
    display: 'grid',
    gap: 8,
    marginTop: 10,
  } as React.CSSProperties,
  approvalRow: {
    paddingTop: 10,
    borderTop: '1px solid #e5ebe8',
  } as React.CSSProperties,
  approvalTopLine: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  } as React.CSSProperties,
  portfolioMetric: {
    display: 'flex',
    justifyContent: 'space-between',
    gap: 10,
    marginTop: 10,
    color: '#30433b',
    fontSize: 13,
  } as React.CSSProperties,
  positionRow: {
    display: 'flex',
    justifyContent: 'space-between',
    gap: 10,
    marginTop: 8,
    color: '#30433b',
    fontSize: 13,
  } as React.CSSProperties,
  smallButton: {
    padding: '8px 10px',
    border: 0,
    borderRadius: 8,
    background: '#e4f5ec',
    color: '#165238',
    cursor: 'pointer',
    fontWeight: 800,
  } as React.CSSProperties,
  fullWidthButton: {
    width: '100%',
    marginTop: 8,
    padding: '9px 10px',
    border: 0,
    borderRadius: 8,
    background: '#174a3a',
    color: '#ffffff',
    cursor: 'pointer',
    fontWeight: 800,
  } as React.CSSProperties,
  fullWidthButtonInline: {
    padding: '8px 10px',
    border: 0,
    borderRadius: 8,
    background: '#174a3a',
    color: '#ffffff',
    cursor: 'pointer',
    fontWeight: 800,
  } as React.CSSProperties,
  bottomPanel: {
    gridColumn: '2 / 5',
    display: 'grid',
    gridTemplateColumns: '180px minmax(0, 1fr)',
    gap: 12,
    alignItems: 'start',
    padding: 14,
    border: '1px solid #d9e0dc',
    borderRadius: 8,
    background: '#ffffff',
    overflow: 'hidden',
  } as React.CSSProperties,
  bottomTitle: {
    fontSize: 13,
  } as React.CSSProperties,
  logList: {
    display: 'grid',
    gap: 6,
  } as React.CSSProperties,
  logEntry: {
    display: 'grid',
    gridTemplateColumns: '74px minmax(0, 1fr)',
    gap: 10,
    alignItems: 'baseline',
    fontSize: 12,
  } as React.CSSProperties,
  logTime: {
    color: '#7a8c84',
    fontVariantNumeric: 'tabular-nums',
  } as React.CSSProperties,
  logText: {
    margin: 0,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  } as React.CSSProperties,
  positiveText: {
    color: '#147548',
  } as React.CSSProperties,
  negativeText: {
    color: '#b13d2c',
  } as React.CSSProperties,
  warningText: {
    color: '#9a6519',
  } as React.CSSProperties,
  neutralText: {
    color: '#4f6259',
  } as React.CSSProperties,
};
