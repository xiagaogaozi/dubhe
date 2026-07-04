import React = require('@theia/core/shared/react');
import { Message } from '@theia/core/shared/@lumino/messaging';
import { injectable, postConstruct } from '@theia/core/shared/inversify';
import { ReactWidget } from '@theia/core/lib/browser/widgets/react-widget';

export const DUBHE_WIDGET_ID = 'dubhe.workbench';

const coreUrl = 'http://127.0.0.1:8019';
const prototypeUrl = 'http://127.0.0.1:5173';

type Tone = 'positive' | 'negative' | 'neutral' | 'warning';

const navItems = [
  { label: '今日市场', glyph: '今' },
  { label: '新闻雷达', glyph: '新', active: true },
  { label: 'AI 分析师', glyph: '智' },
  { label: '策略工坊', glyph: '策' },
  { label: '回测中心', glyph: '回' },
  { label: '风控中心', glyph: '控' },
];

const watchlist = [
  { symbol: 'NVDA', name: '英伟达', market: '美股', move: '+2.8%', tone: 'positive' as Tone },
  { symbol: '0700.HK', name: '腾讯控股', market: '港股', move: '-0.4%', tone: 'negative' as Tone },
  { symbol: '600519.SH', name: '贵州茅台', market: 'A 股', move: '+0.6%', tone: 'positive' as Tone },
  { symbol: 'AAPL', name: '苹果', market: '美股', move: '+1.1%', tone: 'positive' as Tone },
];

const newsEvents = [
  {
    source: '本地演示新闻源',
    title: '英伟达业绩超预期并宣布回购',
    time: '09:31',
    score: 83,
    selected: true,
  },
  {
    source: '公告队列',
    title: '港股互联网板块午后成交放量',
    time: '10:12',
    score: 61,
  },
  {
    source: '财报追踪',
    title: '白酒龙头披露渠道库存改善',
    time: '10:45',
    score: 57,
  },
];

const workflowSteps = ['新闻', 'AI 分析', '策略草案', '回测', '纸面交易'];

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
                <p style={styles.sidebarMeta}>本地演示工作区 · 管理员</p>
              </div>
              <span style={styles.onlinePill}>Core</span>
            </header>

            <PanelTitle title="自选列表" meta="4" />
            <div style={styles.watchlist}>
              {watchlist.map((item) => (
                <button
                  key={item.symbol}
                  type="button"
                  style={{ ...styles.watchRow, ...(item.symbol === 'NVDA' ? styles.watchRowSelected : undefined) }}
                >
                  <span>
                    <strong style={styles.watchSymbol}>{item.symbol}</strong>
                    <small style={styles.watchMeta}>{item.name} · {item.market}</small>
                  </span>
                  <Move value={item.move} tone={item.tone} />
                </button>
              ))}
            </div>

            <PanelTitle title="新闻筛选" meta="实时" />
            <div style={styles.filterList}>
              <ToggleLabel label="权威财经新闻" />
              <ToggleLabel label="公告 / 财报" />
              <ToggleLabel label="影响分大于 70" />
            </div>

            <PanelTitle title="任务队列" meta="3" />
            <div style={styles.taskList}>
              <TaskRow label="同步新闻源" status="已完成" tone="positive" />
              <TaskRow label="生成策略草案" status="等待" tone="neutral" />
              <TaskRow label="LEAN 回测" status="未启动" tone="warning" />
            </div>
          </aside>

          <section style={styles.centerWorkspace}>
            <header style={styles.topbar}>
              <div>
                <p style={styles.crumb}>新闻雷达 / AI 分析标签页</p>
                <h1 style={styles.pageTitle}>把新闻变成可验证的策略线索</h1>
              </div>
              <div style={styles.topbarActions}>
                <a style={styles.linkButton} href={prototypeUrl}>原型</a>
                <a style={styles.linkButton} href={`${coreUrl}/docs`}>Core API</a>
                <button style={styles.primaryButton} type="button">刷新新闻</button>
              </div>
            </header>

            <div style={styles.tabStrip} role="tablist" aria-label="工作区标签">
              {['新闻原文', 'AI 分析', '策略草案', '回测报告'].map((tab, index) => (
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
                <span style={styles.sourceChip}>本地演示新闻源</span>
                <span>美股 / NVDA</span>
              </div>
              <h2 style={styles.newsTitle}>英伟达业绩超预期并宣布回购</h2>
              <p style={styles.summaryText}>
                这条消息对 NVDA 的短线情绪偏正面，主要驱动来自收入指引、回购规模和数据中心需求延续。
                当前建议先进入纸面交易验证，不进入真实订单。
              </p>

              <section style={styles.newsFeedPanel}>
                <header style={styles.panelHeader}>
                  <h3 style={styles.panelHeading}>新闻源事件</h3>
                  <span style={styles.smallMeta}>3 条</span>
                </header>
                <div style={styles.newsEventList}>
                  {newsEvents.map((event) => (
                    <button
                      key={event.title}
                      type="button"
                      style={{ ...styles.newsEvent, ...(event.selected ? styles.newsEventSelected : undefined) }}
                    >
                      <span style={styles.newsEventSource}>{event.source} · {event.time}</span>
                      <strong style={styles.newsEventTitle}>{event.title}</strong>
                      <span style={styles.newsEventScore}>影响分 {event.score}</span>
                    </button>
                  ))}
                </div>
              </section>

              <div style={styles.metricGrid}>
                <Metric label="情绪" value="正面" tone="positive" />
                <Metric label="影响分" value="83" tone="positive" />
                <Metric label="置信度" value="84%" tone="neutral" />
                <Metric label="关联标的" value="NVDA" tone="neutral" />
              </div>

              <section style={styles.workflowPanel}>
                <div>
                  <h3 style={styles.panelHeading}>建议下一步</h3>
                  <p style={styles.bodyText}>先生成策略草案，再跑 deterministic replay。真实订单保持关闭。</p>
                </div>
                <div style={styles.workflowSteps}>
                  {workflowSteps.map((step, index) => (
                    <span
                      key={step}
                      style={{ ...styles.workflowStep, ...(index < 2 ? styles.workflowStepDone : undefined) }}
                    >
                      {step}
                    </span>
                  ))}
                </div>
              </section>

              <section style={styles.splitPanels}>
                <div style={styles.flatPanel}>
                  <header style={styles.panelHeader}>
                    <h3 style={styles.panelHeading}>策略草案</h3>
                    <span style={styles.smallMeta}>strategy_v0_demo</span>
                  </header>
                  <p style={styles.bodyText}>当影响分大于 75 且财报事件为正面时，只允许进入纸面交易账户。</p>
                  <div style={styles.ruleList}>
                    <span style={styles.rulePill}>新闻情绪过滤</span>
                    <span style={styles.rulePill}>最大仓位 8%</span>
                    <span style={styles.rulePill}>禁止实盘直连</span>
                  </div>
                </div>

                <div style={styles.flatPanel}>
                  <header style={styles.panelHeader}>
                    <h3 style={styles.panelHeading}>回测报告</h3>
                    <span style={styles.smallMeta}>golden replay</span>
                  </header>
                  <div style={styles.backtestMetrics}>
                    <Metric label="策略收益" value="+12.4%" tone="positive" compact />
                    <Metric label="最大回撤" value="-4.1%" tone="warning" compact />
                    <Metric label="胜率" value="58%" tone="neutral" compact />
                  </div>
                </div>
              </section>
            </article>
          </section>

          <aside style={styles.rightPanel}>
            <header style={styles.rightHeader}>
              <div>
                <h2 style={styles.rightTitle}>AI 分析师</h2>
                <p style={styles.sidebarMeta}>中文上下文 · 工具调用待接入</p>
              </div>
              <span style={styles.safePill}>只读</span>
            </header>

            <div style={styles.chatList}>
              <div style={styles.chatUser}>这条新闻会影响哪些股票？</div>
              <div style={styles.chatAssistant}>当前最直接关联 NVDA。影响分 83，建议先生成策略草案并回测。</div>
              <div style={styles.chatUser}>可以直接实盘买吗？</div>
              <div style={styles.chatAssistant}>不可以。AI 只能生成订单意图，实盘必须进入风控和人工审批。</div>
            </div>

            <SidePanel title="审批中心" meta="风控">
              <p style={styles.safeStatus}>Kill switch 未启用</p>
              <p style={styles.bodyText}>待审批：1 条。当前账号可查看审批队列。</p>
              <div style={styles.riskActions}>
                <button style={styles.smallButton} type="button">通过</button>
                <button style={styles.smallButtonDanger} type="button">拒绝</button>
              </div>
            </SidePanel>

            <SidePanel title="纸面组合" meta="demo_account">
              <div style={styles.portfolioMetric}>
                <span>USD 权益</span>
                <strong>$102,430.00</strong>
              </div>
              <div style={styles.positionRow}>
                <span>NVDA · 40 股</span>
                <strong>$34,200.00</strong>
              </div>
            </SidePanel>
          </aside>

          <footer style={styles.bottomPanel}>
            <strong style={styles.bottomTitle}>任务日志 / 风控告警</strong>
            <div style={styles.logList}>
              <LogEntry time="10:45:12" text="工作台已载入，等待连接 Dubhe Core。" tone="neutral" />
              <LogEntry time="10:45:16" text="实盘交易关闭：真实订单必须先通过风控与人工审批。" tone="warning" />
              <LogEntry time="10:45:22" text="新闻雷达演示数据已就绪。" tone="positive" />
            </div>
          </footer>
        </section>
      </main>
    );
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

function ToggleLabel(props: { label: string }): React.ReactElement {
  return (
    <label style={styles.toggleLabel}>
      <input type="checkbox" defaultChecked />
      {props.label}
    </label>
  );
}

function TaskRow(props: { label: string; status: string; tone: Tone }): React.ReactElement {
  return (
    <div style={styles.taskRow}>
      <span>{props.label}</span>
      <ToneText tone={props.tone} value={props.status} />
    </div>
  );
}

function Move(props: { value: string; tone: Tone }): React.ReactElement {
  return <span style={{ ...styles.move, ...toneTextStyle(props.tone) }}>{props.value}</span>;
}

function ToneText(props: { value: string; tone: Tone }): React.ReactElement {
  return <span style={{ ...styles.toneText, ...toneTextStyle(props.tone) }}>{props.value}</span>;
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

function LogEntry(props: { time: string; text: string; tone: Tone }): React.ReactElement {
  return (
    <div style={styles.logEntry}>
      <span style={styles.logTime}>{props.time}</span>
      <p style={{ ...styles.logText, ...toneTextStyle(props.tone) }}>{props.text}</p>
    </div>
  );
}

function toneTextStyle(tone: Tone): React.CSSProperties {
  if (tone === 'positive') return styles.positiveText;
  if (tone === 'negative') return styles.negativeText;
  if (tone === 'warning') return styles.warningText;
  return styles.neutralText;
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
    minWidth: 1180,
    minHeight: 760,
    display: 'grid',
    gridTemplateColumns: '64px 260px minmax(500px, 1fr) 320px',
    gridTemplateRows: 'minmax(0, 1fr) 112px',
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
    overflow: 'hidden',
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
    background: '#e4f5ec',
    color: '#14613f',
    fontSize: 12,
    fontWeight: 800,
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
  filterList: {
    display: 'grid',
    gap: 8,
    marginTop: 8,
  } as React.CSSProperties,
  toggleLabel: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    color: '#405149',
    fontSize: 13,
  } as React.CSSProperties,
  taskList: {
    display: 'grid',
    gap: 8,
    marginTop: 8,
  } as React.CSSProperties,
  taskRow: {
    display: 'flex',
    justifyContent: 'space-between',
    gap: 10,
    fontSize: 13,
  } as React.CSSProperties,
  centerWorkspace: {
    minWidth: 0,
    display: 'grid',
    gridTemplateRows: 'auto auto minmax(0, 1fr)',
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
    minHeight: 98,
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
  safeStatus: {
    margin: '10px 0 0',
    color: '#16623f',
    fontWeight: 800,
  } as React.CSSProperties,
  riskActions: {
    display: 'flex',
    gap: 8,
    marginTop: 10,
  } as React.CSSProperties,
  smallButton: {
    flex: 1,
    padding: '8px 10px',
    border: 0,
    borderRadius: 8,
    background: '#e4f5ec',
    color: '#165238',
    cursor: 'pointer',
    fontWeight: 800,
  } as React.CSSProperties,
  smallButtonDanger: {
    flex: 1,
    padding: '8px 10px',
    border: 0,
    borderRadius: 8,
    background: '#fff0ea',
    color: '#9b3721',
    cursor: 'pointer',
    fontWeight: 800,
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
  toneText: {
    fontWeight: 800,
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
