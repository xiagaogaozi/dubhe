import { CommandContribution, MenuContribution } from '@theia/core/lib/common';
import {
  bindViewContribution,
  FrontendApplicationContribution,
  WidgetFactory,
} from '@theia/core/lib/browser';
import { ContainerModule } from '@theia/core/shared/inversify';

import { DubheViewContribution } from './dubhe-view-contribution';
import { DubheWidget, DUBHE_WIDGET_ID } from './dubhe-widget';

export default new ContainerModule(bind => {
  bind(DubheWidget).toSelf();
  bind(WidgetFactory).toDynamicValue(context => ({
    id: DUBHE_WIDGET_ID,
    createWidget: () => context.container.get(DubheWidget),
  })).inSingletonScope();

  bindViewContribution(bind, DubheViewContribution);
  bind(FrontendApplicationContribution).toService(DubheViewContribution);
  bind(CommandContribution).toService(DubheViewContribution);
  bind(MenuContribution).toService(DubheViewContribution);
});
