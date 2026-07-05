import React = require('@theia/core/shared/react');
import { Message } from '@theia/core/shared/@lumino/messaging';
import { injectable, postConstruct } from '@theia/core/shared/inversify';
import { ReactWidget } from '@theia/core/lib/browser/widgets/react-widget';
import * as Blockly from 'blockly/core';
import 'blockly/blocks';
import * as ZhHans from 'blockly/msg/zh-hans';

export const DUBHE_WIDGET_ID = 'dubhe.workbench';

Blockly.setLocale(ZhHans);

const DEFAULT_CORE_URL = 'http://127.0.0.1:8000';
const PROTOTYPE_URL = 'http://127.0.0.1:5173';
const DEVICE_SESSION_STORAGE_KEY = 'dubhe.theia.deviceSession';
const CORE_URL_STORAGE_KEY = 'dubhe.theia.coreUrl';
const STRATEGY_WORKSHOP_STORAGE_KEY = 'dubhe.theia.strategyWorkshop';
const DEFAULT_PAPER_ACCOUNT_ID = 'demo_account';
const CONFIGURE_COMMAND_LABEL = 'Configure-Dubhe.cmd';
const LOCAL_CONFIG_FILE_LABEL = 'config\\dubhe.local.env';

type ApiStatus = '未连接' | '请求中' | '已连接' | '离线';
type AuthMode = 'register' | 'login';
type DevicePlatform = 'windows' | 'macos' | 'ios' | 'android';
type Market = 'A_SHARE' | 'HK' | 'US' | 'GLOBAL';
type Sentiment = 'positive' | 'neutral' | 'negative';
type Tone = 'positive' | 'negative' | 'neutral' | 'warning';
type UserRole = 'user' | 'risk_manager' | 'admin';
type SyncConnectionStatus = '未连接' | '连接中' | '实时同步' | '重连中' | '离线';

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

type LLMRuntimeStatus = {
  provider: string;
  model?: string | null;
  configured: boolean;
  enabled: boolean;
  fallback_available: boolean;
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
  llm?: LLMRuntimeStatus;
  trading: TradingRuntimeStatus;
  generated_at: string;
};

type LocalRuntimeConfigItem = {
  key: string;
  label_zh: string;
  description_zh: string;
  configured: boolean;
  secret: boolean;
  source: 'local_file' | 'process_env' | 'missing';
  masked_value?: string | null;
  restart_required: boolean;
};

type LocalRuntimeConfigResponse = {
  editable: boolean;
  exists: boolean;
  path: string;
  items: LocalRuntimeConfigItem[];
  message_zh: string;
  generated_at: string;
};

type LocalRuntimeConfigUpdateRequest = {
  values: Record<string, string>;
};

type OnboardingStepStatus = 'complete' | 'action_required' | 'warning';

type OnboardingStep = {
  id: string;
  label_zh: string;
  status: OnboardingStepStatus;
  message_zh: string;
  action_zh?: string | null;
};

type OnboardingChecklistResponse = {
  service: string;
  language: string;
  complete_count: number;
  total_count: number;
  next_action_zh: string;
  steps: OnboardingStep[];
  generated_at: string;
};

type OnboardingStepAction = {
  label: string;
  disabled?: boolean;
};

type SmokeWorkflowStatus = 'passed' | 'failed' | 'missing';

type SmokeWorkflowStep = {
  name: string;
  status: 'passed' | 'failed';
  duration_ms: number;
  message: string;
  data?: unknown;
};

type SmokeWorkflowReportResponse = {
  service: string;
  language: string;
  available: boolean;
  status: SmokeWorkflowStatus;
  message_zh: string;
  generated_at: string;
  core_url: string;
  market: string;
  symbol: string;
  failure?: string | null;
  report_path: string;
  artifacts: Record<string, unknown>;
  steps: SmokeWorkflowStep[];
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

type StrategyValidationResult = {
  valid: boolean;
  reasons_zh: string[];
};

type StrategyWorkshopForm = {
  strategyName: string;
  timeframe: string;
  rebalanceRule: string;
  maxOrderNotional: number;
  includeNews: boolean;
  includeMarketBars: boolean;
  paperOnly: boolean;
};

type StrategyWorkshopStorage = {
  form: StrategyWorkshopForm;
  blocklyState: typeof defaultStrategyBlocklyState;
  savedAt: string;
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

type AssistantCitation = {
  label_zh: string;
  ref: string;
};

type AssistantChatResponse = {
  id: string;
  answer_zh: string;
  citations: AssistantCitation[];
  suggested_actions_zh: string[];
  safety_notes_zh: string[];
  model_provider: string;
  model_name?: string | null;
  fallback_used: boolean;
  generated_at: string;
};

type AssistantChatMessage = {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  citations?: AssistantCitation[];
  suggestedActions?: string[];
  modelProvider?: string;
  modelName?: string | null;
  fallbackUsed?: boolean;
};

type AssistantConversationTurn = {
  id: string;
  workspace_id: string;
  question_zh: string;
  answer_zh: string;
  citations: AssistantCitation[];
  suggested_actions_zh: string[];
  safety_notes_zh: string[];
  model_provider: string;
  model_name?: string | null;
  fallback_used: boolean;
  context_refs: string[];
  created_by_user_id?: string | null;
  created_by_device_id?: string | null;
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

type AuditLogEntry = {
  id: string;
  actor_user_id?: string | null;
  actor_device_id?: string | null;
  actor_role?: UserRole | null;
  action: string;
  target_type: string;
  target_id?: string | null;
  summary_zh: string;
  metadata: Record<string, unknown>;
  created_at: string;
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

type Workspace = {
  id: string;
  owner_user_id: string;
  name: string;
  created_at: string;
  updated_at: string;
};

type WatchlistItem = {
  id: string;
  workspace_id: string;
  symbol: string;
  name: string;
  market: Market;
  notes_zh?: string | null;
  added_at: string;
  updated_at: string;
};

type SyncEvent = {
  id: string;
  workspace_id: string;
  sequence: number;
  entity_type: string;
  entity_id: string;
  action: 'created' | 'updated' | 'deleted';
  payload: Record<string, unknown>;
  created_at: string;
};

type WorkspaceSnapshot = {
  workspace: Workspace;
  watchlist: WatchlistItem[];
  strategy_drafts: StrategyDraft[];
  backtest_results: BacktestResult[];
  assistant_turns?: AssistantConversationTurn[];
  events: SyncEvent[];
  server_sequence: number;
};

type WatchlistDisplayItem = {
  symbol: string;
  name: string;
  market: string;
  move: string;
  tone: Tone;
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

const assistantWelcomeMessages: AssistantChatMessage[] = [
  {
    id: 'assistant_welcome',
    role: 'assistant',
    text: '登录后可以直接问我新闻影响、策略规则、回测结果和纸面验证路径。',
  },
];

const defaultStrategyWorkshopForm: StrategyWorkshopForm = {
  strategyName: '新闻情绪纸面验证策略',
  timeframe: '1d',
  rebalanceRule: 'daily',
  maxOrderNotional: 10000,
  includeNews: true,
  includeMarketBars: true,
  paperOnly: true,
};

const strategyBlocklyToolbox = {
  kind: 'categoryToolbox',
  contents: [
    {
      kind: 'category',
      name: '策略文字',
      colour: '#2f7d59',
      contents: [
        { kind: 'block', type: 'text' },
        { kind: 'block', type: 'text_join' },
      ],
    },
    {
      kind: 'category',
      name: '条件',
      colour: '#3366aa',
      contents: [
        { kind: 'block', type: 'logic_compare' },
        { kind: 'block', type: 'logic_operation' },
        { kind: 'block', type: 'logic_boolean' },
      ],
    },
    {
      kind: 'category',
      name: '数字',
      colour: '#8a5aa8',
      contents: [
        { kind: 'block', type: 'math_number' },
        { kind: 'block', type: 'math_arithmetic' },
      ],
    },
  ],
};

const defaultStrategyBlocklyState = {
  blocks: {
    languageVersion: 0,
    blocks: [
      {
        type: 'text',
        id: 'entry_rule',
        x: 28,
        y: 28,
        fields: { TEXT: '入场：新闻情绪为正面且影响分大于 0.7' },
      },
      {
        type: 'text',
        id: 'exit_rule',
        x: 28,
        y: 102,
        fields: { TEXT: '出场：新闻影响消退、跌破止损线或收盘前复核' },
      },
      {
        type: 'text',
        id: 'data_rule',
        x: 28,
        y: 176,
        fields: { TEXT: '数据：news, market_bars' },
      },
    ],
  },
};

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
  const [onboardingChecklist, setOnboardingChecklist] = React.useState<OnboardingChecklistResponse | null>(null);
  const [smokeReport, setSmokeReport] = React.useState<SmokeWorkflowReportResponse | null>(null);
  const [localConfig, setLocalConfig] = React.useState<LocalRuntimeConfigResponse | null>(null);
  const [localConfigForm, setLocalConfigForm] = React.useState<Record<string, string>>({});
  const [localConfigBusy, setLocalConfigBusy] = React.useState(false);
  const [analysis, setAnalysis] = React.useState<NewsAnalysis | null>(null);
  const [strategyDraft, setStrategyDraft] = React.useState<StrategyDraft | null>(null);
  const [strategyWorkshopForm, setStrategyWorkshopForm] = React.useState<StrategyWorkshopForm>(() => readStoredStrategyWorkshop()?.form ?? defaultStrategyWorkshopForm);
  const [strategyWorkshopSpec, setStrategyWorkshopSpec] = React.useState<StrategySpec | null>(null);
  const [strategyValidation, setStrategyValidation] = React.useState<StrategyValidationResult | null>(null);
  const [strategyWorkshopSavedAt, setStrategyWorkshopSavedAt] = React.useState<string | null>(() => readStoredStrategyWorkshop()?.savedAt ?? null);
  const [backtestResult, setBacktestResult] = React.useState<BacktestResult | null>(null);
  const [paperOrder, setPaperOrder] = React.useState<PaperOrder | null>(null);
  const [assistantQuestion, setAssistantQuestion] = React.useState('这条新闻会影响哪些股票？');
  const [assistantBusy, setAssistantBusy] = React.useState(false);
  const [assistantMessages, setAssistantMessages] = React.useState<AssistantChatMessage[]>(assistantWelcomeMessages);
  const [portfolio, setPortfolio] = React.useState<PaperPortfolioSnapshot | null>(null);
  const [workspaceSnapshot, setWorkspaceSnapshot] = React.useState<WorkspaceSnapshot | null>(null);
  const [syncConnectionStatus, setSyncConnectionStatus] = React.useState<SyncConnectionStatus>('未连接');
  const [lastSyncEvent, setLastSyncEvent] = React.useState<SyncEvent | null>(null);
  const [approvals, setApprovals] = React.useState<ApprovalRequest[]>([]);
  const [killSwitch, setKillSwitch] = React.useState<KillSwitchState | null>(null);
  const [auditLogs, setAuditLogs] = React.useState<AuditLogEntry[]>([]);
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
  const workspaceStrategyDrafts = workspaceSnapshot?.strategy_drafts ?? [];
  const workspaceBacktestResults = workspaceSnapshot?.backtest_results ?? [];
  const selectedMarketLabel = marketOptions.find((option) => option.value === market)?.label ?? market;
  const canManageRisk = session?.role === 'admin' || session?.role === 'risk_manager';
  const enabledAdapterCount = systemStatus?.news_adapters.filter((adapter) => adapter.enabled).length ?? 0;
  const adapterStatusMeta = systemStatus ? `${enabledAdapterCount}/${systemStatus.news_adapters.length} 可用` : '待检查';
  const missingConfigCount = systemStatus?.config_items.filter((item) => !item.configured).length ?? 0;
  const syncCursorRef = React.useRef(0);
  const blocklyContainerRef = React.useRef<HTMLDivElement | null>(null);
  const blocklyWorkspaceRef = React.useRef<Blockly.WorkspaceSvg | null>(null);

  React.useEffect(() => {
    void checkHealth();
  }, [coreUrl]);

  React.useEffect(() => {
    const container = blocklyContainerRef.current;
    if (!container) return;

    const workspace = Blockly.inject(container, {
      toolbox: strategyBlocklyToolbox,
      renderer: 'zelos',
      trashcan: true,
      move: {
        scrollbars: true,
        drag: true,
        wheel: true,
      },
      zoom: {
        controls: true,
        wheel: true,
        startScale: 0.82,
        maxScale: 1.4,
        minScale: 0.55,
        scaleSpeed: 1.1,
      },
    });
    blocklyWorkspaceRef.current = workspace;
    Blockly.serialization.workspaces.load(readStoredStrategyWorkshop()?.blocklyState ?? defaultStrategyBlocklyState, workspace);
    window.setTimeout(() => Blockly.svgResize(workspace), 0);

    const resetValidation = (event: Blockly.Events.Abstract) => {
      if (event.isUiEvent) return;
      setStrategyValidation(null);
      setStrategyWorkshopSpec(null);
    };
    workspace.addChangeListener(resetValidation);

    return () => {
      workspace.removeChangeListener(resetValidation);
      workspace.dispose();
      blocklyWorkspaceRef.current = null;
    };
  }, []);

  React.useEffect(() => {
    if (!workspaceSnapshot) return;
    syncCursorRef.current = Math.max(syncCursorRef.current, workspaceSnapshot.server_sequence);
  }, [workspaceSnapshot?.server_sequence]);

  React.useEffect(() => {
    if (!session) {
      setApprovals([]);
      setKillSwitch(null);
      setAuditLogs([]);
      setPortfolio(null);
      setWorkspaceSnapshot(null);
      setLocalConfig(null);
      setLocalConfigForm({});
      setLastSyncEvent(null);
      setSyncConnectionStatus('未连接');
      syncCursorRef.current = 0;
      setRiskMessage('登录后显示审批和急停状态。');
      return;
    }
    void loadSessionData(session);
  }, [coreUrl, session?.access_token, session?.role, session?.workspace_id]);

  React.useEffect(() => {
    if (!session) {
      setSyncConnectionStatus('未连接');
      return;
    }

    let closedByEffect = false;
    let socket: WebSocket | null = null;
    let retryTimer: number | undefined;
    let retryCount = 0;
    let cursor = syncCursorRef.current;

    const refreshFromSyncEvent = async (event: SyncEvent): Promise<void> => {
      const refreshes: Array<Promise<void>> = [loadWorkspaceSnapshot(session)];
      if (event.entity_type === 'paper_order' || event.entity_type === 'broker_order' || event.entity_type === 'paper_portfolio') {
        refreshes.push(loadPortfolio(session));
      }
      if (event.entity_type === 'approval_request' || event.entity_type === 'risk_decision') {
        refreshes.push(loadRiskControls(session));
      }
      await Promise.all(refreshes);
    };

    const connect = (): void => {
      if (closedByEffect) return;
      setSyncConnectionStatus(retryCount === 0 ? '连接中' : '重连中');
      socket = new WebSocket(
        toWebSocketUrl(
          coreUrl,
          `/v1/workspaces/${session.workspace_id}/sync-events/ws?access_token=${encodeURIComponent(session.access_token)}&since_sequence=${cursor}`,
        ),
      );

      socket.onopen = () => {
        if (closedByEffect) return;
        retryCount = 0;
        setSyncConnectionStatus('实时同步');
      };

      socket.onmessage = (message) => {
        if (closedByEffect) return;
        const event = parseSyncEvent(`${message.data}`);
        if (!event) return;
        cursor = Math.max(cursor, event.sequence);
        syncCursorRef.current = cursor;
        setLastSyncEvent(event);
        setLogs((current) => [
          createLog('neutral', `同步事件：#${event.sequence} ${syncEntityLabel(event.entity_type)} ${syncActionLabel(event.action)}。`),
          ...current,
        ].slice(0, 5));
        void refreshFromSyncEvent(event).catch((error: unknown) => {
          setLogs((current) => [
            createLog('warning', `同步事件刷新失败：${errorMessage(error)}。`),
            ...current,
          ].slice(0, 5));
        });
      };

      socket.onerror = () => {
        if (closedByEffect) return;
        setSyncConnectionStatus('离线');
      };

      socket.onclose = () => {
        if (closedByEffect) return;
        retryCount += 1;
        setSyncConnectionStatus('重连中');
        retryTimer = window.setTimeout(connect, Math.min(15000, retryCount * 1000));
      };
    };

    connect();

    return () => {
      closedByEffect = true;
      if (retryTimer !== undefined) {
        window.clearTimeout(retryTimer);
      }
      socket?.close();
    };
  }, [coreUrl, session?.access_token, session?.workspace_id]);

  const workspaceWatchlist = React.useMemo<WatchlistDisplayItem[]>(() => {
    if (!workspaceSnapshot || workspaceSnapshot.watchlist.length === 0) {
      return fallbackWatchlist;
    }
    return workspaceSnapshot.watchlist.map((item) => ({
      symbol: item.symbol,
      name: item.name,
      market: marketLabel(item.market),
      move: '同步',
      tone: 'neutral',
    }));
  }, [workspaceSnapshot]);

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
      const [, nextSystemStatus, nextChecklist, nextSmokeReport] = await Promise.all([
        getJson<Record<string, string>>(coreUrl, '/health'),
        getJson<SystemStatusResponse>(coreUrl, '/v1/system/status'),
        getJson<OnboardingChecklistResponse>(coreUrl, '/v1/onboarding/checklist', session?.access_token),
        getJson<SmokeWorkflowReportResponse>(coreUrl, '/v1/system/smoke-report'),
      ]);
      setSystemStatus(nextSystemStatus);
      setOnboardingChecklist(nextChecklist);
      setSmokeReport(nextSmokeReport);
      setApiStatus('已连接');
      appendLog('positive', 'Dubhe Core 健康检查和系统状态读取通过。');
    } catch (error) {
      setSystemStatus(null);
      setOnboardingChecklist(null);
      setSmokeReport(null);
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
      setWorkspaceSnapshot(null);
      setLocalConfig(null);
      setLocalConfigForm({});
      setAssistantMessages(assistantWelcomeMessages);
      setLastSyncEvent(null);
      setSyncConnectionStatus('未连接');
      syncCursorRef.current = 0;
      setApprovals([]);
      setKillSwitch(null);
      setAuditLogs([]);
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

  function updateStrategyWorkshopField<K extends keyof StrategyWorkshopForm>(field: K, value: StrategyWorkshopForm[K]): void {
    setStrategyWorkshopForm((current) => ({ ...current, [field]: value }));
    setStrategyValidation(null);
    setStrategyWorkshopSpec(null);
  }

  function saveStrategyWorkshopTemplate(): void {
    const workspace = blocklyWorkspaceRef.current;
    if (!workspace) {
      appendLog('warning', '策略工坊尚未准备好，稍后再保存。');
      return;
    }
    const savedAt = new Date().toISOString();
    const snapshot: StrategyWorkshopStorage = {
      form: strategyWorkshopForm,
      blocklyState: Blockly.serialization.workspaces.save(workspace) as typeof defaultStrategyBlocklyState,
      savedAt,
    };
    localStorage.setItem(STRATEGY_WORKSHOP_STORAGE_KEY, JSON.stringify(snapshot));
    setStrategyWorkshopSavedAt(savedAt);
    appendLog('positive', '策略工坊模板已保存到本机。');
  }

  function resetStrategyWorkshopTemplate(): void {
    const workspace = blocklyWorkspaceRef.current;
    setStrategyWorkshopForm(defaultStrategyWorkshopForm);
    setStrategyWorkshopSpec(null);
    setStrategyValidation(null);
    setStrategyWorkshopSavedAt(null);
    localStorage.removeItem(STRATEGY_WORKSHOP_STORAGE_KEY);
    if (workspace) {
      workspace.clear();
      Blockly.serialization.workspaces.load(defaultStrategyBlocklyState, workspace);
    }
    appendLog('warning', '策略工坊已恢复默认模板。');
  }

  async function validateWorkshopStrategy(): Promise<void> {
    const spec = createStrategySpecFromBlockly(
      strategyWorkshopForm,
      market,
      symbol.trim().toUpperCase(),
      blocklyWorkspaceRef.current,
    );
    setStrategyWorkshopSpec(spec);
    setStrategyValidation(null);
    await withBusy(async () => {
      const result = await postJson<StrategyValidationResult>(coreUrl, '/v1/strategy/spec/validate', spec);
      setStrategyValidation(result);
      appendLog(result.valid ? 'positive' : 'warning', result.valid ? '策略工坊校验通过，可进入回测。' : `策略工坊需要补充：${result.reasons_zh.join('；')}。`);
    }).catch((error: unknown) => {
      appendLog('negative', `策略工坊校验失败：${errorMessage(error)}。`);
    });
  }

  function useWorkshopStrategyDraft(): void {
    if (!strategyWorkshopSpec || !strategyValidation?.valid) {
      appendLog('warning', '请先通过策略工坊校验，再设为当前草案。');
      return;
    }
    setStrategyDraft(createWorkshopStrategyDraft(strategyWorkshopSpec, analysis?.id));
    setBacktestResult(null);
    setPaperOrder(null);
    appendLog('positive', '策略工坊草案已设为当前策略，可运行 replay 回测。');
  }

  async function saveWorkshopStrategyToCore(): Promise<void> {
    if (!strategyWorkshopSpec || !strategyValidation?.valid) {
      appendLog('warning', '请先通过策略工坊校验，再保存到工作区。');
      return;
    }
    const draft = createWorkshopStrategyDraft(strategyWorkshopSpec, analysis?.id);
    await withBusy(async () => {
      const savedDraft = await postJson<StrategyDraft>(coreUrl, '/v1/strategy/drafts', draft);
      setStrategyDraft(savedDraft);
      setBacktestResult(null);
      setPaperOrder(null);
      appendLog('positive', `策略草案已保存到工作区：${savedDraft.name}。`);
      if (session) {
        await loadWorkspaceSnapshot(session);
      }
    }).catch((error: unknown) => {
      appendLog('negative', `保存策略草案失败：${errorMessage(error)}。`);
    });
  }

  function loadWorkspaceStrategyDraft(draft: StrategyDraft): void {
    const workspace = blocklyWorkspaceRef.current;
    setStrategyDraft(draft);
    setStrategyWorkshopForm(strategySpecToWorkshopForm(draft.spec));
    setStrategyWorkshopSpec(draft.spec);
    setStrategyValidation({ valid: true, reasons_zh: [] });
    setBacktestResult(latestWorkspaceBacktest(draft, workspaceSnapshot?.backtest_results ?? []));
    setPaperOrder(null);
    if (workspace) {
      workspace.clear();
      Blockly.serialization.workspaces.load(strategySpecToBlocklyState(draft.spec), workspace);
    }
    appendLog('positive', `已载入工作区策略草案：${draft.name}。`);
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

  async function askAssistant(event?: React.FormEvent<HTMLFormElement>): Promise<void> {
    event?.preventDefault();
    const question = assistantQuestion.trim();
    if (!question) return;
    if (!session) {
      appendLog('warning', '请先登录账号，再使用 AI 分析师对话。');
      return;
    }

    const userMessage: AssistantChatMessage = {
      id: `assistant_user_${Date.now()}`,
      role: 'user',
      text: question,
    };
    setAssistantMessages((current) => [...current, userMessage].slice(-8));
    setAssistantQuestion('');
    setAssistantBusy(true);
    try {
      const response = await postJson<AssistantChatResponse>(
        coreUrl,
        '/v1/assistant/chat',
        {
          question_zh: question,
          context: {
            news_event: selectedNews,
            analysis,
            strategy: strategyDraft,
            backtest: backtestResult,
          },
        },
        session.access_token,
      );
      const assistantMessage: AssistantChatMessage = {
        id: response.id,
        role: 'assistant',
        text: response.answer_zh,
        citations: response.citations,
        suggestedActions: response.suggested_actions_zh,
        modelProvider: response.model_provider,
        modelName: response.model_name,
        fallbackUsed: response.fallback_used,
      };
      setAssistantMessages((current) => [...current, assistantMessage].slice(-8));
      appendLog('positive', 'AI 分析师已生成中文研究答复。');
    } catch (error) {
      const failureMessage: AssistantChatMessage = {
        id: `assistant_error_${Date.now()}`,
        role: 'assistant',
        text: `AI 分析师暂时不可用：${errorMessage(error)}。`,
      };
      setAssistantMessages((current) => [...current, failureMessage].slice(-8));
      appendLog('negative', `AI 分析师对话失败：${errorMessage(error)}。`);
    } finally {
      setAssistantBusy(false);
    }
  }

  async function submitPaperOrder(): Promise<void> {
    if (!session) {
      appendLog('warning', '请先登录账号，再提交纸面交易。');
      return;
    }
    if (!analysis && !strategyDraft) {
      appendLog('warning', '请先完成新闻分析或加载同步策略，纸面订单需要来源引用。');
      return;
    }
    const orderSymbol = paperTradeSymbol(symbol, strategyDraft);
    const orderMarket = paperTradeMarket(market, orderSymbol, strategyDraft);
    const sourceRef = paperTradeSourceRef(analysis, strategyDraft, selectedNews);
    await withBusy(async () => {
      const order = await postJson<PaperOrder>(
        coreUrl,
        '/v1/simulation/paper-orders',
        {
          account_id: DEFAULT_PAPER_ACCOUNT_ID,
          strategy_version_id: strategyDraft?.strategy_version_id ?? 'manual_theia_strategy',
          market: orderMarket,
          symbol: orderSymbol,
          side: 'buy',
          order_type: 'market',
          quantity: 1,
          estimated_price: estimatePrice(orderSymbol),
          currency: currencyForMarket(orderMarket),
          created_by: 'user',
          destination: 'paper',
          rationale_zh: 'Theia 工作台根据新闻分析提交纸面交易验证。',
          source_refs: [sourceRef],
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
      await Promise.all([
        loadWorkspaceSnapshot(activeSession),
        loadPortfolio(activeSession),
        loadRiskControls(activeSession),
        loadLocalConfig(activeSession),
        loadOnboardingChecklist(activeSession),
      ]);
    } catch (error) {
      appendLog('warning', `会话数据同步失败：${errorMessage(error)}。`);
    }
  }

  async function loadWorkspaceSnapshot(activeSession = session): Promise<void> {
    if (!activeSession) {
      setWorkspaceSnapshot(null);
      return;
    }
    const snapshot = await getJson<WorkspaceSnapshot>(
      coreUrl,
      `/v1/workspaces/${activeSession.workspace_id}/snapshot`,
      activeSession.access_token,
    );
    setWorkspaceSnapshot(snapshot);
    setAssistantMessages(assistantMessagesFromTurns(snapshot.assistant_turns ?? []));
    const syncedBacktest = latestWorkspaceBacktest(strategyDraft, snapshot.backtest_results);
    if (syncedBacktest) {
      setBacktestResult(syncedBacktest);
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
      setAuditLogs([]);
      setRiskMessage('登录后显示审批和急停状态。');
      return;
    }
    if (activeSession.role !== 'admin' && activeSession.role !== 'risk_manager') {
      setApprovals([]);
      setKillSwitch(null);
      setAuditLogs([]);
      setRiskMessage('当前账号没有审批权限。管理员或风控管理员登录后可管理审批和 kill switch。');
      return;
    }

    setRiskBusy(true);
    try {
      const [nextApprovals, nextKillSwitch, nextAuditLogs] = await Promise.all([
        getJson<ApprovalRequest[]>(coreUrl, '/v1/approvals?status=pending', activeSession.access_token),
        getJson<KillSwitchState>(coreUrl, '/v1/risk/kill-switch', activeSession.access_token),
        getJson<AuditLogEntry[]>(coreUrl, '/v1/audit/logs?limit=8', activeSession.access_token),
      ]);
      setApprovals(nextApprovals);
      setKillSwitch(nextKillSwitch);
      setAuditLogs(nextAuditLogs);
      setRiskMessage(nextApprovals.length > 0 ? `当前有 ${nextApprovals.length} 个待处理审批。` : '当前没有待处理审批。');
    } catch (error) {
      setApprovals([]);
      setKillSwitch(null);
      setAuditLogs([]);
      setRiskMessage(`风控中心同步失败：${errorMessage(error)}。`);
    } finally {
      setRiskBusy(false);
    }
  }

  async function loadLocalConfig(activeSession = session): Promise<void> {
    if (!activeSession || activeSession.role !== 'admin') {
      setLocalConfig(null);
      setLocalConfigForm({});
      return;
    }
    setLocalConfigBusy(true);
    try {
      const nextConfig = await getJson<LocalRuntimeConfigResponse>(
        coreUrl,
        '/v1/runtime/local-config',
        activeSession.access_token,
      );
      setLocalConfig(nextConfig);
      setLocalConfigForm(localConfigFormFromResponse(nextConfig));
    } catch (error) {
      setLocalConfig(null);
      setLocalConfigForm({});
      appendLog('warning', `本地配置读取失败：${errorMessage(error)}。`);
    } finally {
      setLocalConfigBusy(false);
    }
  }

  async function loadOnboardingChecklist(activeSession = session): Promise<void> {
    try {
      const checklist = await getJson<OnboardingChecklistResponse>(
        coreUrl,
        '/v1/onboarding/checklist',
        activeSession?.access_token,
      );
      setOnboardingChecklist(checklist);
    } catch (error) {
      setOnboardingChecklist(null);
      appendLog('warning', `首次使用清单读取失败：${errorMessage(error)}。`);
    }
  }

  async function loadSmokeReport(): Promise<void> {
    try {
      const report = await getJson<SmokeWorkflowReportResponse>(coreUrl, '/v1/system/smoke-report');
      setSmokeReport(report);
      appendLog(report.status === 'passed' ? 'positive' : 'warning', report.message_zh);
    } catch (error) {
      setSmokeReport(null);
      appendLog('warning', `主链路烟测报告读取失败：${errorMessage(error)}。`);
    }
  }

  function updateLocalConfigField(key: string, value: string): void {
    setLocalConfigForm((current) => ({ ...current, [key]: value }));
  }

  async function saveLocalConfig(): Promise<void> {
    if (!session || session.role !== 'admin') {
      appendLog('warning', '只有管理员可以修改本地运行配置。');
      return;
    }
    if (!localConfig) {
      appendLog('warning', '请先读取本地配置状态。');
      return;
    }

    const values: Record<string, string> = {};
    for (const item of localConfig.items) {
      const nextValue = localConfigForm[item.key] ?? '';
      if (item.secret) {
        if (nextValue.trim()) values[item.key] = nextValue;
      } else if (nextValue.trim() || item.configured) {
        values[item.key] = nextValue;
      }
    }
    if (Object.keys(values).length === 0) {
      appendLog('warning', '没有需要保存的配置值。');
      return;
    }

    setLocalConfigBusy(true);
    try {
      const nextConfig = await putJson<LocalRuntimeConfigResponse, LocalRuntimeConfigUpdateRequest>(
        coreUrl,
        '/v1/runtime/local-config',
        { values },
        session.access_token,
      );
      setLocalConfig(nextConfig);
      setLocalConfigForm(localConfigFormFromResponse(nextConfig));
      await checkHealth();
      appendLog('positive', '本地配置已保存并应用到当前 Core；数据库路径变更需重启后生效。');
    } catch (error) {
      appendLog('negative', `本地配置保存失败：${errorMessage(error)}。`);
    } finally {
      setLocalConfigBusy(false);
    }
  }

  function onboardingActionForStep(step: OnboardingStep): OnboardingStepAction | null {
    if (step.status === 'complete') return null;
    if (step.id === 'account_login') return { label: '创建账号或登录', disabled: isBusy };
    if (step.id === 'runtime_config') return { label: session?.role === 'admin' ? '打开配置检查' : '查看配置指引', disabled: localConfigBusy };
    if (step.id === 'news_ready') return { label: '刷新新闻源', disabled: isBusy };
    if (step.id === 'ai_assistant_ready') return { label: session ? '准备 AI 问题' : '先登录再使用 AI', disabled: assistantBusy };
    if (step.id === 'workspace_sync') return { label: session ? '刷新同步状态' : '先登录启用同步', disabled: isBusy };
    if (step.id === 'paper_trading_ready') return { label: '提交纸面验证', disabled: isBusy };
    if (step.id === 'live_trading_guard') return { label: canManageRisk ? '查看风控中心' : '查看风控边界', disabled: riskBusy };
    if (step.id === 'core_connected') return { label: '重新检查 Core', disabled: isBusy };
    return step.action_zh ? { label: '处理这一步', disabled: isBusy } : null;
  }

  function runOnboardingStepAction(step: OnboardingStep): void {
    if (step.id === 'account_login') {
      setAuthMode('register');
      appendLog('neutral', '请在左侧创建账号或切回登录；完成后会自动启用同步和纸面交易入口。');
      return;
    }
    if (step.id === 'runtime_config') {
      if (session?.role === 'admin') {
        void loadLocalConfig(session);
        appendLog('neutral', '请在右侧“数据源配置”填写 AI 模型和授权新闻源 key，保存后会重新检查 Core。');
      } else {
        appendLog('warning', '本地运行配置需要管理员账号修改；当前可先使用公开/演示新闻源和本地 AI 兜底。');
      }
      return;
    }
    if (step.id === 'news_ready' || step.id === 'core_connected') {
      void (step.id === 'core_connected' ? checkHealth() : refreshNewsFeed());
      return;
    }
    if (step.id === 'ai_assistant_ready') {
      if (!session) {
        appendLog('warning', '请先登录账号，再使用可跨端恢复的 AI 分析师对话。');
        return;
      }
      setAssistantQuestion('请根据当前新闻、策略和回测，告诉我下一步该怎么做。');
      appendLog('neutral', '已把问题填入右侧 AI 分析师对话框，请确认后发送。');
      return;
    }
    if (step.id === 'workspace_sync') {
      if (!session) {
        appendLog('warning', '请先登录账号，再刷新工作区同步状态。');
        return;
      }
      void loadWorkspaceSnapshot(session);
      return;
    }
    if (step.id === 'paper_trading_ready') {
      void submitPaperOrder();
      return;
    }
    if (step.id === 'live_trading_guard') {
      if (session) void loadRiskControls(session);
      appendLog('neutral', '风控中心已在右侧面板展示；Dubhe 当前不会直接发送真实券商订单。');
      return;
    }
    appendLog('neutral', step.action_zh ?? '这一步暂时只提供状态提示。');
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
      await loadRiskControls(session);
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

    const nextSymbol = paperTradeSymbol(symbol, strategyDraft);
    const nextMarket = paperTradeMarket(market, nextSymbol, strategyDraft);
    const sourceRef = paperTradeSourceRef(analysis, strategyDraft, selectedNews);
    setRiskBusy(true);
    try {
      const decision = await postJson<RiskDecision>(
        coreUrl,
        '/v1/risk/evaluate',
        {
          account_id: DEFAULT_PAPER_ACCOUNT_ID,
          strategy_version_id: strategyDraft?.strategy_version_id ?? 'manual_live_approval_demo',
          market: nextMarket,
          symbol: nextSymbol,
          side: 'buy',
          order_type: 'market',
          quantity: 1,
          estimated_price: estimatePrice(nextSymbol),
          currency: currencyForMarket(nextMarket),
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

          <PanelTitle title="同步状态" meta={workspaceSnapshot ? `#${workspaceSnapshot.server_sequence} · ${syncConnectionStatus}` : syncConnectionStatus} />
          <div style={styles.syncCard}>
            {workspaceSnapshot ? (
              <>
                <div style={styles.syncTopLine}>
                  <strong style={styles.statusName}>{workspaceSnapshot.workspace.name}</strong>
                  <button
                    style={styles.inlineTextButton}
                    type="button"
                    onClick={() => void loadWorkspaceSnapshot(session)}
                    disabled={isBusy || !session}
                  >
                    刷新
                  </button>
                </div>
                <div style={styles.syncMetrics}>
                  <Metric label="自选股" value={`${workspaceSnapshot.watchlist.length}`} tone="neutral" compact />
                  <Metric label="策略草案" value={`${workspaceStrategyDrafts.length}`} tone="neutral" compact />
                  <Metric label="回测" value={`${workspaceBacktestResults.length}`} tone="neutral" compact />
                  <Metric label="同步事件" value={`${workspaceSnapshot.events.length}`} tone="neutral" compact />
                  <Metric label="服务器序号" value={`${workspaceSnapshot.server_sequence}`} tone="positive" compact />
                  <Metric label="实时连接" value={syncConnectionStatus} tone={syncConnectionTone(syncConnectionStatus)} compact />
                </div>
                {lastSyncEvent && (
                  <p style={styles.statusMessage}>
                    最近推送：#{lastSyncEvent.sequence} {syncEntityLabel(lastSyncEvent.entity_type)} {syncActionLabel(lastSyncEvent.action)}
                  </p>
                )}
                <div style={styles.syncEventList}>
                  {workspaceSnapshot.events.slice(0, 3).map((event) => (
                    <p style={styles.statusMessage} key={event.id}>
                      #{event.sequence} {syncEntityLabel(event.entity_type)} {syncActionLabel(event.action)}
                    </p>
                  ))}
                </div>
              </>
            ) : (
              <p style={styles.bodyText}>登录后显示工作区快照、自选股和最近同步事件。</p>
            )}
          </div>

          <PanelTitle title="自选列表" meta={workspaceSnapshot ? 'Core 同步' : '演示'} />
          <div style={styles.watchlist}>
            {workspaceWatchlist.map((item) => (
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
                <p style={styles.bodyText}>当前 Theia 壳已能调用 Core 完成：新闻源刷新、中文分析、Blockly 策略工坊、回测和纸面订单。</p>
              </div>
              <div style={styles.workflowSteps}>
                <StepPill label="新闻" done={newsEvents.length > 0} />
                <StepPill label="AI 分析" done={Boolean(analysis)} />
                <StepPill label="策略校验" done={Boolean(strategyValidation?.valid)} />
                <StepPill label="策略草案" done={Boolean(strategyDraft)} />
                <StepPill label="回测" done={Boolean(backtestResult)} />
                <StepPill label="纸面交易" done={Boolean(paperOrder)} />
              </div>
            </section>

            <section style={styles.strategyWorkshop}>
              <header style={styles.panelHeader}>
                <div>
                  <h3 style={styles.panelHeading}>策略工坊</h3>
                  <p style={styles.bodyText}>拖动或改写中文积木，Dubhe 会生成可校验的策略规格；通过前不会进入回测或交易。</p>
                </div>
                <span style={styles.smallMeta}>
                  {strategyWorkshopSavedAt ? `已保存 ${shortTime(strategyWorkshopSavedAt)}` : 'Blockly · Core 校验'}
                </span>
              </header>
              <div style={styles.strategyWorkshopGrid}>
                <div ref={blocklyContainerRef} style={styles.blocklySurface} aria-label="Blockly 策略积木画布" />
                <div style={styles.strategyFormPanel}>
                  <label style={styles.stackField}>
                    策略名称
                    <input
                      style={styles.textInput}
                      value={strategyWorkshopForm.strategyName}
                      onChange={(event) => updateStrategyWorkshopField('strategyName', event.target.value)}
                    />
                  </label>
                  <div style={styles.twoColumnControls}>
                    <label style={styles.stackField}>
                      周期
                      <select
                        style={styles.selectInput}
                        value={strategyWorkshopForm.timeframe}
                        onChange={(event) => updateStrategyWorkshopField('timeframe', event.target.value)}
                      >
                        <option value="1d">日线</option>
                        <option value="1h">小时线</option>
                        <option value="15m">15 分钟</option>
                      </select>
                    </label>
                    <label style={styles.stackField}>
                      最大名义金额
                      <input
                        style={styles.textInput}
                        type="number"
                        min={1000}
                        step={1000}
                        value={strategyWorkshopForm.maxOrderNotional}
                        onChange={(event) => updateStrategyWorkshopField('maxOrderNotional', Number(event.target.value) || 0)}
                      />
                    </label>
                  </div>
                  <label style={styles.stackField}>
                    调仓方式
                    <select
                      style={styles.selectInput}
                      value={strategyWorkshopForm.rebalanceRule}
                      onChange={(event) => updateStrategyWorkshopField('rebalanceRule', event.target.value)}
                    >
                      <option value="daily">每日复核</option>
                      <option value="event_driven">新闻事件触发</option>
                      <option value="manual_review">人工确认后执行</option>
                    </select>
                  </label>
                  <div style={styles.checkboxGrid}>
                    <label style={styles.inlineToggle}>
                      <input
                        type="checkbox"
                        checked={strategyWorkshopForm.includeNews}
                        onChange={(event) => updateStrategyWorkshopField('includeNews', event.target.checked)}
                      />
                      使用新闻数据
                    </label>
                    <label style={styles.inlineToggle}>
                      <input
                        type="checkbox"
                        checked={strategyWorkshopForm.includeMarketBars}
                        onChange={(event) => updateStrategyWorkshopField('includeMarketBars', event.target.checked)}
                      />
                      使用行情数据
                    </label>
                    <label style={styles.inlineToggle}>
                      <input
                        type="checkbox"
                        checked={strategyWorkshopForm.paperOnly}
                        onChange={(event) => updateStrategyWorkshopField('paperOnly', event.target.checked)}
                      />
                      仅允许纸面验证
                    </label>
                  </div>
                  <div style={styles.strategyActions}>
                    <button style={styles.primaryButton} type="button" disabled={isBusy} onClick={() => void validateWorkshopStrategy()}>
                      校验策略
                    </button>
                    <button style={styles.secondaryButton} type="button" disabled={!strategyValidation?.valid} onClick={useWorkshopStrategyDraft}>
                      设为草案
                    </button>
                    <button style={styles.secondaryButton} type="button" disabled={!strategyValidation?.valid || isBusy} onClick={() => void saveWorkshopStrategyToCore()}>
                      保存到工作区
                    </button>
                    <button style={styles.secondaryButton} type="button" onClick={saveStrategyWorkshopTemplate}>
                      保存模板
                    </button>
                    <button style={styles.secondaryButton} type="button" onClick={resetStrategyWorkshopTemplate}>
                      恢复默认
                    </button>
                  </div>
                  <div style={styles.validationBox}>
                    <strong style={styles.statusName}>
                      {strategyValidation ? (strategyValidation.valid ? '校验通过' : '需要补充') : '待校验'}
                    </strong>
                    <p style={styles.statusMessage}>
                      {strategyValidation
                        ? strategyValidation.valid
                          ? '策略规格已包含风控限额、数据依赖和纸面权限。'
                          : strategyValidation.reasons_zh.join('；')
                        : '校验会调用 Dubhe Core，不通过就不能设为当前草案。'}
                    </p>
                    {strategyWorkshopSpec && (
                      <p style={styles.statusMessage}>
                        当前标的：{strategyWorkshopSpec.asset_universe.join('、')} · 数据：{strategyWorkshopSpec.data_dependencies.join('、')}
                      </p>
                    )}
                  </div>
                  <div style={styles.workspaceDraftList}>
                    <div style={styles.auditHeaderLine}>
                      <strong style={styles.statusName}>工作区草案</strong>
                      <span style={styles.smallMeta}>{workspaceStrategyDrafts.length} 个</span>
                    </div>
                    {workspaceStrategyDrafts.length === 0 ? (
                      <p style={styles.statusMessage}>保存到工作区后，其他设备也会同步看到。</p>
                    ) : (
                      workspaceStrategyDrafts.slice(0, 3).map((draft) => (
                        <div style={styles.workspaceDraftRow} key={draft.id}>
                          <div>
                            <strong style={styles.statusName}>{draft.name}</strong>
                            <p style={styles.statusMessage}>{draft.strategy_version_id} · {shortTime(draft.created_at)}</p>
                          </div>
                          <button style={styles.inlineTextButton} type="button" onClick={() => loadWorkspaceStrategyDraft(draft)}>
                            使用
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                </div>
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
            {assistantMessages.map((message) => (
              <div
                key={message.id}
                style={message.role === 'user' ? styles.chatUser : styles.chatAssistant}
              >
                <div>{message.text}</div>
                {assistantModelLabel(message) && (
                  <div style={styles.chatCitations}>
                    <span style={styles.chatCitation}>{assistantModelLabel(message)}</span>
                  </div>
                )}
                {message.citations && message.citations.length > 0 && (
                  <div style={styles.chatCitations}>
                    {message.citations.slice(0, 3).map((citation) => (
                      <span style={styles.chatCitation} key={`${message.id}-${citation.ref}`}>
                        {citation.label_zh} · {shortRef(citation.ref)}
                      </span>
                    ))}
                  </div>
                )}
                {message.suggestedActions && message.suggestedActions.length > 0 && (
                  <div style={styles.chatSuggestions}>
                    {message.suggestedActions.slice(0, 3).map((action) => (
                      <span style={styles.chatSuggestion} key={`${message.id}-${action}`}>{action}</span>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
          <form style={styles.assistantForm} onSubmit={(event) => void askAssistant(event)}>
            <textarea
              style={styles.assistantInput}
              value={assistantQuestion}
              onChange={(event) => setAssistantQuestion(event.target.value)}
              placeholder="问：这条新闻影响哪些股票？策略和回测怎么看？"
              rows={3}
            />
            <div style={styles.assistantActions}>
              <button
                style={styles.inlineTextButton}
                type="button"
                disabled={assistantBusy}
                onClick={() => setAssistantQuestion('可以直接实盘买吗？需要哪些风控步骤？')}
              >
                实盘风险
              </button>
              <button
                style={styles.inlineTextButton}
                type="button"
                disabled={assistantBusy}
                onClick={() => setAssistantQuestion('请根据当前新闻、策略和回测，给我下一步纸面验证清单。')}
              >
                验证清单
              </button>
              <button style={styles.primaryButton} type="submit" disabled={assistantBusy || !assistantQuestion.trim()}>
                {assistantBusy ? '分析中' : '发送'}
              </button>
            </div>
          </form>

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
                <StatusRow
                  label="AI 模型"
                  value={systemStatus.llm?.enabled ? (systemStatus.llm.model ?? systemStatus.llm.provider) : '本地兜底'}
                  tone={systemStatus.llm?.enabled ? 'positive' : 'warning'}
                  message={systemStatus.llm?.message_zh ?? '未读取到模型状态；默认按本地安全兜底处理。'}
                />
              </div>
            ) : (
              <p style={styles.bodyText}>点击左侧“检查”后显示 Core、存储、认证和交易开关状态。</p>
            )}
          </SidePanel>

          <SidePanel title="主链路烟测" meta={smokeReport ? smokeStatusLabel(smokeReport.status) : '待读取'}>
            {smokeReport ? (
              <SmokeWorkflowPanel report={smokeReport} onRefresh={() => void loadSmokeReport()} />
            ) : (
              <>
                <p style={styles.bodyText}>连接 Core 后显示最近一次账号、新闻、AI、策略、回测、纸面交易和同步烟测结果。</p>
                <button style={styles.fullWidthButtonInline} type="button" onClick={() => void loadSmokeReport()}>
                  读取报告
                </button>
              </>
            )}
          </SidePanel>

          <SidePanel
            title="首次使用清单"
            meta={onboardingChecklist ? `${onboardingChecklist.complete_count}/${onboardingChecklist.total_count}` : '待检查'}
          >
            {onboardingChecklist ? (
              <OnboardingChecklistPanel
                checklist={onboardingChecklist}
                actionForStep={onboardingActionForStep}
                onRunStep={runOnboardingStepAction}
              />
            ) : (
              <p style={styles.bodyText}>连接 Core 后显示从登录、配置到纸面交易的下一步清单。</p>
            )}
          </SidePanel>

          <SidePanel title="数据源配置" meta={systemStatus ? `${missingConfigCount} 项待配置` : adapterStatusMeta}>
            {systemStatus ? (
              <>
                <ConfigurationGuide
                  systemStatus={systemStatus}
                  session={session}
                  localConfig={localConfig}
                  localConfigForm={localConfigForm}
                  busy={isBusy}
                  configBusy={localConfigBusy}
                  onRefresh={() => void checkHealth()}
                  onReloadConfig={() => void loadLocalConfig(session)}
                  onSaveConfig={() => void saveLocalConfig()}
                  onConfigFieldChange={updateLocalConfigField}
                />
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
              </>
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

          <SidePanel title="风控中心" meta={canManageRisk ? `${approvals.length} 审批 / ${auditLogs.length} 审计` : '只读'}>
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
                <div style={styles.auditList}>
                  <div style={styles.auditHeaderLine}>
                    <strong style={styles.statusName}>最近审计</strong>
                    <span style={styles.smallMeta}>最新 {auditLogs.length} 条</span>
                  </div>
                  {auditLogs.length === 0 ? (
                    <p style={styles.bodyText}>暂无审计记录。</p>
                  ) : (
                    auditLogs.slice(0, 5).map((entry) => (
                      <div style={styles.auditRow} key={entry.id}>
                        <div style={styles.approvalTopLine}>
                          <strong style={styles.statusName}>{auditActionLabel(entry.action)}</strong>
                          <span style={styles.smallMeta}>{shortTime(entry.created_at)}</span>
                        </div>
                        <p style={styles.auditSummary}>{entry.summary_zh}</p>
                        <p style={styles.statusMessage}>
                          {auditRoleLabel(entry.actor_role)} · {entry.target_type}
                          {entry.target_id ? ` · ${entry.target_id}` : ''}
                        </p>
                      </div>
                    ))
                  )}
                </div>
              </>
            )}
          </SidePanel>

          <SidePanel title="纸面交易" meta={paperOrder?.status ?? '待提交'}>
            <p style={styles.bodyText}>{paperOrder?.message_zh ?? '登录并完成分析或加载同步策略后，可提交 1 股纸面买入验证账本链路。'}</p>
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

function readStoredStrategyWorkshop(): StrategyWorkshopStorage | null {
  try {
    const raw = localStorage.getItem(STRATEGY_WORKSHOP_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<StrategyWorkshopStorage>;
    const form = coerceStrategyWorkshopForm(parsed.form);
    const blocklyState = parsed.blocklyState && typeof parsed.blocklyState === 'object'
      ? parsed.blocklyState
      : defaultStrategyBlocklyState;
    const savedAt = typeof parsed.savedAt === 'string' ? parsed.savedAt : new Date().toISOString();
    return form ? { form, blocklyState, savedAt } : null;
  } catch {
    localStorage.removeItem(STRATEGY_WORKSHOP_STORAGE_KEY);
    return null;
  }
}

function coerceStrategyWorkshopForm(value: unknown): StrategyWorkshopForm | null {
  if (!value || typeof value !== 'object') return null;
  const form = value as Partial<StrategyWorkshopForm>;
  return {
    strategyName: typeof form.strategyName === 'string' && form.strategyName.trim() ? form.strategyName : defaultStrategyWorkshopForm.strategyName,
    timeframe: typeof form.timeframe === 'string' && form.timeframe.trim() ? form.timeframe : defaultStrategyWorkshopForm.timeframe,
    rebalanceRule: typeof form.rebalanceRule === 'string' && form.rebalanceRule.trim() ? form.rebalanceRule : defaultStrategyWorkshopForm.rebalanceRule,
    maxOrderNotional: Number(form.maxOrderNotional) > 0 ? Number(form.maxOrderNotional) : defaultStrategyWorkshopForm.maxOrderNotional,
    includeNews: typeof form.includeNews === 'boolean' ? form.includeNews : defaultStrategyWorkshopForm.includeNews,
    includeMarketBars: typeof form.includeMarketBars === 'boolean' ? form.includeMarketBars : defaultStrategyWorkshopForm.includeMarketBars,
    paperOnly: typeof form.paperOnly === 'boolean' ? form.paperOnly : defaultStrategyWorkshopForm.paperOnly,
  };
}

function normalizeCoreUrl(value: string): string {
  const trimmed = value.trim() || DEFAULT_CORE_URL;
  return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
}

function toWebSocketUrl(baseUrl: string, path: string): string {
  const url = new URL(`${normalizeCoreUrl(baseUrl)}${path}`);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  return url.toString();
}

async function getJson<T>(baseUrl: string, path: string, accessToken?: string): Promise<T> {
  return requestJson<T>(baseUrl, path, { accessToken });
}

async function postJson<T>(baseUrl: string, path: string, body: unknown, accessToken?: string): Promise<T> {
  return requestJson<T>(baseUrl, path, { method: 'POST', body, accessToken });
}

async function putJson<T, B>(baseUrl: string, path: string, body: B, accessToken?: string): Promise<T> {
  return requestJson<T>(baseUrl, path, { method: 'PUT', body, accessToken });
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

function parseSyncEvent(raw: string): SyncEvent | null {
  try {
    const parsed = JSON.parse(raw) as Partial<SyncEvent>;
    if (
      typeof parsed.id === 'string' &&
      typeof parsed.workspace_id === 'string' &&
      typeof parsed.sequence === 'number' &&
      typeof parsed.entity_type === 'string' &&
      typeof parsed.entity_id === 'string' &&
      (parsed.action === 'created' || parsed.action === 'updated' || parsed.action === 'deleted') &&
      typeof parsed.created_at === 'string'
    ) {
      return {
        id: parsed.id,
        workspace_id: parsed.workspace_id,
        sequence: parsed.sequence,
        entity_type: parsed.entity_type,
        entity_id: parsed.entity_id,
        action: parsed.action,
        payload: parsed.payload && typeof parsed.payload === 'object' ? parsed.payload : {},
        created_at: parsed.created_at,
      };
    }
  } catch {
    // Ignore malformed sync payloads and keep the socket alive.
  }
  return null;
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

function currencyForMarket(market: Market): 'HKD' | 'CNY' | 'USD' {
  if (market === 'HK') return 'HKD';
  if (market === 'A_SHARE') return 'CNY';
  return 'USD';
}

function firstNonEmpty(values: Array<string | null | undefined>): string {
  return values.map((value) => value?.trim()).find((value): value is string => Boolean(value)) ?? 'manual_paper_trade';
}

function paperTradeSourceRef(analysis: NewsAnalysis | null, draft: StrategyDraft | null, event: NewsEvent): string {
  return firstNonEmpty([
    analysis?.id,
    draft?.source_analysis_id,
    draft?.id,
    draft?.strategy_version_id,
    event.id,
  ]);
}

function paperTradeSymbol(currentSymbol: string, draft: StrategyDraft | null): string {
  const draftSymbol = draft?.spec.asset_universe.find((asset) => asset.trim().length > 0)?.trim().toUpperCase();
  const selectedSymbol = currentSymbol.trim().toUpperCase();
  return draftSymbol ?? (selectedSymbol || 'NVDA');
}

function paperTradeMarket(currentMarket: Market, orderSymbol: string, draft: StrategyDraft | null): Market {
  const draftMarket = draft?.spec.market_scope.find((candidate) => candidate !== 'GLOBAL');
  if (draftMarket) return draftMarket;
  if (currentMarket !== 'GLOBAL') return currentMarket;
  return marketFromSymbol(orderSymbol);
}

function latestWorkspaceBacktest(draft: StrategyDraft | null, results: BacktestResult[]): BacktestResult | null {
  if (results.length === 0) return null;
  const strategyVersionId = draft?.strategy_version_id.trim();
  if (strategyVersionId) {
    return results.find((result) => result.strategy_version_id === strategyVersionId) ?? null;
  }
  return results[0];
}

function assistantMessagesFromTurns(turns: AssistantConversationTurn[]): AssistantChatMessage[] {
  if (turns.length === 0) return assistantWelcomeMessages;
  const messages: AssistantChatMessage[] = [];
  for (const turn of turns) {
    messages.push({
      id: `${turn.id}_question`,
      role: 'user',
      text: turn.question_zh,
    });
    messages.push({
      id: `${turn.id}_answer`,
      role: 'assistant',
      text: turn.answer_zh,
      citations: turn.citations,
      suggestedActions: turn.suggested_actions_zh,
      modelProvider: turn.model_provider,
      modelName: turn.model_name,
      fallbackUsed: turn.fallback_used,
    });
  }
  return messages.slice(-8);
}

function assistantModelLabel(message: AssistantChatMessage): string {
  if (message.role === 'user') return '';
  if (message.fallbackUsed) return '本地兜底';
  return message.modelName || message.modelProvider || '';
}

function marketLabel(market: Market): string {
  if (market === 'US') return '美股';
  if (market === 'HK') return '港股';
  if (market === 'A_SHARE') return 'A 股';
  return '全球';
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

function auditActionLabel(action: string): string {
  const labels: Record<string, string> = {
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
    'runtime.local_config_updated': '本地配置更新',
    'simulation.paper_order_submitted': '纸面订单',
  };
  return labels[action] ?? action;
}

function auditRoleLabel(role?: UserRole | null): string {
  if (!role) return '系统';
  return roleLabel(role);
}

function syncEntityLabel(entityType: string): string {
  const labels: Record<string, string> = {
    approval_request: '审批',
    assistant_turn: 'AI 分析师对话',
    backtest_result: '回测',
    broker_order: '模拟券商订单',
    news_analysis: 'AI 分析',
    news_event: '新闻',
    paper_order: '纸面订单',
    paper_portfolio: '纸面组合',
    risk_decision: '风控决定',
    strategy_draft: '策略草案',
    watchlist_item: '自选股',
    workspace: '工作区',
  };
  return labels[entityType] ?? entityType;
}

function syncActionLabel(action: SyncEvent['action']): string {
  if (action === 'created') return '已创建';
  if (action === 'updated') return '已更新';
  return '已删除';
}

function syncConnectionTone(status: SyncConnectionStatus): Tone {
  if (status === '实时同步') return 'positive';
  if (status === '离线') return 'negative';
  if (status === '连接中' || status === '重连中') return 'warning';
  return 'neutral';
}

function createStrategySpecFromBlockly(
  form: StrategyWorkshopForm,
  market: Market,
  symbol: string,
  workspace: Blockly.WorkspaceSvg | null,
): StrategySpec {
  const textBlocks = extractBlocklyTextBlocks(workspace);
  const entryRules = extractPrefixedRules(textBlocks, '入场');
  const exitRules = extractPrefixedRules(textBlocks, '出场');
  const dataDependencies = extractDataDependencies(textBlocks, form);
  const assetSymbol = symbol || 'NVDA';

  return {
    strategy_name: form.strategyName.trim() || defaultStrategyWorkshopForm.strategyName,
    market_scope: [market],
    asset_universe: [assetSymbol],
    entry_rules: entryRules.length > 0 ? entryRules : ['新闻情绪为正面且影响分大于 0.7'],
    exit_rules: exitRules.length > 0 ? exitRules : ['新闻影响消退、跌破止损线或收盘前复核'],
    risk_limits: {
      max_order_notional: Math.max(1, Number(form.maxOrderNotional) || defaultStrategyWorkshopForm.maxOrderNotional),
    },
    timeframe: form.timeframe || defaultStrategyWorkshopForm.timeframe,
    rebalance_rule: form.rebalanceRule || defaultStrategyWorkshopForm.rebalanceRule,
    data_dependencies: dataDependencies,
    broker_permissions: form.paperOnly ? ['paper'] : [],
  };
}

function strategySpecToWorkshopForm(spec: StrategySpec): StrategyWorkshopForm {
  return {
    strategyName: spec.strategy_name || defaultStrategyWorkshopForm.strategyName,
    timeframe: spec.timeframe || defaultStrategyWorkshopForm.timeframe,
    rebalanceRule: spec.rebalance_rule || defaultStrategyWorkshopForm.rebalanceRule,
    maxOrderNotional: Number(spec.risk_limits.max_order_notional) || defaultStrategyWorkshopForm.maxOrderNotional,
    includeNews: spec.data_dependencies.includes('news'),
    includeMarketBars: spec.data_dependencies.includes('market_bars'),
    paperOnly: spec.broker_permissions.includes('paper'),
  };
}

function strategySpecToBlocklyState(spec: StrategySpec): typeof defaultStrategyBlocklyState {
  return {
    blocks: {
      languageVersion: 0,
      blocks: [
        {
          type: 'text',
          id: 'entry_rule_loaded',
          x: 28,
          y: 28,
          fields: { TEXT: `入场：${spec.entry_rules.join('；') || '新闻情绪为正面且影响分大于 0.7'}` },
        },
        {
          type: 'text',
          id: 'exit_rule_loaded',
          x: 28,
          y: 102,
          fields: { TEXT: `出场：${spec.exit_rules.join('；') || '新闻影响消退或触发止损'}` },
        },
        {
          type: 'text',
          id: 'data_rule_loaded',
          x: 28,
          y: 176,
          fields: { TEXT: `数据：${spec.data_dependencies.join(', ') || 'news, market_bars'}` },
        },
      ],
    },
  };
}

function extractBlocklyTextBlocks(workspace: Blockly.WorkspaceSvg | null): string[] {
  if (!workspace) {
    return defaultStrategyBlocklyState.blocks.blocks.map((block) => block.fields.TEXT);
  }
  return workspace
    .getAllBlocks(false)
    .filter((block) => block.type === 'text')
    .map((block) => String(block.getFieldValue('TEXT') ?? '').trim())
    .filter(Boolean);
}

function extractPrefixedRules(values: string[], prefix: string): string[] {
  return values
    .filter((value) => value.startsWith(`${prefix}：`) || value.startsWith(`${prefix}:`))
    .map((value) => value.replace(new RegExp(`^${prefix}[：:]\\s*`), '').trim())
    .filter(Boolean);
}

function extractDataDependencies(values: string[], form: StrategyWorkshopForm): string[] {
  const dependencies = new Set<string>();
  if (form.includeNews) dependencies.add('news');
  if (form.includeMarketBars) dependencies.add('market_bars');

  values
    .filter((value) => value.startsWith('数据：') || value.startsWith('数据:'))
    .flatMap((value) => value.replace(/^数据[：:]\s*/, '').split(/[,，、\s]+/))
    .map(normalizeDataDependency)
    .filter(Boolean)
    .forEach((dependency) => dependencies.add(dependency));

  return [...dependencies];
}

function normalizeDataDependency(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (normalized === '新闻') return 'news';
  if (normalized === '行情') return 'market_bars';
  return normalized;
}

function generateStrategyPseudoCode(spec: StrategySpec): string {
  return [
    `strategy "${spec.strategy_name}"`,
    `market ${spec.market_scope.join(', ')}`,
    `assets ${spec.asset_universe.join(', ')}`,
    `entry ${spec.entry_rules.join('；')}`,
    `exit ${spec.exit_rules.join('；')}`,
    `risk max_order_notional=${spec.risk_limits.max_order_notional}`,
    `permissions ${spec.broker_permissions.join(', ') || 'none'}`,
  ].join('\n');
}

function createWorkshopStrategyDraft(spec: StrategySpec, analysisId?: string): StrategyDraft {
  const strategyVersionId = `blockly_${Date.now()}`;
  return {
    id: `strategy_draft_${strategyVersionId}`,
    strategy_version_id: strategyVersionId,
    name: spec.strategy_name,
    spec,
    explanation_zh: '由 Blockly 策略工坊生成；已通过 Dubhe Core 策略规格校验，仅允许纸面验证。',
    generated_code: generateStrategyPseudoCode(spec),
    source_analysis_id: analysisId ?? 'blockly_manual',
    created_at: new Date().toISOString(),
  };
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

function shortRef(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length <= 36) return trimmed;
  return `${trimmed.slice(0, 18)}...${trimmed.slice(-12)}`;
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

function ConfigurationGuide(props: {
  systemStatus: SystemStatusResponse;
  session: DeviceSession | null;
  localConfig: LocalRuntimeConfigResponse | null;
  localConfigForm: Record<string, string>;
  busy: boolean;
  configBusy: boolean;
  onRefresh: () => void;
  onReloadConfig: () => void;
  onSaveConfig: () => void;
  onConfigFieldChange: (key: string, value: string) => void;
}): React.ReactElement {
  const missingItems = props.systemStatus.config_items.filter((item) => !item.configured);
  const licensedNewsReady = props.systemStatus.news_adapters.some((adapter) => adapter.requires_license && adapter.enabled);
  const llmReady = Boolean(props.systemStatus.llm?.enabled);
  const ready = missingItems.length === 0;
  const tone: Tone = ready ? 'positive' : 'warning';
  const canEditConfig = props.session?.role === 'admin';

  return (
    <div style={{ ...styles.configGuide, ...styles.configGuideTone[tone] }}>
      <div style={styles.configGuideHeader}>
        <strong style={styles.statusName}>{ready ? '核心配置已读取' : '需要本机配置'}</strong>
        <span style={{ ...styles.miniPill, ...tonePillStyle(tone) }}>
          {ready ? '可用' : `${missingItems.length} 项待填`}
        </span>
      </div>
      <p style={styles.statusMessage}>
        {ready
          ? 'Core 已读取当前运行配置。AI、新闻源和交易功能仍会继续遵守只读建议、许可范围和实盘风控边界。'
          : `双击 ${CONFIGURE_COMMAND_LABEL}，在 ${LOCAL_CONFIG_FILE_LABEL} 填写自己的模型或新闻源 key；保存后重启 Dubhe Core，再重新检查。`}
      </p>
      <div style={styles.configSignalRow}>
        <span style={{ ...styles.chatCitation, ...tonePillStyle(llmReady ? 'positive' : 'warning') }}>
          AI {llmReady ? '已接入' : '本地兜底'}
        </span>
        <span style={{ ...styles.chatCitation, ...tonePillStyle(licensedNewsReady ? 'positive' : 'warning') }}>
          授权新闻 {licensedNewsReady ? '已接入' : '未接入'}
        </span>
      </div>
      {!ready && (
        <>
          <div style={styles.configStepList}>
            <span style={styles.configStep}>1. 双击仓库根目录的 {CONFIGURE_COMMAND_LABEL}</span>
            <span style={styles.configStep}>2. 删除需要项目前面的 #，填写自己的 key</span>
            <span style={styles.configStep}>3. 保存文件，重启 Dubhe，再点重新检查</span>
          </div>
          <div style={styles.configKeyList}>
            {missingItems.slice(0, 6).map((item) => (
              <span style={styles.configKeyPill} key={item.key}>{item.key}</span>
            ))}
          </div>
        </>
      )}
      <button style={styles.inlineTextButton} type="button" onClick={props.onRefresh} disabled={props.busy}>
        重新检查配置
      </button>
      <div style={styles.localConfigBox}>
        <div style={styles.configGuideHeader}>
          <strong style={styles.statusName}>图形化配置</strong>
          <span style={styles.smallMeta}>{props.localConfig?.exists ? '已创建' : '未创建'}</span>
        </div>
        <p style={styles.statusMessage}>
          {canEditConfig
            ? props.localConfig?.message_zh ?? '点击读取后可直接在工作台里保存模型和新闻源配置。'
            : '管理员登录后可在这里直接保存本机模型和新闻源配置。'}
        </p>
        {props.localConfig?.path && <p style={styles.configPath}>{props.localConfig.path}</p>}
        {canEditConfig && (
          <div style={styles.localConfigActions}>
            <button
              style={styles.inlineTextButton}
              type="button"
              onClick={props.onReloadConfig}
              disabled={props.configBusy}
            >
              读取配置
            </button>
          </div>
        )}
        {canEditConfig && props.localConfig && (
          <form
            style={styles.localConfigForm}
            onSubmit={(event) => {
              event.preventDefault();
              props.onSaveConfig();
            }}
          >
            {props.localConfig.items.map((item) => (
              <label style={styles.configField} key={item.key}>
                <span style={styles.configFieldTopLine}>
                  <span style={styles.configFieldLabel}>{item.label_zh}</span>
                  <span style={{ ...styles.miniPill, ...tonePillStyle(item.configured ? 'positive' : 'warning') }}>
                    {item.configured ? sourceLabel(item.source) : '未配置'}
                  </span>
                </span>
                <input
                  style={styles.configInput}
                  type={item.secret ? 'password' : 'text'}
                  value={props.localConfigForm[item.key] ?? ''}
                  placeholder={item.secret && item.configured ? '已配置，留空保持不变' : item.key}
                  onChange={(event) => props.onConfigFieldChange(item.key, event.target.value)}
                  disabled={props.configBusy}
                />
                <span style={styles.configHint}>
                  {item.description_zh}{item.restart_required ? ' 修改后需要重启 Core。' : ''}
                </span>
              </label>
            ))}
            <button style={styles.fullWidthButtonInline} type="submit" disabled={props.configBusy}>
              {props.configBusy ? '保存中' : '保存到本机配置'}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

function localConfigFormFromResponse(response: LocalRuntimeConfigResponse): Record<string, string> {
  const values: Record<string, string> = {};
  for (const item of response.items) {
    values[item.key] = item.secret ? '' : item.masked_value ?? '';
  }
  return values;
}

function sourceLabel(source: LocalRuntimeConfigItem['source']): string {
  if (source === 'local_file') return '本机文件';
  if (source === 'process_env') return '环境变量';
  return '未配置';
}

function OnboardingChecklistPanel(props: {
  checklist: OnboardingChecklistResponse;
  actionForStep: (step: OnboardingStep) => OnboardingStepAction | null;
  onRunStep: (step: OnboardingStep) => void;
}): React.ReactElement {
  const nextStep = nextOnboardingStep(props.checklist);
  const nextAction = nextStep ? props.actionForStep(nextStep) : null;
  return (
    <div style={styles.onboardingBox}>
      <div style={styles.onboardingProgress}>
        <span>{props.checklist.complete_count}/{props.checklist.total_count}</span>
        <strong>下一步：{props.checklist.next_action_zh}</strong>
        {nextStep && nextAction && (
          <button
            style={styles.onboardingPrimaryAction}
            type="button"
            disabled={nextAction.disabled}
            onClick={() => props.onRunStep(nextStep)}
          >
            {nextAction.label}
          </button>
        )}
      </div>
      <div style={styles.onboardingStepList}>
        {props.checklist.steps.map((step) => {
          const action = step.status === 'complete' ? null : props.actionForStep(step);
          return (
            <div style={styles.onboardingStep} key={step.id}>
              <span style={{ ...styles.onboardingDot, ...onboardingDotStyle(step.status) }} />
              <div>
                <div style={styles.statusRowHeader}>
                  <strong style={styles.statusName}>{step.label_zh}</strong>
                  <span style={{ ...styles.miniPill, ...tonePillStyle(onboardingTone(step.status)) }}>
                    {onboardingStatusLabel(step.status)}
                  </span>
                </div>
                <p style={styles.statusMessage}>{step.message_zh}</p>
                {step.action_zh && <p style={styles.configHint}>建议：{step.action_zh}</p>}
                {action && (
                  <button
                    style={styles.onboardingInlineAction}
                    type="button"
                    disabled={action.disabled}
                    onClick={() => props.onRunStep(step)}
                  >
                    {action.label}
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function nextOnboardingStep(checklist: OnboardingChecklistResponse): OnboardingStep | null {
  return (
    checklist.steps.find((step) => step.status === 'action_required') ??
    checklist.steps.find((step) => step.status === 'warning') ??
    null
  );
}

function SmokeWorkflowPanel(props: {
  report: SmokeWorkflowReportResponse;
  onRefresh: () => void;
}): React.ReactElement {
  return (
    <div style={styles.statusList}>
      <div style={styles.statusRow}>
        <div style={styles.statusRowHeader}>
          <strong style={styles.statusName}>{props.report.available ? '最近一次烟测' : '尚无烟测报告'}</strong>
          <span style={{ ...styles.miniPill, ...tonePillStyle(smokeTone(props.report.status)) }}>
            {smokeStatusLabel(props.report.status)}
          </span>
        </div>
        <p style={styles.statusMessage}>{props.report.message_zh}</p>
        <p style={styles.configHint}>
          {props.report.available
            ? `${props.report.market || '--'} / ${props.report.symbol || '--'} · ${shortTime(props.report.generated_at)}`
            : props.report.report_path}
        </p>
      </div>
      <button style={styles.fullWidthButtonInline} type="button" onClick={props.onRefresh}>
        刷新报告
      </button>
      {props.report.steps.length > 0 && (
        <div style={styles.smokeStepList}>
          {props.report.steps.slice(0, 8).map((step) => (
            <div style={styles.smokeStepRow} key={`${step.name}-${step.duration_ms}`}>
              <span style={{ ...styles.onboardingDot, ...smokeDotStyle(step.status) }} />
              <div>
                <div style={styles.statusRowHeader}>
                  <strong style={styles.statusName}>{step.name}</strong>
                  <span style={styles.smallMeta}>{step.duration_ms}ms</span>
                </div>
                <p style={styles.statusMessage}>{step.message || smokeStatusLabel(step.status)}</p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function smokeTone(status: SmokeWorkflowStatus): Tone {
  if (status === 'passed') return 'positive';
  if (status === 'missing') return 'warning';
  return 'negative';
}

function smokeStatusLabel(status: SmokeWorkflowStatus): string {
  if (status === 'passed') return '通过';
  if (status === 'missing') return '未运行';
  return '失败';
}

function smokeDotStyle(status: SmokeWorkflowStep['status']): React.CSSProperties {
  return status === 'passed' ? styles.onboardingDotComplete : styles.onboardingDotAction;
}

function onboardingTone(status: OnboardingStepStatus): Tone {
  if (status === 'complete') return 'positive';
  if (status === 'warning') return 'warning';
  return 'negative';
}

function onboardingStatusLabel(status: OnboardingStepStatus): string {
  if (status === 'complete') return '已完成';
  if (status === 'warning') return '可优化';
  return '待操作';
}

function onboardingDotStyle(status: OnboardingStepStatus): React.CSSProperties {
  if (status === 'complete') return styles.onboardingDotComplete;
  if (status === 'warning') return styles.onboardingDotWarning;
  return styles.onboardingDotAction;
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
  syncCard: {
    display: 'grid',
    gap: 8,
    marginTop: 8,
    padding: 10,
    border: '1px solid #e3eae6',
    borderRadius: 8,
    background: '#fbfcfb',
  } as React.CSSProperties,
  syncTopLine: {
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 8,
  } as React.CSSProperties,
  syncMetrics: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr 1fr',
    gap: 8,
  } as React.CSSProperties,
  syncEventList: {
    display: 'grid',
    gap: 2,
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
  secondaryButton: {
    padding: '9px 12px',
    border: '1px solid #cdd8d3',
    borderRadius: 8,
    background: '#ffffff',
    color: '#174a3a',
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
  strategyWorkshop: {
    marginTop: 14,
    padding: 14,
    border: '1px solid #dfe8e3',
    borderRadius: 8,
    background: '#ffffff',
  } as React.CSSProperties,
  strategyWorkshopGrid: {
    display: 'grid',
    gridTemplateColumns: 'minmax(340px, 1.4fr) minmax(260px, 0.8fr)',
    gap: 12,
    marginTop: 12,
  } as React.CSSProperties,
  blocklySurface: {
    height: 360,
    minHeight: 320,
    border: '1px solid #d8e2dc',
    borderRadius: 8,
    overflow: 'hidden',
    background: '#f7faf8',
  } as React.CSSProperties,
  strategyFormPanel: {
    display: 'grid',
    alignContent: 'start',
    gap: 10,
  } as React.CSSProperties,
  stackField: {
    display: 'grid',
    gap: 6,
    color: '#4f6259',
    fontSize: 12,
    fontWeight: 800,
  } as React.CSSProperties,
  twoColumnControls: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)',
    gap: 10,
  } as React.CSSProperties,
  checkboxGrid: {
    display: 'grid',
    gap: 8,
    padding: 10,
    border: '1px solid #e1e8e4',
    borderRadius: 8,
    background: '#f8faf9',
  } as React.CSSProperties,
  strategyActions: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 8,
  } as React.CSSProperties,
  validationBox: {
    padding: 10,
    border: '1px solid #e1e8e4',
    borderRadius: 8,
    background: '#fbfcfb',
  } as React.CSSProperties,
  workspaceDraftList: {
    display: 'grid',
    gap: 8,
    padding: 10,
    border: '1px solid #e1e8e4',
    borderRadius: 8,
    background: '#fbfcfb',
  } as React.CSSProperties,
  workspaceDraftRow: {
    display: 'grid',
    gridTemplateColumns: 'minmax(0, 1fr) auto',
    alignItems: 'center',
    gap: 8,
    paddingTop: 8,
    borderTop: '1px solid #e5ebe8',
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
  chatCitations: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 6,
    marginTop: 8,
  } as React.CSSProperties,
  chatCitation: {
    padding: '4px 6px',
    borderRadius: 6,
    background: '#e3ebe6',
    color: '#4f6259',
    fontSize: 11,
    fontWeight: 700,
  } as React.CSSProperties,
  chatSuggestions: {
    display: 'grid',
    gap: 5,
    marginTop: 8,
  } as React.CSSProperties,
  chatSuggestion: {
    padding: '5px 7px',
    borderLeft: '3px solid #9db7aa',
    background: '#fbfcfb',
    color: '#41524a',
    fontSize: 12,
    lineHeight: 1.4,
  } as React.CSSProperties,
  assistantForm: {
    display: 'grid',
    gap: 8,
    marginTop: 12,
  } as React.CSSProperties,
  assistantInput: {
    width: '100%',
    minHeight: 72,
    boxSizing: 'border-box',
    resize: 'vertical',
    border: '1px solid #d8e2dc',
    borderRadius: 8,
    padding: 10,
    color: '#1f2f28',
    background: '#ffffff',
    fontSize: 13,
    lineHeight: 1.45,
    outline: 'none',
  } as React.CSSProperties,
  assistantActions: {
    display: 'flex',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    gap: 8,
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
  configGuide: {
    marginTop: 10,
    padding: '2px 0 2px 10px',
    borderLeft: '3px solid #d6a23d',
  } as React.CSSProperties,
  configGuideTone: {
    positive: {
      borderLeftColor: '#45a46f',
    } as React.CSSProperties,
    warning: {
      borderLeftColor: '#d6a23d',
    } as React.CSSProperties,
    negative: {
      borderLeftColor: '#c6503c',
    } as React.CSSProperties,
    neutral: {
      borderLeftColor: '#7391c8',
    } as React.CSSProperties,
  },
  configGuideHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  } as React.CSSProperties,
  configSignalRow: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 6,
    marginTop: 8,
  } as React.CSSProperties,
  configStepList: {
    display: 'grid',
    gap: 5,
    marginTop: 9,
  } as React.CSSProperties,
  configStep: {
    color: '#40534a',
    fontSize: 12,
    lineHeight: 1.45,
    overflowWrap: 'anywhere',
  } as React.CSSProperties,
  configKeyList: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 5,
    marginTop: 8,
  } as React.CSSProperties,
  configKeyPill: {
    padding: '4px 6px',
    borderRadius: 6,
    background: '#eef2ef',
    color: '#40534a',
    fontFamily: 'Consolas, "SFMono-Regular", monospace',
    fontSize: 11,
    fontWeight: 800,
    overflowWrap: 'anywhere',
  } as React.CSSProperties,
  localConfigBox: {
    marginTop: 12,
    paddingTop: 10,
    borderTop: '1px solid #e5ebe8',
  } as React.CSSProperties,
  localConfigActions: {
    display: 'flex',
    gap: 10,
    marginTop: 4,
  } as React.CSSProperties,
  localConfigForm: {
    display: 'grid',
    gap: 10,
    marginTop: 10,
  } as React.CSSProperties,
  configField: {
    display: 'grid',
    gap: 5,
  } as React.CSSProperties,
  configFieldTopLine: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  } as React.CSSProperties,
  configFieldLabel: {
    minWidth: 0,
    color: '#26362f',
    fontSize: 12,
    fontWeight: 800,
    lineHeight: 1.35,
  } as React.CSSProperties,
  configInput: {
    width: '100%',
    boxSizing: 'border-box',
    border: '1px solid #d8e2dc',
    borderRadius: 8,
    padding: '8px 9px',
    color: '#1f2f28',
    background: '#ffffff',
    fontSize: 12,
    outline: 'none',
  } as React.CSSProperties,
  configHint: {
    color: '#65786f',
    fontSize: 11,
    lineHeight: 1.4,
    overflowWrap: 'anywhere',
  } as React.CSSProperties,
  configPath: {
    margin: '6px 0 0',
    padding: '6px 7px',
    borderRadius: 6,
    background: '#eef2ef',
    color: '#40534a',
    fontFamily: 'Consolas, "SFMono-Regular", monospace',
    fontSize: 11,
    lineHeight: 1.4,
    overflowWrap: 'anywhere',
  } as React.CSSProperties,
  onboardingBox: {
    display: 'grid',
    gap: 10,
  } as React.CSSProperties,
  onboardingProgress: {
    display: 'grid',
    gap: 4,
    padding: '8px 0',
    color: '#30433b',
    fontSize: 12,
  } as React.CSSProperties,
  onboardingPrimaryAction: {
    width: '100%',
    padding: '8px 10px',
    border: 0,
    borderRadius: 8,
    background: '#174a3a',
    color: '#ffffff',
    cursor: 'pointer',
    fontSize: 12,
    fontWeight: 800,
    overflowWrap: 'anywhere',
  } as React.CSSProperties,
  onboardingInlineAction: {
    marginTop: 6,
    padding: '6px 8px',
    border: '1px solid #cdd8d3',
    borderRadius: 8,
    background: '#ffffff',
    color: '#174a3a',
    cursor: 'pointer',
    fontSize: 12,
    fontWeight: 800,
    overflowWrap: 'anywhere',
  } as React.CSSProperties,
  onboardingStepList: {
    display: 'grid',
    gap: 9,
  } as React.CSSProperties,
  smokeStepList: {
    display: 'grid',
    gap: 8,
    paddingTop: 8,
    borderTop: '1px solid #e5ebe8',
  } as React.CSSProperties,
  smokeStepRow: {
    display: 'grid',
    gridTemplateColumns: '12px minmax(0, 1fr)',
    gap: 8,
    alignItems: 'start',
  } as React.CSSProperties,
  onboardingStep: {
    display: 'grid',
    gridTemplateColumns: '12px minmax(0, 1fr)',
    gap: 8,
    alignItems: 'start',
    paddingTop: 9,
    borderTop: '1px solid #e5ebe8',
  } as React.CSSProperties,
  onboardingDot: {
    width: 9,
    height: 9,
    borderRadius: 999,
    marginTop: 5,
  } as React.CSSProperties,
  onboardingDotComplete: {
    background: '#45a46f',
  } as React.CSSProperties,
  onboardingDotWarning: {
    background: '#d6a23d',
  } as React.CSSProperties,
  onboardingDotAction: {
    background: '#c6503c',
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
  auditList: {
    display: 'grid',
    gap: 8,
    marginTop: 12,
    paddingTop: 10,
    borderTop: '1px solid #e5ebe8',
  } as React.CSSProperties,
  auditHeaderLine: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  } as React.CSSProperties,
  auditRow: {
    padding: '8px 0',
    borderTop: '1px solid #edf2ef',
  } as React.CSSProperties,
  auditSummary: {
    margin: '5px 0 0',
    color: '#30433b',
    fontSize: 12,
    lineHeight: 1.45,
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
