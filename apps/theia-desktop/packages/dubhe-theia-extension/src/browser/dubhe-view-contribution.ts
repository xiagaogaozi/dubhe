import { injectable } from '@theia/core/shared/inversify';
import {
  AbstractViewContribution,
  FrontendApplication,
} from '@theia/core/lib/browser';
import {
  Command,
  CommandRegistry,
  MenuModelRegistry,
} from '@theia/core/lib/common';

import { DubheWidget, DUBHE_WIDGET_ID } from './dubhe-widget';

export const DUBHE_OPEN_COMMAND: Command = {
  id: 'dubhe.open-workbench',
  label: '打开 Dubhe 工作台',
};

@injectable()
export class DubheViewContribution
  extends AbstractViewContribution<DubheWidget> {
  constructor() {
    super({
      widgetId: DUBHE_WIDGET_ID,
      widgetName: 'Dubhe',
      defaultWidgetOptions: {
        area: 'main',
      },
      toggleCommandId: DUBHE_OPEN_COMMAND.id,
      toggleKeybinding: 'ctrlcmd+alt+d',
    });
  }

  override async onStart(app: FrontendApplication): Promise<void> {
    await super.onStart(app);
    await this.openView({ activate: true, reveal: true });
  }

  override registerCommands(commands: CommandRegistry): void {
    super.registerCommands(commands);
    commands.registerCommand(DUBHE_OPEN_COMMAND, {
      execute: () => this.openView({ activate: true, reveal: true }),
    });
  }

  override registerMenus(menus: MenuModelRegistry): void {
    super.registerMenus(menus);
    menus.registerMenuAction(['view', 'views'], {
      commandId: DUBHE_OPEN_COMMAND.id,
      label: DUBHE_OPEN_COMMAND.label,
      order: '0',
    });
  }
}
