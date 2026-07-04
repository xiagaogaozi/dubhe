import React = require('@theia/core/shared/react');
import { Message } from '@theia/core/shared/@lumino/messaging';
import { injectable, postConstruct } from '@theia/core/shared/inversify';
import { ReactWidget } from '@theia/core/lib/browser/widgets/react-widget';

export const DUBHE_WIDGET_ID = 'dubhe.workbench';

const coreUrl = 'http://127.0.0.1:8019';
const prototypeUrl = 'http://127.0.0.1:5173';

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
        <section style={styles.hero}>
          <div style={styles.brandMark}>D</div>
          <div>
            <p style={styles.eyebrow}>Dubhe Desktop / Theia Shell</p>
            <h1 style={styles.title}>把新闻、AI、策略和风控放进一个 IDE 工作台</h1>
            <p style={styles.copy}>
              这里是 Dubhe 的正式 Theia Desktop 落点。当前 React/Vite 工作台仍作为功能原型运行，
              本扩展会逐步接管新闻雷达、AI 分析、策略工坊、回测中心、纸面组合和风控审批面板。
            </p>
            <div style={styles.actions}>
              <a style={styles.primaryButton} href={prototypeUrl}>打开当前桌面原型</a>
              <a style={styles.secondaryButton} href={`${coreUrl}/docs`}>查看 Core API</a>
            </div>
          </div>
        </section>

        <section style={styles.grid}>
          <DubheCard
            title="新闻雷达"
            text="接入 A 股、港股、美股新闻和公告，统一成中文摘要、影响分、来源引用。"
            status="原型可用"
          />
          <DubheCard
            title="AI 分析师"
            text="围绕新闻、组合、策略草案和回测结果进行中文讨论；AI 不能直接下单。"
            status="接口占位"
          />
          <DubheCard
            title="策略工坊"
            text="小白优先走模板和可视化策略积木，高级用户再进入 Theia 编辑器。"
            status="待接 Blockly"
          />
          <DubheCard
            title="回测中心"
            text="当前有 deterministic replay smoke，后续接 LEAN worker 和报告解析。"
            status="smoke 可用"
          />
          <DubheCard
            title="纸面组合"
            text="纸面订单成交后写入现金、权益、持仓和均价，并推送同步事件。"
            status="Core 可用"
          />
          <DubheCard
            title="风控中心"
            text="审批、kill switch、角色门禁和审计日志必须在所有交易路径之前。"
            status="Core 可用"
          />
        </section>
      </main>
    );
  }
}

function DubheCard(props: { title: string; text: string; status: string }): React.ReactElement {
  return (
    <article style={styles.card}>
      <div style={styles.cardHeader}>
        <h2 style={styles.cardTitle}>{props.title}</h2>
        <span style={styles.badge}>{props.status}</span>
      </div>
      <p style={styles.cardText}>{props.text}</p>
    </article>
  );
}

const styles = {
  shell: {
    minHeight: '100%',
    padding: 24,
    color: '#10231c',
    background: '#f4f2ea',
    boxSizing: 'border-box',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
  } as React.CSSProperties,
  hero: {
    display: 'grid',
    gridTemplateColumns: '56px minmax(0, 1fr)',
    gap: 18,
    maxWidth: 920,
    padding: 24,
    border: '1px solid #d9d6cc',
    borderRadius: 8,
    background: '#fffdf7',
  } as React.CSSProperties,
  brandMark: {
    width: 52,
    height: 52,
    display: 'grid',
    placeItems: 'center',
    borderRadius: 10,
    background: '#cde9d9',
    color: '#082118',
    fontWeight: 800,
    fontSize: 22,
  } as React.CSSProperties,
  eyebrow: {
    margin: 0,
    color: '#527062',
    fontSize: 13,
    fontWeight: 700,
  } as React.CSSProperties,
  title: {
    margin: '6px 0 10px',
    maxWidth: 720,
    fontSize: 30,
    lineHeight: 1.15,
  } as React.CSSProperties,
  copy: {
    margin: 0,
    maxWidth: 760,
    color: '#405248',
    fontSize: 15,
    lineHeight: 1.65,
  } as React.CSSProperties,
  actions: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 10,
    marginTop: 18,
  } as React.CSSProperties,
  primaryButton: {
    padding: '10px 14px',
    borderRadius: 8,
    background: '#0f3d31',
    color: '#ffffff',
    textDecoration: 'none',
    fontWeight: 800,
  } as React.CSSProperties,
  secondaryButton: {
    padding: '10px 14px',
    border: '1px solid #b9c4bc',
    borderRadius: 8,
    color: '#0f3d31',
    textDecoration: 'none',
    fontWeight: 800,
  } as React.CSSProperties,
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
    gap: 12,
    maxWidth: 920,
    marginTop: 16,
  } as React.CSSProperties,
  card: {
    padding: 16,
    minHeight: 132,
    border: '1px solid #d9d6cc',
    borderRadius: 8,
    background: '#fffdf7',
  } as React.CSSProperties,
  cardHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  } as React.CSSProperties,
  cardTitle: {
    margin: 0,
    fontSize: 18,
  } as React.CSSProperties,
  badge: {
    padding: '4px 8px',
    borderRadius: 999,
    background: '#dfeee5',
    color: '#184536',
    fontSize: 12,
    fontWeight: 800,
    whiteSpace: 'nowrap',
  } as React.CSSProperties,
  cardText: {
    margin: '12px 0 0',
    color: '#45584d',
    lineHeight: 1.55,
  } as React.CSSProperties,
};
