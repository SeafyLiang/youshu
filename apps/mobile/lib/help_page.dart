import 'utility_pages.dart';

import 'package:flutter/services.dart';

import 'ui.dart';

import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('使用帮助')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.language),
          title: const Text('有数官网'),
          subtitle: const Text('youshu-site.894700104.xyz'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => openExternal('https://youshu-site.894700104.xyz/'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.mail_outline),
          title: const Text('意见反馈'),
          subtitle: const Text('894700104@qq.com'),
          onTap: () => openExternal('mailto:894700104@qq.com'),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: '894700104@qq.com'),
              );
              notifyApp('邮箱已复制');
            },
          ),
        ),
        ExpansionTile(
          title: Text('快捷记账'),
          children: [
            ListTile(
              title: Text(
                '长按桌面图标或点按小组件可记一笔。小组件显示当前账本的支出与预算，新增保存后返回流水；从统计或预算明细编辑则回原列表。键盘触感可在偏好设置中调整关闭、轻、中、强。',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('物品与维修'),
          children: [
            ListTile(
              title: Text(
                '物品页独立记录购买、照片、有效期、保修和养护费用，不生成账本流水。总资产为持有物品购入原值，维修单独累计；日均按（购入 + 养护 − 回收）除以持有天数，售出或退役后冻结。右上云图标手动物品备份，包含照片和凭证；换机请分别备份账本和物品。分析页内切换统计与预算。',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('常用模板与周期记账'),
          children: [
            ListTile(
              title: Text(
                '在我的 → 常用模板新建随手记，或长按普通收支流水存为模板。金额可留空，置顶后首页快捷使用。周期记账预设房租、房贷，也可自定义分期和固定收入；支持从中途接入、暂停恢复、跳过和结束。到期先待确认，核对实际金额后记账；已记过可关联已有流水。房租押金只在指定期单独记一笔。账本备份保留模板、计划和期次，恢复副本默认暂停。',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('账期与统计'),
          children: [
            ListTile(
              title: Text(
                '修改起始日会重新划分全部历史账期，交易日期和金额不变。短月使用当月最后一天。预算跟随原月份迁移，手动日额度按实际日期保留。年/月/日统一使用排除规则；修改日额度同步月额，月额不足需调整或重置。标签统计中，多标签账目分别计入各标签；不同币种分开汇总。',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('多账本与合并'),
          children: [
            ListTile(
              title: Text(
                '顶部账本按钮支持单选和多选。预算针对当前记账账本。在「账本管理」合并流水时，会按交易日汇率创建人民币账本并保留原本；仅相同来源记录去重，预算不合并。',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('备份与恢复'),
          children: [
            ListTile(
              title: Text(
                '账本保存在设备，可保存账本备份文件或配置自己的 HTTPS WebDAV。开启前台自动备份后，有改动时会安排备份。备份包含分类、预算、导入草稿与批次记录，采用可读 JSON，请存入私人目录。恢复前先核对，再创建副本。回收站保留账目和账本 30 天。',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('导入与导出'),
          children: [
            ListTile(
              title: Text(
                '支持随手记、微信 XLSX 和支付宝 CSV。先核对再导入；有疑问的记录可留在草稿。导入记录可查看批次，把符合条件的流水移入回收站。流水可按选定范围导出 CSV。换机请使用账本备份。',
              ),
            ),
          ],
        ),
        ListTile(
          title: Text('物品全彩图标'),
          subtitle: Text('Microsoft Fluent UI Emoji · MIT；洗衣机原创'),
          onTap: () => showLicensePage(context: context, applicationName: '有数'),
        ),
        ListTile(
          title: Text('Ant Design Icons'),
          subtitle: Text('© Ant UED · MIT License'),
        ),
      ],
    ),
  );
}
