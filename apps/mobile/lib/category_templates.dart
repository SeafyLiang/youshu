import 'domain.dart';

import 'package:uuid/uuid.dart';

// 以用途分类；购买平台、旅行项目与待报销状态使用标签。
const expenseTemplates = <String, List<String>>{
  '餐饮': ['三餐', '水果零食', '买菜食材', '咖啡饮品', '烟酒茶', '聚餐宴请'],
  '交通': ['公交地铁', '打车租车', '火车机票', '加油充电', '停车路桥', '车辆养护', '车辆购置', '交通待分类'],
  '购物': ['服饰鞋包', '美妆护肤', '手机电脑', '数码配件', '家电家具', '购物待分类'],
  '日用': ['清洁洗护', '生活用品', '快递邮寄'],
  '居住': ['房租', '水电燃气', '物业宽带', '维修装修', '购房还贷'],
  '娱乐': ['影音游戏', '订阅服务', '休闲玩乐', '运动健身', '宠物用品'],
  '健康': ['门诊检查', '药品', '保健护理', '美容理发'],
  '学习': ['书籍资料', '课程培训', '办公文具'],
  '旅行': ['住宿', '景点门票', '旅行待分类'],
  '人情': ['礼物红包', '家庭支持', '公益捐助'],
  '工作垫付': ['差旅垫付', '工作采购', '工作待分类'],
  '金融': ['保险', '税费手续费'],
  '其他': ['待分类'],
};
const incomeTemplates = <String, List<String>>{
  '工资': ['工资收入', '奖金津贴', '兼职收入'],
  '投资收益': ['利息', '投资收入'],
  '往来收入': ['礼金红包', '家庭转入', '报销到账', '退款返还'],
  '其他收入': ['闲置出售', '其他待分类'],
};

List<Json> recommendedCategories(Json ledger) {
  final existing = dictionary(ledger, 'category');
  final occupied = (ledger['entries'] as List).map((row) => row['id']).toSet();
  String availableId(String preferred) {
    final id = occupied.contains(preferred) ? const Uuid().v4() : preferred;
    occupied.add(id);
    return id;
  }

  final result = <Json>[];
  for (final type in ['expense', 'income']) {
    final groups = type == 'expense' ? expenseTemplates : incomeTemplates;
    var order = 0;
    for (final group in groups.entries) {
      final root = existing
          .where(
            (e) =>
                e['data']['type'] == type &&
                e['data']['name'] == group.key &&
                e['data']['parent_id'] == '',
          )
          .firstOrNull;
      final rootId =
          root?['id'] ?? availableId(categoryId(ledger['id'], type, group.key));
      final icon =
          defaultIcons[group.key] ?? (type == 'income' ? 'work' : 'category');
      final color = type == 'income' ? '#BD672D' : '#126C62';
      if (root == null) {
        result.add(
          entity(rootId, 'category', {
            'name': group.key,
            'type': type,
            'parent_id': '',
            'icon': icon,
            'color': color,
            'order': order,
            'archived': false,
          }),
        );
      }
      order++;
      for (var i = 0; i < group.value.length; i++) {
        final name = group.value[i];
        if (existing.any(
          (e) => e['data']['parent_id'] == rootId && e['data']['name'] == name,
        )) {
          continue;
        }
        result.add(
          entity(
            availableId(categoryId(ledger['id'], type, '${group.key}/$name')),
            'category',
            {
              'name': name,
              'type': type,
              'parent_id': rootId,
              'icon': icon,
              'color': color,
              'order': i,
              'archived': false,
            },
          ),
        );
      }
    }
  }
  return result;
}

const recommendedIconNames = <String, String>{
  '餐饮': 'ant:shop',
  '三餐': 'ant:rest',
  '水果零食': 'ant:apple',
  '买菜食材': 'ant:shopping-cart',
  '咖啡饮品': 'ant:coffee',
  '烟酒茶': 'ant:experiment',
  '聚餐宴请': 'ant:team',
  '交通': 'ant:car',
  '公交地铁': 'ant:gateway',
  '打车租车': 'ant:branches',
  '火车机票': 'ant:send',
  '加油充电': 'ant:thunderbolt',
  '停车路桥': 'ant:dashboard',
  '车辆养护': 'ant:tool',
  '车辆购置': 'ant:key',
  '交通待分类': 'ant:compass',
  '购物': 'ant:shopping',
  '服饰鞋包': 'ant:skin',
  '美妆护肤': 'ant:highlight',
  '手机电脑': 'ant:laptop',
  '数码配件': 'ant:usb',
  '家电家具': 'ant:desktop',
  '购物待分类': 'ant:barcode',
  '日用': 'ant:inbox',
  '清洁洗护': 'ant:clear',
  '生活用品': 'ant:gift',
  '快递邮寄': 'ant:mail',
  '居住': 'ant:home',
  '房租': 'ant:bank',
  '水电燃气': 'ant:bulb',
  '物业宽带': 'ant:wifi',
  '维修装修': 'ant:build',
  '购房还贷': 'ant:property-safety',
  '娱乐': 'ant:smile',
  '影音游戏': 'ant:play-circle',
  '订阅服务': 'ant:calendar',
  '休闲玩乐': 'ant:rocket',
  '运动健身': 'ant:trophy',
  '宠物用品': 'ant:heart',
  '健康': 'ant:medicine-box',
  '门诊检查': 'ant:reconciliation',
  '药品': 'ant:plus-circle',
  '保健护理': 'ant:safety',
  '美容理发': 'ant:scissor',
  '学习': 'ant:read',
  '书籍资料': 'ant:book',
  '课程培训': 'ant:solution',
  '办公文具': 'ant:edit',
  '旅行': 'ant:global',
  '住宿': 'ant:gold',
  '景点门票': 'ant:camera',
  '旅行待分类': 'ant:flag',
  '人情': 'ant:usergroup-add',
  '礼物红包': 'ant:red-envelope',
  '家庭支持': 'ant:user',
  '公益捐助': 'ant:like',
  '工作垫付': 'ant:audit',
  '差旅垫付': 'ant:environment',
  '工作采购': 'ant:carry-out',
  '工作待分类': 'ant:file-search',
  '金融': 'ant:account-book',
  '保险': 'ant:insurance',
  '税费手续费': 'ant:percentage',
  '其他': 'ant:appstore',
  '待分类': 'ant:question-circle',
  '工资': 'ant:wallet',
  '工资收入': 'ant:pay-circle',
  '奖金津贴': 'ant:crown',
  '兼职收入': 'ant:clock-circle',
  '投资收益': 'ant:fund',
  '利息': 'ant:rise',
  '投资收入': 'ant:line-chart',
  '往来收入': 'ant:swap',
  '礼金红包': 'ant:dollar',
  '家庭转入': 'ant:user-switch',
  '报销到账': 'ant:file-done',
  '退款返还': 'ant:rollback',
  '其他收入': 'ant:plus-square',
  '闲置出售': 'ant:tags',
  '其他待分类': 'ant:question',
};
