import type { FormEvent } from 'react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import './App.css'

const API_BASE = import.meta.env.VITE_DUBHE_CORE_URL ?? 'http://127.0.0.1:8000'
const DEVICE_SESSION_STORAGE_KEY = 'dubhe.deviceSession'
const DEFAULT_PAPER_ACCOUNT_ID = 'demo_account'

let deviceAccessToken: string | null = null
let logSequence = 0

type Market = 'A_SHARE' | 'HK' | 'US' | 'GLOBAL'
type DevicePlatform = 'windows' | 'macos' | 'ios' | 'android'
type RiskStatus = 'approved' | 'requires_approval' | 'rejected'
type Sentiment = 'positive' | 'neutral' | 'negative'
type UserRole = 'user' | 'risk_manager' | 'admin'

type NewsAnalysis = {
  id: string
  news_event_id: string
  summary_zh: string
  sentiment: Sentiment
  impact_score: number
  affected_tickers: string[]
  source_refs: string[]
  confidence: number
  generated_at: string
}

type NewsEvent = {
  id: string
  provider: string
  provider_event_id?: string | null
  source_name: string
  market_scope: Market[]
  language: string
  title_original: string
  title_zh?: string | null
  published_at: string
  received_at?: string
  url?: string | null
  tickers: string[]
  entities: string[]
  event_type: string
  authority_score: number
  duplicate_group_id?: string | null
  license_flags: string[]
}

type NewsProviderStatus = {
  provider: string
  status: 'ok' | 'skipped' | 'unavailable'
  fetched_count: number
  message_zh: string
}

type NewsFeedResponse = {
  events: NewsEvent[]
  provider_status: NewsProviderStatus[]
  generated_at: string
}

type RiskDecision = {
  id: string
  order_intent_id: string
  status: RiskStatus
  allowed_destination: 'none' | 'paper' | 'live_after_approval'
  notional: number
  reasons_zh: string[]
  evaluated_at: string
}

type ApprovalRequest = {
  id: string
  order_intent_id: string
  risk_decision: RiskDecision
  status: 'pending' | 'approved' | 'rejected'
  requested_by: 'ai' | 'strategy' | 'user'
  decided_by?: string | null
  decision_comment_zh?: string | null
  created_at: string
  decided_at?: string | null
  message_zh: string
}

type KillSwitchState = {
  enabled: boolean
  reason_zh: string
  updated_by: string
  updated_at: string
}

type BrokerFill = {
  id: string
  broker_order_id: string
  symbol: string
  side: 'buy' | 'sell'
  quantity: number
  price: number
  notional: number
  commission: number
  filled_at: string
}

type BrokerOrder = {
  id: string
  paper_order_id: string
  order_intent_id: string
  adapter: string
  broker_account_id: string
  market: Market
  symbol: string
  side: 'buy' | 'sell'
  quantity: number
  currency: string
  status: 'accepted' | 'filled' | 'rejected' | 'canceled'
  filled_quantity: number
  avg_fill_price?: number | null
  submitted_at: string
  updated_at: string
  fills: BrokerFill[]
  message_zh: string
  raw_response: Record<string, unknown>
}

type PaperOrder = {
  id: string
  order_intent_id: string
  status: 'accepted' | 'blocked'
  risk_decision: RiskDecision
  broker_order?: BrokerOrder | null
  message_zh: string
  submitted_at: string
}

type PaperPortfolioPosition = {
  market: Market
  symbol: string
  currency: string
  quantity: number
  avg_cost: number
  last_price: number
  market_value: number
  unrealized_pnl: number
  updated_at: string
}

type PaperPortfolioSnapshot = {
  account_id: string
  cash_by_currency: Record<string, number>
  equity_by_currency: Record<string, number>
  realized_pnl_by_currency: Record<string, number>
  positions: PaperPortfolioPosition[]
  updated_at: string
}

type StrategySpec = {
  strategy_name: string
  market_scope: Market[]
  asset_universe: string[]
  entry_rules: string[]
  exit_rules: string[]
  risk_limits: Record<string, number>
  timeframe: string
  rebalance_rule: string
  data_dependencies: string[]
  broker_permissions: string[]
}

type StrategyDraft = {
  id: string
  strategy_version_id: string
  name: string
  spec: StrategySpec
  explanation_zh: string
  generated_code: string
  source_analysis_id: string
  created_at: string
}

type BacktestPoint = {
  date: string
  equity: number
  benchmark: number
}

type BacktestResult = {
  id: string
  strategy_version_id: string
  replay_scenario: string
  symbol: string
  market: Market
  initial_cash: number
  final_equity: number
  total_return: number
  benchmark_return: number
  max_drawdown: number
  win_rate: number
  trade_count: number
  risk_notes_zh: string[]
  equity_curve: BacktestPoint[]
  generated_at: string
}

type DeviceSession = {
  user_id: string
  device_id: string
  workspace_id: string
  access_token: string
  role: UserRole
  platform: DevicePlatform
  device_name: string
  created_at: string
}

type UserSummary = {
  id: string
  account_key: string
  display_name: string
  role: UserRole
  mfa_enabled: boolean
  created_at: string
}

type AuditLogEntry = {
  id: string
  actor_user_id?: string | null
  actor_device_id?: string | null
  actor_role?: UserRole | null
  action: string
  target_type: string
  target_id?: string | null
  summary_zh: string
  metadata: Record<string, unknown>
  created_at: string
}

type SyncedWatchlistItem = {
  id: string
  workspace_id: string
  symbol: string
  name: string
  market: Market
  notes_zh?: string | null
  added_at: string
  updated_at: string
}

type WorkspaceSnapshot = {
  workspace: {
    id: string
    owner_user_id: string
    name: string
    created_at: string
    updated_at: string
  }
  watchlist: SyncedWatchlistItem[]
  news_events: NewsEvent[]
  broker_orders: BrokerOrder[]
  paper_portfolios: PaperPortfolioSnapshot[]
  server_sequence: number
}

type SyncEvent = {
  id: string
  workspace_id: string
  sequence: number
  entity_type:
    | 'workspace'
    | 'watchlist_item'
    | 'news_event'
    | 'news_analysis'
    | 'strategy_draft'
    | 'backtest_result'
    | 'risk_decision'
    | 'approval_request'
    | 'kill_switch'
    | 'paper_order'
    | 'broker_order'
    | 'paper_portfolio'
  entity_id: string
  action: 'created' | 'updated' | 'deleted'
  payload: Record<string, unknown>
  created_at: string
}

type WatchRow = {
  symbol: string
  name: string
  market: Market
  move: string
  notes_zh?: string | null
}

type LogEntry = {
  id: string
  time: string
  kind: 'info' | 'success' | 'warning' | 'danger'
  message: string
}

type AuthMode = 'register' | 'login'

type AuthForm = {
  account_key: string
  account_name: string
  password: string
  mfa_code: string
}

const navItems = [
  ['今日市场', '今'],
  ['新闻雷达', '新'],
  ['AI 分析师', '智'],
  ['策略工坊', '策'],
  ['回测中心', '回'],
  ['模拟交易', '模'],
  ['数据源', '源'],
  ['风控中心', '控'],
] as const

const roleOptions: UserRole[] = ['user', 'risk_manager', 'admin']

const fallbackWatchlist: WatchRow[] = [
  { symbol: 'NVDA', name: '英伟达', market: 'US', move: '+2.8%' },
  { symbol: '0700.HK', name: '腾讯控股', market: 'HK', move: '-0.4%' },
  { symbol: '600519.SH', name: '贵州茅台', market: 'A_SHARE', move: '+0.6%' },
  { symbol: 'AAPL', name: '苹果', market: 'US', move: '+1.1%' },
]

const demoMoves: Record<string, string> = {
  NVDA: '+2.8%',
  '0700.HK': '-0.4%',
  '600519.SH': '+0.6%',
  AAPL: '+1.1%',
}

const fallbackAnalysis: NewsAnalysis = {
  id: 'analysis_local_demo',
  news_event_id: 'news_local_demo',
  summary_zh: '这条来自测试新闻源的消息显示：英伟达业绩超预期并宣布回购。',
  sentiment: 'positive',
  impact_score: 0.825,
  affected_tickers: ['NVDA'],
  source_refs: ['本地演示数据'],
  confidence: 0.845,
  generated_at: new Date().toISOString(),
}

const fallbackNewsEvent: NewsEvent = {
  id: 'news_local_demo',
  provider: 'fixture',
  provider_event_id: 'desktop-news-001',
  source_name: '本地演示新闻源',
  market_scope: ['US'],
  language: 'zh-CN',
  title_original: '英伟达业绩超预期并宣布回购',
  title_zh: '英伟达业绩超预期并宣布回购',
  published_at: new Date().toISOString(),
  url: 'https://example.com/news/desktop-news-001',
  tickers: ['NVDA'],
  entities: ['英伟达'],
  event_type: 'earnings',
  authority_score: 0.75,
  license_flags: ['fixture'],
}

function nowTime() {
  return new Intl.DateTimeFormat('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date())
}

function createLogEntry(kind: LogEntry['kind'], message: string): LogEntry {
  logSequence += 1
  return {
    id: `log_${Date.now()}_${logSequence}`,
    time: nowTime(),
    kind,
    message,
  }
}

function sentimentLabel(sentiment: Sentiment) {
  if (sentiment === 'positive') return '正面'
  if (sentiment === 'negative') return '负面'
  return '中性'
}

function percentLabel(value: number) {
  return `${(value * 100).toFixed(2)}%`
}

function moneyLabel(currency: string, value: number) {
  try {
    return new Intl.NumberFormat('zh-CN', {
      currency,
      maximumFractionDigits: 2,
      style: 'currency',
    }).format(value)
  } catch {
    return `${currency} ${value.toLocaleString('zh-CN')}`
  }
}

function roleLabel(role: UserRole) {
  if (role === 'admin') return '管理员'
  if (role === 'risk_manager') return '风控管理员'
  return '普通用户'
}

function roleShortLabel(role: UserRole) {
  if (role === 'admin') return '管理员'
  if (role === 'risk_manager') return '风控'
  return '普通'
}

function formatShortDateTime(value: string) {
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

function readStoredSession() {
  try {
    const raw = localStorage.getItem(DEVICE_SESSION_STORAGE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as DeviceSession
    const session = { ...parsed, role: parsed.role ?? 'user' }
    deviceAccessToken = session.access_token
    return session
  } catch {
    localStorage.removeItem(DEVICE_SESSION_STORAGE_KEY)
    return null
  }
}

function authHeaders(headers: Record<string, string> = {}) {
  if (!deviceAccessToken) return headers
  return { ...headers, Authorization: `Bearer ${deviceAccessToken}` }
}

async function postJson<T>(path: string, body: unknown): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: authHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`${response.status} ${text}`)
  }

  return response.json() as Promise<T>
}

async function getJson<T>(path: string): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: authHeaders(),
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`${response.status} ${text}`)
  }

  return response.json() as Promise<T>
}

function detectPlatform(): DevicePlatform {
  const userAgent = navigator.userAgent.toLowerCase()
  const platform = navigator.platform.toLowerCase()
  if (userAgent.includes('android')) return 'android'
  if (userAgent.includes('iphone') || userAgent.includes('ipad')) return 'ios'
  if (platform.includes('mac')) return 'macos'
  return 'windows'
}

function marketLabel(market: Market) {
  if (market === 'A_SHARE') return 'A 股'
  if (market === 'HK') return '港股'
  if (market === 'US') return '美股'
  return '全球'
}

function syncEntityLabel(entityType: SyncEvent['entity_type']) {
  if (entityType === 'watchlist_item') return '自选股'
  if (entityType === 'approval_request') return '审批请求'
  if (entityType === 'kill_switch') return '急停状态'
  if (entityType === 'risk_decision') return '风控结果'
  if (entityType === 'paper_order') return '纸面订单'
  if (entityType === 'broker_order') return '模拟券商回报'
  if (entityType === 'paper_portfolio') return '纸面组合'
  if (entityType === 'backtest_result') return '回测结果'
  if (entityType === 'strategy_draft') return '策略草案'
  if (entityType === 'news_event') return '新闻事件'
  if (entityType === 'news_analysis') return 'AI 分析'
  return '工作区'
}

function syncSocketUrl(workspaceId: string, sinceSequence: number) {
  const url = new URL(API_BASE)
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
  url.pathname = `/v1/workspaces/${workspaceId}/sync-events/ws`
  url.search = new URLSearchParams({
    access_token: deviceAccessToken ?? '',
    since_sequence: String(sinceSequence),
  }).toString()
  return url.toString()
}

function Icon({ label }: { label: string }) {
  return <span className="icon-glyph" aria-hidden="true">{label}</span>
}

function App() {
  const [deviceSession, setDeviceSession] = useState<DeviceSession | null>(() => readStoredSession())
  const [authMode, setAuthMode] = useState<AuthMode>('register')
  const [authForm, setAuthForm] = useState<AuthForm>({
    account_key: 'local-demo',
    account_name: '本地演示账户',
    password: 'Dubhe@2026',
    mfa_code: '000000',
  })
  const [authError, setAuthError] = useState<string | null>(null)
  const [isAuthenticating, setAuthenticating] = useState(false)
  const [activeNav, setActiveNav] = useState('新闻雷达')
  const [selectedTicker, setSelectedTicker] = useState('NVDA')
  const [watchlistItems, setWatchlistItems] = useState<WatchRow[]>(fallbackWatchlist)
  const [workspaceName, setWorkspaceName] = useState('本地演示工作区')
  const [syncSequence, setSyncSequence] = useState(0)
  const [newsEvents, setNewsEvents] = useState<NewsEvent[]>([fallbackNewsEvent])
  const [selectedNewsId, setSelectedNewsId] = useState(fallbackNewsEvent.id)
  const [providerStatus, setProviderStatus] = useState<NewsProviderStatus[]>([])
  const [analysis, setAnalysis] = useState<NewsAnalysis>(fallbackAnalysis)
  const [strategyDraft, setStrategyDraft] = useState<StrategyDraft | null>(null)
  const [backtestResult, setBacktestResult] = useState<BacktestResult | null>(null)
  const [riskDecision, setRiskDecision] = useState<RiskDecision | null>(null)
  const [approvalRequests, setApprovalRequests] = useState<ApprovalRequest[]>([])
  const [killSwitch, setKillSwitch] = useState<KillSwitchState | null>(null)
  const [adminUsers, setAdminUsers] = useState<UserSummary[]>([])
  const [auditLogs, setAuditLogs] = useState<AuditLogEntry[]>([])
  const [paperOrder, setPaperOrder] = useState<PaperOrder | null>(null)
  const [brokerOrder, setBrokerOrder] = useState<BrokerOrder | null>(null)
  const [paperPortfolio, setPaperPortfolio] = useState<PaperPortfolioSnapshot | null>(null)
  const [isBusy, setBusy] = useState(false)
  const [apiStatus, setApiStatus] = useState<'未知' | '已连接' | '离线'>('未知')
  const [syncSocketStatus, setSyncSocketStatus] = useState<'未连接' | '已连接' | '离线'>('未连接')
  const [logs, setLogs] = useState<LogEntry[]>([
    createLogEntry('info', '工作台已载入，可连接 Dubhe Core。'),
    createLogEntry('warning', '实盘交易关闭：所有真实订单必须先通过风控与人工审批。'),
  ])

  const tickerContext = useMemo(
    () => watchlistItems.find((item) => item.symbol === selectedTicker) ?? watchlistItems[0] ?? fallbackWatchlist[0],
    [selectedTicker, watchlistItems],
  )

  const selectedNews = useMemo(
    () =>
      newsEvents.find((event) => event.id === selectedNewsId) ??
      newsEvents.find((event) => event.tickers.includes(selectedTicker)) ??
      fallbackNewsEvent,
    [newsEvents, selectedNewsId, selectedTicker],
  )
  const canManageRisk = deviceSession?.role === 'admin' || deviceSession?.role === 'risk_manager'
  const canManageAdmin = deviceSession?.role === 'admin'

  function appendLog(kind: LogEntry['kind'], message: string) {
    setLogs((current) => [createLogEntry(kind, message), ...current].slice(0, 4))
  }

  function updateAuthField(field: keyof AuthForm, value: string) {
    setAuthForm((current) => ({ ...current, [field]: value }))
  }

  async function submitAuth(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setAuthenticating(true)
    setAuthError(null)
    try {
      const payload = {
        ...authForm,
        device_name: navigator.platform || 'Dubhe Desktop',
        platform: detectPlatform(),
      }
      const session = await postJson<DeviceSession>(
        authMode === 'register' ? '/v1/auth/accounts/register' : '/v1/auth/login',
        authMode === 'register' ? payload : {
          account_key: payload.account_key,
          password: payload.password,
          mfa_code: payload.mfa_code,
          device_name: payload.device_name,
          platform: payload.platform,
        },
      )
      deviceAccessToken = session.access_token
      localStorage.setItem(DEVICE_SESSION_STORAGE_KEY, JSON.stringify(session))
      setDeviceSession(session)
      appendLog('success', `已登录：${roleLabel(session.role)}。`)
    } catch (error) {
      setAuthError(error instanceof Error ? error.message : '登录失败，请稍后重试。')
    } finally {
      setAuthenticating(false)
    }
  }

  async function signOut() {
    try {
      await postJson('/v1/auth/devices/current/revoke', {})
    } catch {
      // 本地退出优先，服务端撤销失败时也清理本机令牌。
    }
    deviceAccessToken = null
    localStorage.removeItem(DEVICE_SESSION_STORAGE_KEY)
    setDeviceSession(null)
    setApiStatus('未知')
    setSyncSocketStatus('未连接')
    setAdminUsers([])
    setAuditLogs([])
    appendLog('warning', '已退出当前设备。')
  }

  const refreshSafetyState = useCallback(async () => {
    const [approvals, killSwitchState] = await Promise.all([
      getJson<ApprovalRequest[]>('/v1/approvals'),
      getJson<KillSwitchState>('/v1/risk/kill-switch'),
    ])
    setApprovalRequests(approvals)
    setKillSwitch(killSwitchState)
    return { approvals, killSwitchState }
  }, [])

  const refreshGovernanceState = useCallback(async () => {
    const [users, audits] = await Promise.all([
      canManageAdmin ? getJson<UserSummary[]>('/v1/admin/users') : Promise.resolve([]),
      canManageRisk ? getJson<AuditLogEntry[]>('/v1/audit/logs?limit=6') : Promise.resolve([]),
    ])
    setAdminUsers(users)
    setAuditLogs(audits)
    return { users, audits }
  }, [canManageAdmin, canManageRisk])

  const refreshPaperPortfolio = useCallback(async () => {
    const portfolio = await getJson<PaperPortfolioSnapshot>(
      `/v1/simulation/paper-portfolio/${DEFAULT_PAPER_ACCOUNT_ID}`,
    )
    setPaperPortfolio(portfolio)
    return portfolio
  }, [])

  async function setUserRole(user: UserSummary, role: UserRole) {
    if (!canManageAdmin || user.role === role) return
    setBusy(true)
    try {
      const updatedUser = await postJson<UserSummary>(`/v1/admin/users/${user.id}/role`, {
        role,
        reason_zh: `桌面端管理员将 ${user.account_key} 调整为${roleLabel(role)}。`,
      })
      setAdminUsers((current) => current.map((item) => (item.id === updatedUser.id ? updatedUser : item)))
      if (deviceSession?.user_id === updatedUser.id) {
        const updatedSession = { ...deviceSession, role: updatedUser.role }
        deviceAccessToken = updatedSession.access_token
        localStorage.setItem(DEVICE_SESSION_STORAGE_KEY, JSON.stringify(updatedSession))
        setDeviceSession(updatedSession)
        setAdminUsers([])
        setAuditLogs(
          updatedUser.role === 'admin' || updatedUser.role === 'risk_manager'
            ? await getJson<AuditLogEntry[]>('/v1/audit/logs?limit=6')
            : [],
        )
      } else {
        await refreshGovernanceState()
      }
      appendLog('success', `已更新 ${updatedUser.account_key} 的角色：${roleLabel(updatedUser.role)}。`)
    } catch (error) {
      appendLog('danger', `角色更新失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  function applySyncEvent(event: SyncEvent) {
    setSyncSequence((current) => Math.max(current, event.sequence))

    if (event.entity_type === 'approval_request') {
      const approval = event.payload as unknown as ApprovalRequest
      setApprovalRequests((current) => [approval, ...current.filter((item) => item.id !== approval.id)])
    }

    if (event.entity_type === 'kill_switch') {
      setKillSwitch(event.payload as unknown as KillSwitchState)
    }

    if (event.entity_type === 'watchlist_item') {
      const item = event.payload as unknown as SyncedWatchlistItem
      setWatchlistItems((current) => {
        const row: WatchRow = {
          symbol: item.symbol,
          name: item.name,
          market: item.market,
          move: demoMoves[item.symbol] ?? '0.0%',
          notes_zh: item.notes_zh,
        }
        return [row, ...current.filter((existing) => existing.symbol !== row.symbol)]
      })
    }

    if (event.entity_type === 'broker_order') {
      setBrokerOrder(event.payload as unknown as BrokerOrder)
    }

    if (event.entity_type === 'paper_portfolio') {
      setPaperPortfolio(event.payload as unknown as PaperPortfolioSnapshot)
    }

    if (!['news_event', 'news_analysis'].includes(event.entity_type)) {
      appendLog('info', `实时同步：${syncEntityLabel(event.entity_type)} ${event.action}。`)
    }
  }

  function newsFeedPath(item: WatchRow) {
    const params = new URLSearchParams({
      market: item.market,
      symbol: item.symbol,
      limit: '8',
      live: 'true',
    })
    return `/v1/news/feed?${params.toString()}`
  }

  async function loadNewsFeed(item: WatchRow) {
    const feed = await getJson<NewsFeedResponse>(newsFeedPath(item))
    setNewsEvents(feed.events.length > 0 ? feed.events : [fallbackNewsEvent])
    setProviderStatus(feed.provider_status)
    setSelectedNewsId(feed.events[0]?.id ?? fallbackNewsEvent.id)
    return feed
  }

  async function refreshNewsFeed() {
    setBusy(true)
    try {
      const feed = await loadNewsFeed(tickerContext)
      setApiStatus('已连接')
      appendLog('success', `新闻源刷新完成：${feed.events.length} 条，${feed.provider_status.length} 个来源状态。`)
    } catch (error) {
      setApiStatus('离线')
      appendLog('danger', `新闻源刷新失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  useEffect(() => {
    if (!deviceSession) return
    const session = deviceSession
    let cancelled = false
    let syncSocket: WebSocket | null = null

    async function connectWorkspaceSync() {
      try {
        deviceAccessToken = session.access_token
        const snapshot = await getJson<WorkspaceSnapshot>(`/v1/workspaces/${session.workspace_id}/snapshot`)

        if (cancelled) return

        const syncedWatchlist = snapshot.watchlist.map((item) => ({
          symbol: item.symbol,
          name: item.name,
          market: item.market,
          move: demoMoves[item.symbol] ?? '0.0%',
          notes_zh: item.notes_zh,
        }))

        setWorkspaceName(snapshot.workspace.name)
        setSyncSequence(snapshot.server_sequence)
        if (snapshot.news_events.length > 0) {
          setNewsEvents(snapshot.news_events)
          setSelectedNewsId(snapshot.news_events[0].id)
        }
        if (snapshot.broker_orders.length > 0) {
          setBrokerOrder(snapshot.broker_orders[0])
        }
        if (snapshot.paper_portfolios.length > 0) {
          setPaperPortfolio(snapshot.paper_portfolios[0])
        }
        if (syncedWatchlist.length > 0) {
          setWatchlistItems(syncedWatchlist)
          const activeSymbol = syncedWatchlist.some((item) => item.symbol === fallbackWatchlist[0].symbol)
            ? fallbackWatchlist[0].symbol
            : syncedWatchlist[0].symbol
          setSelectedTicker(activeSymbol)
        }
        const activeSymbol = syncedWatchlist.some((item) => item.symbol === fallbackWatchlist[0].symbol)
          ? fallbackWatchlist[0].symbol
          : syncedWatchlist[0]?.symbol
        const activeTicker =
          syncedWatchlist.find((item) => item.symbol === activeSymbol) ?? syncedWatchlist[0] ?? fallbackWatchlist[0]
        const feed = await getJson<NewsFeedResponse>(newsFeedPath(activeTicker))
        if (cancelled) return
        setNewsEvents(feed.events.length > 0 ? feed.events : [fallbackNewsEvent])
        setProviderStatus(feed.provider_status)
        setSelectedNewsId(feed.events[0]?.id ?? fallbackNewsEvent.id)
        await refreshPaperPortfolio()
        if (canManageRisk) {
          await refreshSafetyState()
          await refreshGovernanceState()
        } else {
          setApprovalRequests([])
          setKillSwitch(null)
          setAdminUsers([])
          setAuditLogs([])
        }
        if (cancelled) return
        syncSocket = new WebSocket(syncSocketUrl(session.workspace_id, snapshot.server_sequence))
        syncSocket.onopen = () => {
          setSyncSocketStatus('已连接')
          appendLog('success', '实时同步已连接。')
        }
        syncSocket.onmessage = (message) => {
          applySyncEvent(JSON.parse(message.data) as SyncEvent)
        }
        syncSocket.onclose = () => {
          setSyncSocketStatus('离线')
          appendLog('warning', '实时同步已断开。')
        }
        setApiStatus('已连接')
        appendLog(
          'success',
          `同步快照已加载：${snapshot.watchlist.length} 个自选标的；新闻源 ${feed.events.length} 条。`,
        )
      } catch (error) {
        if (cancelled) return
        setApiStatus('离线')
        appendLog('danger', `同步服务不可用：${error instanceof Error ? error.message : '未知错误'}。`)
      }
    }

    void connectWorkspaceSync()

    return () => {
      cancelled = true
      syncSocket?.close()
    }
  }, [canManageRisk, deviceSession, refreshGovernanceState, refreshPaperPortfolio, refreshSafetyState])

  async function runNewsAnalysis() {
    setBusy(true)
    try {
      const event = {
        ...selectedNews,
        market_scope: selectedNews.market_scope.length > 0 ? selectedNews.market_scope : [tickerContext.market],
        tickers: selectedNews.tickers.length > 0 ? selectedNews.tickers : [selectedTicker],
        entities: selectedNews.entities.length > 0 ? selectedNews.entities : [tickerContext.name],
      }
      const result = await postJson<NewsAnalysis>('/v1/news/analyze', event)
      setAnalysis(result)
      setApiStatus('已连接')
      appendLog('success', `新闻分析完成：${result.affected_tickers.join('、')} 影响分 ${Math.round(result.impact_score * 100)}。`)
    } catch (error) {
      setApiStatus('离线')
      appendLog('danger', `Core API 不可用：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  async function draftStrategy() {
    setBusy(true)
    try {
      const draft = await postJson<StrategyDraft>('/v1/strategy/drafts/from-analysis', {
        analysis,
        symbol: selectedTicker,
        market: tickerContext.market,
        max_order_notional: 10000,
      })
      setStrategyDraft(draft)
      setBacktestResult(null)
      setApiStatus('已连接')
      appendLog('success', `策略草案已生成：${draft.name}。`)
    } catch (error) {
      setApiStatus('离线')
      appendLog('danger', `策略草案生成失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  async function runReplayBacktest() {
    if (!strategyDraft) {
      appendLog('warning', '请先生成策略草案，再运行回测。')
      return
    }

    setBusy(true)
    try {
      const result = await postJson<BacktestResult>('/v1/backtests/replay', {
        strategy: strategyDraft,
        initial_cash: 100000,
        replay_scenario: 'golden_news_sentiment_v1',
      })
      setBacktestResult(result)
      setApiStatus('已连接')
      appendLog('success', `回测完成：收益 ${percentLabel(result.total_return)}，最大回撤 ${percentLabel(result.max_drawdown)}。`)
    } catch (error) {
      setApiStatus('离线')
      appendLog('danger', `回测失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  async function evaluateRisk() {
    setBusy(true)
    try {
      const result = await postJson<RiskDecision>('/v1/risk/evaluate', {
        account_id: DEFAULT_PAPER_ACCOUNT_ID,
        strategy_version_id: 'strategy_news_demo_v1',
        market: tickerContext.market,
        symbol: selectedTicker,
        side: 'buy',
        order_type: 'market',
        quantity: 1,
        estimated_price: selectedTicker === '0700.HK' ? 300 : 1000,
        currency: selectedTicker === '0700.HK' ? 'HKD' : 'USD',
        created_by: 'ai',
        destination: 'live',
        rationale_zh: '根据新闻分析生成的实盘订单意图，必须进入人工审批。',
        source_refs: [analysis.id],
      })
      setRiskDecision(result)
      if (canManageRisk) {
        await refreshSafetyState()
        await refreshGovernanceState()
      }
      setApiStatus('已连接')
      appendLog('warning', `风控完成：${result.status === 'requires_approval' ? '需要人工审批' : result.status}。`)
    } catch (error) {
      setApiStatus('离线')
      appendLog('danger', `风控评估失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  async function approveLatestRequest() {
    if (!canManageRisk) {
      appendLog('warning', '当前账号没有审批权限，请使用风控管理员或管理员账号。')
      return
    }
    const pending = approvalRequests.find((approval) => approval.status === 'pending')
    if (!pending) {
      appendLog('warning', '当前没有待审批请求。')
      return
    }

    setBusy(true)
    try {
      const approval = await postJson<ApprovalRequest>(`/v1/approvals/${pending.id}/approve`, {
        decided_by: 'desktop-risk-manager',
        decision_comment_zh: '桌面端演示审批通过，仅用于验证审批链路。',
      })
      await refreshSafetyState()
      await refreshGovernanceState()
      appendLog('success', `审批已通过：${approval.id}。`)
    } catch (error) {
      appendLog('danger', `审批失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  async function rejectLatestRequest() {
    if (!canManageRisk) {
      appendLog('warning', '当前账号没有审批权限，请使用风控管理员或管理员账号。')
      return
    }
    const pending = approvalRequests.find((approval) => approval.status === 'pending')
    if (!pending) {
      appendLog('warning', '当前没有待审批请求。')
      return
    }

    setBusy(true)
    try {
      const approval = await postJson<ApprovalRequest>(`/v1/approvals/${pending.id}/reject`, {
        decided_by: 'desktop-risk-manager',
        decision_comment_zh: '桌面端演示拒绝，高风险订单不进入实盘。',
      })
      await refreshSafetyState()
      await refreshGovernanceState()
      appendLog('warning', `审批已拒绝：${approval.id}。`)
    } catch (error) {
      appendLog('danger', `拒绝审批失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  async function toggleKillSwitch() {
    if (!canManageRisk) {
      appendLog('warning', '当前账号没有急停权限，请使用风控管理员或管理员账号。')
      return
    }
    setBusy(true)
    try {
      const nextEnabled = !killSwitch?.enabled
      const state = await postJson<KillSwitchState>('/v1/risk/kill-switch', {
        enabled: nextEnabled,
        reason_zh: nextEnabled ? '桌面端手动启用急停。' : '桌面端手动解除急停。',
        updated_by: 'desktop-risk-manager',
      })
      setKillSwitch(state)
      await refreshGovernanceState()
      appendLog(state.enabled ? 'danger' : 'success', state.enabled ? 'Kill switch 已启用。' : 'Kill switch 已解除。')
    } catch (error) {
      appendLog('danger', `Kill switch 更新失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  async function submitPaperOrder() {
    setBusy(true)
    try {
      const result = await postJson<PaperOrder>('/v1/simulation/paper-orders', {
        account_id: DEFAULT_PAPER_ACCOUNT_ID,
        strategy_version_id: 'strategy_news_demo_v1',
        market: tickerContext.market,
        symbol: selectedTicker,
        side: 'buy',
        order_type: 'market',
        quantity: 1,
        estimated_price: selectedTicker === '0700.HK' ? 300 : 1000,
        currency: selectedTicker === '0700.HK' ? 'HKD' : 'USD',
        created_by: 'strategy',
        destination: 'paper',
        rationale_zh: '将新闻情绪策略放入纸面交易验证。',
        source_refs: [analysis.id],
      })
      setPaperOrder(result)
      setBrokerOrder(result.broker_order ?? null)
      await refreshPaperPortfolio()
      if (canManageRisk) {
        await refreshGovernanceState()
      }
      setApiStatus('已连接')
      appendLog(result.status === 'accepted' ? 'success' : 'danger', result.message_zh)
    } catch (error) {
      setApiStatus('离线')
      appendLog('danger', `纸面订单失败：${error instanceof Error ? error.message : '未知错误'}。`)
    } finally {
      setBusy(false)
    }
  }

  if (!deviceSession) {
    return (
      <main className="login-shell">
        <section className="login-panel" aria-label="Dubhe 登录">
          <div className="login-brand">
            <div className="brand-mark">D</div>
            <div>
              <strong>Dubhe</strong>
              <span>AI 投资研究与受控量化工作台</span>
            </div>
          </div>
          <div className="auth-switch" role="tablist" aria-label="登录模式">
            <button
              className={authMode === 'register' ? 'is-active' : ''}
              type="button"
              onClick={() => setAuthMode('register')}
            >
              创建 / 接管账号
            </button>
            <button
              className={authMode === 'login' ? 'is-active' : ''}
              type="button"
              onClick={() => setAuthMode('login')}
            >
              登录
            </button>
          </div>
          <form className="login-form" onSubmit={submitAuth}>
            <label>
              账号
              <input
                value={authForm.account_key}
                onChange={(event) => updateAuthField('account_key', event.target.value)}
                autoComplete="username"
              />
            </label>
            {authMode === 'register' && (
              <label>
                显示名称
                <input
                  value={authForm.account_name}
                  onChange={(event) => updateAuthField('account_name', event.target.value)}
                  autoComplete="name"
                />
              </label>
            )}
            <label>
              密码
              <input
                type="password"
                value={authForm.password}
                onChange={(event) => updateAuthField('password', event.target.value)}
                autoComplete={authMode === 'register' ? 'new-password' : 'current-password'}
              />
            </label>
            <label>
              MFA 验证码
              <input
                value={authForm.mfa_code}
                onChange={(event) => updateAuthField('mfa_code', event.target.value)}
                inputMode="numeric"
                autoComplete="one-time-code"
              />
            </label>
            {authError && <p className="auth-error">{authError}</p>}
            <button className="login-submit" type="submit" disabled={isAuthenticating}>
              {isAuthenticating ? '正在进入...' : authMode === 'register' ? '创建并进入' : '登录工作台'}
            </button>
          </form>
          <p className="login-note">本地开发 MFA 默认码为 000000；生产环境需要替换为正式验证器或企业身份系统。</p>
        </section>
      </main>
    )
  }

  return (
    <main className="workspace-shell">
      <aside className="activity-rail" aria-label="主导航">
        <div className="brand-mark">D</div>
        {navItems.map(([label, glyph]) => (
          <button
            className={activeNav === label ? 'rail-button is-active' : 'rail-button'}
            key={label}
            type="button"
            title={label}
            aria-label={label}
            onClick={() => setActiveNav(label)}
          >
            {glyph}
          </button>
        ))}
      </aside>

      <aside className="left-sidebar">
        <header className="sidebar-header">
          <div>
            <strong>Dubhe</strong>
            <small>{workspaceName} · {roleLabel(deviceSession.role)}</small>
          </div>
          <button className={apiStatus === '已连接' ? 'status-dot online' : 'status-dot'} type="button" onClick={signOut}>
            {apiStatus}
          </button>
        </header>

        <section className="sidebar-section">
          <h2>自选列表</h2>
          <div className="watchlist">
            {watchlistItems.map((item) => (
              <button
                className={selectedTicker === item.symbol ? 'watch-row is-selected' : 'watch-row'}
                key={item.symbol}
                type="button"
                onClick={() => setSelectedTicker(item.symbol)}
              >
                <span>
                  <b>{item.symbol}</b>
                  <small>{item.name} · {marketLabel(item.market)}</small>
                </span>
                <span className={item.move.startsWith('+') ? 'move up' : 'move down'}>{item.move}</span>
              </button>
            ))}
          </div>
        </section>

        <section className="sidebar-section compact">
          <h2>新闻筛选器</h2>
          <label><input type="checkbox" defaultChecked /> 权威财经新闻</label>
          <label><input type="checkbox" defaultChecked /> 公告 / 财报</label>
          <label><input type="checkbox" defaultChecked /> 影响分大于 70</label>
        </section>

        <section className="sidebar-section compact">
          <h2>策略项目</h2>
          <p>新闻情绪测试策略</p>
          <p>同步序列 {syncSequence}</p>
          <p>实时同步 {syncSocketStatus}</p>
        </section>
      </aside>

      <section className="center-workspace">
        <header className="topbar">
          <div>
            <span className="crumb">新闻雷达 / AI 分析标签页</span>
            <h1>把新闻变成可验证的策略线索</h1>
          </div>
          <div className="topbar-actions">
            <button type="button" onClick={refreshNewsFeed} disabled={isBusy}>
              <Icon label="源" /> 刷新新闻源
            </button>
            <button type="button" onClick={runNewsAnalysis} disabled={isBusy}>
              <Icon label="析" /> 分析新闻
            </button>
            <button type="button" onClick={draftStrategy} disabled={isBusy}>
              <Icon label="策" /> 生成策略草案
            </button>
            <button type="button" onClick={runReplayBacktest} disabled={isBusy}>
              <Icon label="回" /> 运行回测
            </button>
            <button type="button" onClick={evaluateRisk} disabled={isBusy}>
              <Icon label="控" /> 风控评估
            </button>
            <button type="button" className="primary-action" onClick={submitPaperOrder} disabled={isBusy}>
              <Icon label="纸" /> 放入纸面交易
            </button>
          </div>
        </header>

        <div className="tab-strip" role="tablist" aria-label="工作区标签">
          <button className="tab is-active" type="button">新闻原文</button>
          <button className="tab" type="button">AI 分析</button>
          <button className="tab" type="button">策略草案</button>
          <button className="tab" type="button">回测报告</button>
        </div>

        <article className="analysis-document">
          <div className="document-title">
            <span className="source-chip">{selectedNews.source_name}</span>
            <span>{marketLabel(tickerContext.market)} / {tickerContext.symbol}</span>
          </div>
          <h2>{selectedNews.title_zh || selectedNews.title_original}</h2>
          <p className="summary-text">{analysis.summary_zh}</p>

          <section className="news-feed-panel">
            <header>
              <h3>新闻源事件</h3>
              <span>{newsEvents.length} 条</span>
            </header>
            <div className="news-event-list">
              {newsEvents.slice(0, 5).map((event) => (
                <button
                  className={selectedNews.id === event.id ? 'news-event is-selected' : 'news-event'}
                  key={event.id}
                  type="button"
                  onClick={() => setSelectedNewsId(event.id)}
                >
                  <span>{event.source_name}</span>
                  <strong>{event.title_zh || event.title_original}</strong>
                </button>
              ))}
            </div>
          </section>

          <div className="metric-grid">
            <div>
              <span>情绪</span>
              <strong>{sentimentLabel(analysis.sentiment)}</strong>
            </div>
            <div>
              <span>影响分</span>
              <strong>{Math.round(analysis.impact_score * 100)}</strong>
            </div>
            <div>
              <span>置信度</span>
              <strong>{Math.round(analysis.confidence * 100)}%</strong>
            </div>
            <div>
              <span>关联标的</span>
              <strong>{analysis.affected_tickers.join('、') || selectedTicker}</strong>
            </div>
          </div>

          <section className="source-panel">
            <h3>来源引用</h3>
            <ul>
              {analysis.source_refs.map((source) => <li key={source}>{source}</li>)}
            </ul>
          </section>

          <section className="workflow-panel">
            <div>
              <h3>建议下一步</h3>
              <p>先用纸面交易验证，不进入真实订单。实盘意图必须通过风控与人工审批。</p>
            </div>
            <div className="workflow-steps">
              <span>新闻</span>
              <span>AI 分析</span>
              <span>策略草案</span>
              <span>回测</span>
              <span>纸面交易</span>
            </div>
          </section>

          <section className="strategy-panel">
            <header>
              <h3>策略草案</h3>
              <span>{strategyDraft ? strategyDraft.strategy_version_id : '待生成'}</span>
            </header>
            {strategyDraft ? (
              <>
                <p>{strategyDraft.explanation_zh}</p>
                <div className="rule-list">
                  {strategyDraft.spec.entry_rules.map((rule) => <span key={rule}>{rule}</span>)}
                </div>
              </>
            ) : (
              <p>点击“生成策略草案”，把当前新闻分析转换成可回测的策略版本。</p>
            )}
          </section>

          <section className="backtest-panel">
            <header>
              <h3>回测报告</h3>
              <span>{backtestResult ? backtestResult.replay_scenario : 'golden replay'}</span>
            </header>
            {backtestResult ? (
              <>
                <div className="backtest-metrics">
                  <div><span>策略收益</span><strong>{percentLabel(backtestResult.total_return)}</strong></div>
                  <div><span>基准收益</span><strong>{percentLabel(backtestResult.benchmark_return)}</strong></div>
                  <div><span>最大回撤</span><strong>{percentLabel(backtestResult.max_drawdown)}</strong></div>
                  <div><span>胜率</span><strong>{percentLabel(backtestResult.win_rate)}</strong></div>
                </div>
                <p>{backtestResult.risk_notes_zh[0]}</p>
              </>
            ) : (
              <p>点击“运行回测”，用确定性 golden replay 先验证策略方向。</p>
            )}
          </section>
        </article>
      </section>

      <aside className="right-panel">
        <header>
          <h2>AI 分析师对话</h2>
          <span>中文上下文</span>
        </header>
        <div className="chat-list">
          <div className="chat user">这条新闻会影响哪些股票？</div>
          <div className="chat assistant">当前最直接关联 {selectedTicker}。影响分 {Math.round(analysis.impact_score * 100)}，建议先生成策略草案并回测。</div>
          <div className="chat user">可以直接实盘买吗？</div>
          <div className="chat assistant">不可以。AI 只能生成订单意图，实盘必须进入风控和人工审批。</div>
        </div>

        <section className="risk-card">
          <h3>新闻源状态</h3>
          {providerStatus.length > 0 ? (
            providerStatus.slice(0, 3).map((status) => (
              <p key={status.provider}>
                {status.provider}：{status.message_zh}
              </p>
            ))
          ) : (
            <p>尚未刷新实时新闻源。</p>
          )}
        </section>

        <section className="risk-card">
          <h3>策略 / 回测</h3>
          {strategyDraft ? <p>策略：{strategyDraft.name}</p> : <p>尚未生成策略草案。</p>}
          {backtestResult ? (
            <p>回测收益 {percentLabel(backtestResult.total_return)}，最大回撤 {percentLabel(backtestResult.max_drawdown)}。</p>
          ) : (
            <p>尚未运行 replay 回测。</p>
          )}
        </section>

        <section className="risk-card">
          <h3>审批中心</h3>
          {canManageRisk ? (
            <>
              <p className={killSwitch?.enabled ? 'paper-blocked' : 'paper-ok'}>
                {killSwitch?.enabled ? 'Kill switch 已启用' : 'Kill switch 未启用'}
              </p>
              <p>{killSwitch?.reason_zh ?? '尚未同步急停状态。'}</p>
              <p>待审批：{approvalRequests.filter((approval) => approval.status === 'pending').length} 条</p>
            </>
          ) : (
            <p>当前账号只能做研究、回测和纸面交易，审批与急停需要风控管理员权限。</p>
          )}
          <div className="risk-actions">
            <button type="button" onClick={toggleKillSwitch} disabled={isBusy || !canManageRisk}>
              {killSwitch?.enabled ? '解除急停' : '启用急停'}
            </button>
            <button type="button" onClick={approveLatestRequest} disabled={isBusy || !canManageRisk}>通过</button>
            <button type="button" onClick={rejectLatestRequest} disabled={isBusy || !canManageRisk}>拒绝</button>
          </div>
        </section>

        {canManageAdmin && (
          <section className="risk-card governance-card">
            <h3>账号权限</h3>
            {adminUsers.length > 0 ? (
              <div className="admin-user-list">
                {adminUsers.slice(0, 4).map((user) => (
                  <div className="admin-user-row" key={user.id}>
                    <div>
                      <strong>{user.display_name}</strong>
                      <span>{user.account_key} · {roleLabel(user.role)}</span>
                    </div>
                    <div className="role-actions" aria-label={`${user.account_key} 角色`}>
                      {roleOptions.map((role) => (
                        <button
                          className={user.role === role ? 'is-active' : ''}
                          disabled={isBusy || user.role === role}
                          key={role}
                          onClick={() => void setUserRole(user, role)}
                          type="button"
                        >
                          {roleShortLabel(role)}
                        </button>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p>账号列表尚未同步。</p>
            )}
          </section>
        )}

        {canManageRisk && (
          <section className="risk-card audit-card">
            <h3>审计日志</h3>
            {auditLogs.length > 0 ? (
              <div className="audit-list">
                {auditLogs.slice(0, 5).map((entry) => (
                  <div className="audit-row" key={entry.id}>
                    <span>{formatShortDateTime(entry.created_at)} · {entry.actor_role ? roleLabel(entry.actor_role) : '系统'}</span>
                    <p>{entry.summary_zh}</p>
                  </div>
                ))}
              </div>
            ) : (
              <p>尚未同步审计日志。</p>
            )}
          </section>
        )}

        <section className="risk-card">
          <h3>风控快照</h3>
          {riskDecision ? (
            <>
              <p className="risk-status">{riskDecision.status === 'requires_approval' ? '需要人工审批' : riskDecision.status}</p>
              <p>名义金额：{riskDecision.notional.toLocaleString('zh-CN')}</p>
              <p>{riskDecision.reasons_zh[0]}</p>
            </>
          ) : (
            <p>尚未运行风控评估。</p>
          )}
        </section>

        <section className="risk-card portfolio-card">
          <h3>纸面组合</h3>
          {paperPortfolio ? (
            <>
              <div className="portfolio-metrics">
                {Object.entries(paperPortfolio.equity_by_currency).map(([currency, value]) => (
                  <div key={currency}>
                    <span>{currency} 权益</span>
                    <strong>{moneyLabel(currency, value)}</strong>
                  </div>
                ))}
              </div>
              <div className="portfolio-cash-list">
                {Object.entries(paperPortfolio.cash_by_currency).map(([currency, value]) => (
                  <p key={currency}>现金 {currency}：{moneyLabel(currency, value)}</p>
                ))}
              </div>
              {paperPortfolio.positions.length > 0 ? (
                <div className="position-list">
                  {paperPortfolio.positions.slice(0, 4).map((position) => (
                    <div className="position-row" key={`${position.market}-${position.symbol}-${position.currency}`}>
                      <span>
                        <strong>{position.symbol}</strong>{' '}
                        {position.quantity.toLocaleString('zh-CN')} 股 · 均价 {moneyLabel(position.currency, position.avg_cost)}
                      </span>
                      <span>{moneyLabel(position.currency, position.market_value)}</span>
                    </div>
                  ))}
                </div>
              ) : (
                <p>尚无持仓，提交纸面交易后会自动更新。</p>
              )}
            </>
          ) : (
            <p>纸面组合尚未同步。</p>
          )}
        </section>

        <section className="risk-card">
          <h3>纸面订单</h3>
          {paperOrder ? (
            <>
              <p className={paperOrder.status === 'accepted' ? 'paper-ok' : 'paper-blocked'}>{paperOrder.message_zh}</p>
              <p>订单号：{paperOrder.id}</p>
              {brokerOrder ? (
                <>
                  <p>券商回报：{brokerOrder.adapter} · {brokerOrder.status}</p>
                  <p>
                    成交：{brokerOrder.filled_quantity} 股，均价{' '}
                    {brokerOrder.avg_fill_price?.toLocaleString('zh-CN') ?? '待成交'} {brokerOrder.currency}
                  </p>
                </>
              ) : (
                <p>尚未生成券商回报。</p>
              )}
            </>
          ) : (
            <p>尚未提交纸面交易。</p>
          )}
        </section>
      </aside>

      <footer className="bottom-panel">
        <div className="bottom-title">任务日志 / 风控告警</div>
        <div className="log-list">
          {logs.map((entry) => (
            <div className={`log-entry ${entry.kind}`} key={entry.id}>
              <span>{entry.time}</span>
              <p>{entry.message}</p>
            </div>
          ))}
        </div>
      </footer>
    </main>
  )
}

export default App
