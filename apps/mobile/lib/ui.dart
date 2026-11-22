import 'notices.dart';
import 'display.dart';
import 'theme_art.dart';
export 'display.dart';
export 'notices.dart';
export 'theme_art.dart';
import 'icon_catalog.dart';

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

const appRelease = '0.8.3 (22)';
const brand = Color(0xFF0E7460);
const tabularFigures = [FontFeature.tabularFigures()];

bool get isAndroidPlatform => !kIsWeb && Platform.isAndroid;

enum AppThemeStyle {
  emerald(
    'emerald',
    '深翠青瓷',
    '矿物翠绿 · 沉稳通透',
    Color(0xFF0E7460),
    paperTint: Color(0xFFF3F5F4),
  ),
  mono(
    'mono',
    '极简石墨黑',
    '黑白灰骨架 · 利落克制',
    Color(0xFF15181C),
    paperTint: Color(0xFFF4F5F7),
  ),
  oat(
    'oat',
    '燕麦暖纸',
    '温润暖白 · 赤陶手账感',
    Color(0xFFB55429),
    paperTint: Color(0xFFF6F2EC),
  ),
  cat(
    'cat',
    '橘猫喵账',
    '柔雾杏仁奶粉 · 俏皮眨眼橘猫',
    Color(0xFFD48E6C),
    paperTint: Color(0xFFFAF5EE),
    isCute: true,
    badgeText: '小鱼干守护中',
    recordHintExp: '喵？记下这笔小心愿',
    recordHintInc: '哇！小鱼干基金涨啦',
  ),
  dog(
    'dog',
    '柴犬汪汪',
    '柔雾香草燕麦 · 歪耳吐舌柴柴',
    Color(0xFFC59C5B),
    paperTint: Color(0xFFF9F5EB),
    isCute: true,
    badgeText: '守财乖柴柴',
    recordHintExp: '汪！乖乖记在小本本',
    recordHintInc: '耶！大骨头进账咯',
  ),
  panda(
    'panda',
    '滚滚熊猫',
    '柔雾烟青竹雾 · 抱笋憨态花花熊',
    Color(0xFF5EA587),
    paperTint: Color(0xFFF0F6F2),
    isCute: true,
    badgeText: '抱笋管好账',
    recordHintExp: '咔嚓~ 记完继续啃笋',
    recordHintInc: '竹林大丰收啦！',
  ),
  capybara(
    'capybara',
    '佛系豚豚',
    '柔雾砂砾奶咖 · 叠橘温泉豚豚',
    Color(0xFFC79263),
    paperTint: Color(0xFFF6F2EB),
    isCute: true,
    badgeText: '情绪与结余都稳',
    recordHintExp: '淡定记一笔，不焦虑',
    recordHintInc: '顶着小橘子慢慢变富',
  ),
  taro(
    'taro',
    '芋泥云朵',
    '柔雾烟紫香芋 · 星星眼小云朵',
    Color(0xFF9281C4),
    paperTint: Color(0xFFF4F1FA),
    isCute: true,
    badgeText: '星光存钱中',
    recordHintExp: '云朵轻轻接住这笔账',
    recordHintInc: '闪闪发光进账啦！',
  ),
  matcha(
    'matcha',
    '抹茶小熊',
    '柔雾牛油果绿 · 捧杯贝雷帽小熊',
    Color(0xFF6EA374),
    paperTint: Color(0xFFF0F6EF),
    isCute: true,
    badgeText: '抹茶好运账',
    recordHintExp: '小熊帮你记好啦~',
    recordHintInc: '四叶草带来好运进账',
  );

  final String id, label, subtitle;
  final Color swatch;
  final Color paperTint;
  final bool isCute;
  final String badgeText;
  final String recordHintExp;
  final String recordHintInc;

  const AppThemeStyle(
    this.id,
    this.label,
    this.subtitle,
    this.swatch, {
    required this.paperTint,
    this.isCute = false,
    this.badgeText = '',
    this.recordHintExp = '',
    this.recordHintInc = '',
  });

  static List<AppThemeStyle> get classicThemes =>
      values.where((e) => !e.isCute).toList(growable: false);

  static List<AppThemeStyle> get cuteThemes =>
      values.where((e) => e.isCute).toList(growable: false);
}

AppThemeStyle appThemeStyleOf(Object? raw) => switch (raw) {
  'mono' => AppThemeStyle.mono,
  'oat' => AppThemeStyle.oat,
  'cat' => AppThemeStyle.cat,
  'dog' => AppThemeStyle.dog,
  'panda' => AppThemeStyle.panda,
  'capybara' => AppThemeStyle.capybara,
  'taro' => AppThemeStyle.taro,
  'matcha' => AppThemeStyle.matcha,
  _ => AppThemeStyle.emerald,
};

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final AppThemeStyle style;
  final Brightness brightness;
  final Color canvas;
  final Color card;
  final Color surface2;
  final Color dockSurface;
  final Color headerGlass;
  final Color border;
  final Color borderStrong;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color brandColor;
  final Color brandDeep;
  final Color brandSoft;
  final Color income;
  final Color incomeSoft;
  final Color danger;
  final Color warn;
  final List<Color> heroGradient;
  final List<Color> fabGradient;
  final Color fabInk;
  final List<Color> saveGradient;
  final Color saveInk;
  final List<Color> incomeGradient;
  final Color keypadBg;
  final Color keyBg;
  final Color keyFn;
  final Color segmentTrack;
  final Color segmentActive;
  final Color waterOk;
  final Color waterWarn;
  final Color waterOver;
  final List<Color> chartColors;
  final Color heroInk;
  final Color heroSubInk;
  final Color heroBadgeBg;
  final Color heroBadgeInk;
  final Color heroBorder;
  final Color? markerSwipe;
  final Color? patternColor;
  final Color? auraColor;

  const AppPalette({
    required this.style,
    required this.brightness,
    required this.canvas,
    required this.card,
    required this.surface2,
    required this.dockSurface,
    required this.headerGlass,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.brandColor,
    required this.brandDeep,
    required this.brandSoft,
    required this.income,
    required this.incomeSoft,
    required this.danger,
    required this.warn,
    required this.heroGradient,
    required this.fabGradient,
    required this.fabInk,
    required this.saveGradient,
    required this.saveInk,
    required this.incomeGradient,
    required this.keypadBg,
    required this.keyBg,
    required this.keyFn,
    required this.segmentTrack,
    required this.segmentActive,
    required this.waterOk,
    required this.waterWarn,
    required this.waterOver,
    required this.chartColors,
    this.heroInk = Colors.white,
    this.heroSubInk = const Color(0xC7FFFFFF),
    this.heroBadgeBg = const Color(0x29FFFFFF),
    this.heroBadgeInk = Colors.white,
    this.heroBorder = Colors.transparent,
    this.markerSwipe,
    this.patternColor,
    this.auraColor,
  });

  bool get isDark => brightness == Brightness.dark;

  static AppPalette resolve(AppThemeStyle style, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (style) {
      AppThemeStyle.mono =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.mono,
                brightness: Brightness.dark,
                canvas: Color(0xFF090A0C),
                card: Color(0xFF14161A),
                surface2: Color(0xFF1C1F25),
                dockSurface: Color(0xE016191E),
                headerGlass: Color(0xE6090A0C),
                border: Color(0x14FFFFFF),
                borderStrong: Color(0x24FFFFFF),
                ink: Color(0xFFF3F5F7),
                ink2: Color(0xFF9AA2AE),
                ink3: Color(0xFF666F7B),
                brandColor: Color(0xFFF3F5F7),
                brandDeep: Color(0xFFD2D7DF),
                brandSoft: Color(0x1CFFFFFF),
                income: Color(0xFF34D399),
                incomeSoft: Color(0x2434D399),
                danger: Color(0xFFF87171),
                warn: Color(0xFFFBBF24),
                heroGradient: [Color(0xFF1B1F27), Color(0xFF313846)],
                fabGradient: [Color(0xFFFFFFFF), Color(0xFFDDE1E7)],
                fabInk: Color(0xFF0E1013),
                saveGradient: [Color(0xFFFFFFFF), Color(0xFFE0E4EA)],
                saveInk: Color(0xFF0E1013),
                incomeGradient: [Color(0xFF34D399), Color(0xFF10B981)],
                keypadBg: Color(0xFF101215),
                keyBg: Color(0xFF1C1F25),
                keyFn: Color(0xFF16191E),
                segmentTrack: Color(0x14FFFFFF),
                segmentActive: Color(0xFF252932),
                waterOk: Color(0x20FFFFFF),
                waterWarn: Color(0x2DFBBF24),
                waterOver: Color(0x33F87171),
                chartColors: [
                  Color(0xFFE2E6EC),
                  Color(0xFF34D399),
                  Color(0xFF60A5FA),
                  Color(0xFFF5A362),
                  Color(0xFFA78BFA),
                  Color(0xFFF472B6),
                  Color(0xFFFBBF24),
                  Color(0xFF94A3B8),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.mono,
                brightness: Brightness.light,
                canvas: Color(0xFFF4F5F7),
                card: Color(0xFFFFFFFF),
                surface2: Color(0xFFF7F8FA),
                dockSurface: Color(0xDCFFFFFF),
                headerGlass: Color(0xE6F4F5F7),
                border: Color(0x12111418),
                borderStrong: Color(0x20111418),
                ink: Color(0xFF121518),
                ink2: Color(0xFF58606A),
                ink3: Color(0xFF8D95A0),
                brandColor: Color(0xFF15181C),
                brandDeep: Color(0xFF0B0D10),
                brandSoft: Color(0x1415181C),
                income: Color(0xFF0F9468),
                incomeSoft: Color(0x1C0F9468),
                danger: Color(0xFFDC3F3F),
                warn: Color(0xFFC27E16),
                heroGradient: [Color(0xFF16191F), Color(0xFF323A46)],
                fabGradient: [Color(0xFF272B33), Color(0xFF111317)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFF242830), Color(0xFF111317)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFF12A373), Color(0xFF0C7E58)],
                keypadBg: Color(0xFFECEEF1),
                keyBg: Color(0xFFFFFFFF),
                keyFn: Color(0xFFE5E8EC),
                segmentTrack: Color(0x10111418),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x1715181C),
                waterWarn: Color(0x24C27E16),
                waterOver: Color(0x24DC3F3F),
                chartColors: [
                  Color(0xFF181C22),
                  Color(0xFF0F9468),
                  Color(0xFF3B82F6),
                  Color(0xFFD97736),
                  Color(0xFF8B5CF6),
                  Color(0xFFEC4899),
                  Color(0xFFCA8A04),
                  Color(0xFF64748B),
                ],
              ),
      AppThemeStyle.oat =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.oat,
                brightness: Brightness.dark,
                canvas: Color(0xFF120F0D),
                card: Color(0xFF1D1815),
                surface2: Color(0xFF27211C),
                dockSurface: Color(0xE01F1A16),
                headerGlass: Color(0xE6120F0D),
                border: Color(0x14FCEEDE),
                borderStrong: Color(0x24FCEEDE),
                ink: Color(0xFFF7F1EA),
                ink2: Color(0xFFB3A396),
                ink3: Color(0xFF7A6C61),
                brandColor: Color(0xFFE59564),
                brandDeep: Color(0xFFC47142),
                brandSoft: Color(0x26E59564),
                income: Color(0xFF57C492),
                incomeSoft: Color(0x2457C492),
                danger: Color(0xFFEF7373),
                warn: Color(0xFFE8B85D),
                heroGradient: [Color(0xFF2D1D15), Color(0xFF5F3B27)],
                fabGradient: [Color(0xFFEC9E6E), Color(0xFFCA7645)],
                fabInk: Color(0xFF1C110A),
                saveGradient: [Color(0xFFEC9E6E), Color(0xFFCA7645)],
                saveInk: Color(0xFF1C110A),
                incomeGradient: [Color(0xFF57C492), Color(0xFF379E70)],
                keypadBg: Color(0xFF171310),
                keyBg: Color(0xFF26201B),
                keyFn: Color(0xFF1E1915),
                segmentTrack: Color(0x14FCEEDE),
                segmentActive: Color(0xFF302822),
                waterOk: Color(0x2DE59564),
                waterWarn: Color(0x2DE8B85D),
                waterOver: Color(0x33EF7373),
                chartColors: [
                  Color(0xFFE59564),
                  Color(0xFF57C492),
                  Color(0xFFE5B55C),
                  Color(0xFF8AA4CC),
                  Color(0xFFC492B4),
                  Color(0xFFE87E7E),
                  Color(0xFF9AC28B),
                  Color(0xFFA8998B),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.oat,
                brightness: Brightness.light,
                canvas: Color(0xFFF6F2EC),
                card: Color(0xFFFFFDF9),
                surface2: Color(0xFFF8F4EE),
                dockSurface: Color(0xE0FFFDF9),
                headerGlass: Color(0xE6F6F2EC),
                border: Color(0x14422E1E),
                borderStrong: Color(0x22422E1E),
                ink: Color(0xFF241C16),
                ink2: Color(0xFF6E5F53),
                ink3: Color(0xFF9E8F82),
                brandColor: Color(0xFFB55429),
                brandDeep: Color(0xFF913F1C),
                brandSoft: Color(0x1CB55429),
                income: Color(0xFF2E7D5B),
                incomeSoft: Color(0x1C2E7D5B),
                danger: Color(0xFFC9403E),
                warn: Color(0xFFBE7C18),
                heroGradient: [Color(0xFF3A251B), Color(0xFF7C4B31)],
                fabGradient: [Color(0xFFC86335), Color(0xFF9E441E)],
                fabInk: Color(0xFFFFFDF9),
                saveGradient: [Color(0xFFC66134), Color(0xFF9E441E)],
                saveInk: Color(0xFFFFFDF9),
                incomeGradient: [Color(0xFF358C66), Color(0xFF246A4C)],
                keypadBg: Color(0xFFF0EAE0),
                keyBg: Color(0xFFFFFDF9),
                keyFn: Color(0xFFEAE2D6),
                segmentTrack: Color(0x11422E1E),
                segmentActive: Color(0xFFFFFDF9),
                waterOk: Color(0x1FB55429),
                waterWarn: Color(0x26BE7C18),
                waterOver: Color(0x24C9403E),
                chartColors: [
                  Color(0xFFB55429),
                  Color(0xFF2E7D5B),
                  Color(0xFFC98B2B),
                  Color(0xFF6A7BA2),
                  Color(0xFF9C6B8A),
                  Color(0xFFC85B5B),
                  Color(0xFF6E996B),
                  Color(0xFF8C7A6B),
                ],
              ),
      AppThemeStyle.emerald =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.emerald,
                brightness: Brightness.dark,
                canvas: Color(0xFF0B1110),
                card: Color(0xFF141D1B),
                surface2: Color(0xFF1B2724),
                dockSurface: Color(0xDE16211E),
                headerGlass: Color(0xE60B1110),
                border: Color(0x14EBF8F4),
                borderStrong: Color(0x22EBF8F4),
                ink: Color(0xFFEDF4F1),
                ink2: Color(0xFF93A7A1),
                ink3: Color(0xFF637771),
                brandColor: Color(0xFF38CFA0),
                brandDeep: Color(0xFF1E9E77),
                brandSoft: Color(0x2238CFA0),
                income: Color(0xFFF3A363),
                incomeSoft: Color(0x24F3A363),
                danger: Color(0xFFF07373),
                warn: Color(0xFFE5B55C),
                heroGradient: [Color(0xFF0D3D34), Color(0xFF176C5B)],
                fabGradient: [Color(0xFF34CFA0), Color(0xFF1FA67D)],
                fabInk: Color(0xFF062119),
                saveGradient: [Color(0xFF34CFA0), Color(0xFF1FA67D)],
                saveInk: Color(0xFF062119),
                incomeGradient: [Color(0xFFF3A363), Color(0xFFD97E39)],
                keypadBg: Color(0xFF111917),
                keyBg: Color(0xFF1D2926),
                keyFn: Color(0xFF172220),
                segmentTrack: Color(0x12FFFFFF),
                segmentActive: Color(0xFF202E2A),
                waterOk: Color(0x2B38CFA0),
                waterWarn: Color(0x2DE5B55C),
                waterOver: Color(0x33F07373),
                chartColors: [
                  Color(0xFF38CFA0),
                  Color(0xFFF3A363),
                  Color(0xFF6BA6D6),
                  Color(0xFFB59CD9),
                  Color(0xFFE8848E),
                  Color(0xFF8CC490),
                  Color(0xFFDDC577),
                  Color(0xFF85A1B0),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.emerald,
                brightness: Brightness.light,
                canvas: Color(0xFFF3F5F4),
                card: Color(0xFFFFFFFF),
                surface2: Color(0xFFF7F9F8),
                dockSurface: Color(0xDCFFFFFF),
                headerGlass: Color(0xE6F3F5F4),
                border: Color(0x120F1F1A),
                borderStrong: Color(0x1E0F1F1A),
                ink: Color(0xFF111A18),
                ink2: Color(0xFF586A65),
                ink3: Color(0xFF8C9B97),
                brandColor: Color(0xFF0E7460),
                brandDeep: Color(0xFF0B594A),
                brandSoft: Color(0x1A0E7460),
                income: Color(0xFFC86A2B),
                incomeSoft: Color(0x1CC86A2B),
                danger: Color(0xFFD64545),
                warn: Color(0xFFB97D19),
                heroGradient: [Color(0xFF0D5144), Color(0xFF19826E)],
                fabGradient: [Color(0xFF12856E), Color(0xFF0C6352)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFF12856E), Color(0xFF0B6050)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFFD97736), Color(0xFFB85B1E)],
                keypadBg: Color(0xFFEBF0EE),
                keyBg: Color(0xFFFFFFFF),
                keyFn: Color(0xFFE4ECE9),
                segmentTrack: Color(0x0F0F1F1A),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x210E7460),
                waterWarn: Color(0x26B97D19),
                waterOver: Color(0x24D64545),
                chartColors: [
                  Color(0xFF0E7460),
                  Color(0xFFD97736),
                  Color(0xFF3B82A6),
                  Color(0xFF7E6BB5),
                  Color(0xFFC95B6B),
                  Color(0xFF5D9E6C),
                  Color(0xFFC19D44),
                  Color(0xFF668090),
                ],
              ),
      AppThemeStyle.cat =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.cat,
                brightness: Brightness.dark,
                canvas: Color(0xFF171311),
                card: Color(0xFF221C19),
                surface2: Color(0xFF2C2420),
                dockSurface: Color(0xE6221C19),
                headerGlass: Color(0xE8171311),
                border: Color(0x1AFFDCC6),
                borderStrong: Color(0x2EFFDCC6),
                ink: Color(0xFFFAF0EA),
                ink2: Color(0xFFC2ACA0),
                ink3: Color(0xFF89756B),
                brandColor: Color(0xFFEBA580),
                brandDeep: Color(0xFFD08762),
                brandSoft: Color(0x2AEBA580),
                income: Color(0xFF6FD0AD),
                incomeSoft: Color(0x266FD0AD),
                danger: Color(0xFFF07B7B),
                warn: Color(0xFFEEC06C),
                heroGradient: [Color(0xFF3A2820), Color(0xFF4A3328)],
                heroInk: Color(0xFFFFF4EC),
                heroSubInk: Color(0xFFD6B7A6),
                heroBadgeBg: Color(0x30FFB48A),
                heroBadgeInk: Color(0xFFFFCBA9),
                heroBorder: Color(0x38FFB48A),
                markerSwipe: Color(0x40FFA87A),
                patternColor: Color(0xFFF4A982),
                auraColor: Color(0xFFFFB086),
                fabGradient: [Color(0xFFEBA580), Color(0xFFD48B65)],
                fabInk: Color(0xFF26140B),
                saveGradient: [Color(0xFFEBA580), Color(0xFFD48B65)],
                saveInk: Color(0xFF26140B),
                incomeGradient: [Color(0xFF6FD0AD), Color(0xFF49B28C)],
                keypadBg: Color(0xFF1C1715),
                keyBg: Color(0xFF29221E),
                keyFn: Color(0xFF221C18),
                segmentTrack: Color(0x17FFDCC6),
                segmentActive: Color(0xFF342B26),
                waterOk: Color(0x2CEBA580),
                waterWarn: Color(0x2CEEC06C),
                waterOver: Color(0x33F07B7B),
                chartColors: [
                  Color(0xFFEBA580),
                  Color(0xFF6FD0AD),
                  Color(0xFF89B4D8),
                  Color(0xFFC2A6E8),
                  Color(0xFFF096A0),
                  Color(0xFF9AC994),
                  Color(0xFFE8C87A),
                  Color(0xFFA89990),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.cat,
                brightness: Brightness.light,
                canvas: Color(0xFFFAF5EE),
                card: Color(0xFFFFFFFF),
                surface2: Color(0xFFF4ECE1),
                dockSurface: Color(0xE6FFFCF8),
                headerGlass: Color(0xE8FAF5EE),
                border: Color(0x1EBC8060),
                borderStrong: Color(0x34BC8060),
                ink: Color(0xFF38271E),
                ink2: Color(0xFF7D6659),
                ink3: Color(0xFFAE988C),
                brandColor: Color(0xFFD48E6C),
                brandDeep: Color(0xFFB57050),
                brandSoft: Color(0x22D48E6C),
                income: Color(0xFF45A382),
                incomeSoft: Color(0x2045A382),
                danger: Color(0xFFD65E5E),
                warn: Color(0xFFC99038),
                heroGradient: [Color(0xFFF2D6C4), Color(0xFFF7E4D8)],
                heroInk: Color(0xFF3A2920),
                heroSubInk: Color(0xFF7B6254),
                heroBadgeBg: Color(0x99FFFFFF),
                heroBadgeInk: Color(0xFFA36143),
                heroBorder: Color(0x42C4886A),
                markerSwipe: Color(0x47D89472),
                patternColor: Color(0xFFE29B74),
                auraColor: Color(0xFFFFCCAC),
                fabGradient: [Color(0xFFDC9876), Color(0xFFCA8360)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFFDC9876), Color(0xFFCA8360)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFF56B492), Color(0xFF419A7A)],
                keypadBg: Color(0xFFF4EAE0),
                keyBg: Color(0xFFFFFFFF),
                keyFn: Color(0xFFECE0D4),
                segmentTrack: Color(0x16BC8060),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x26D48E6C),
                waterWarn: Color(0x28C99038),
                waterOver: Color(0x26D65E5E),
                chartColors: [
                  Color(0xFFD48E6C),
                  Color(0xFF4FA888),
                  Color(0xFF6FA0C4),
                  Color(0xFF9C88CC),
                  Color(0xFFD9828E),
                  Color(0xFF7CB080),
                  Color(0xFFD4A85C),
                  Color(0xFF9C8B80),
                ],
              ),
      AppThemeStyle.dog =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.dog,
                brightness: Brightness.dark,
                canvas: Color(0xFF16140F),
                card: Color(0xFF211D16),
                surface2: Color(0xFF2B261E),
                dockSurface: Color(0xE6211D16),
                headerGlass: Color(0xE816140F),
                border: Color(0x1AF8E8C0),
                borderStrong: Color(0x2EF8E8C0),
                ink: Color(0xFFF8F2E6),
                ink2: Color(0xFFC0B39B),
                ink3: Color(0xFF877B66),
                brandColor: Color(0xFFE2BC74),
                brandDeep: Color(0xFFC69E56),
                brandSoft: Color(0x2AE2BC74),
                income: Color(0xFF6FD0AD),
                incomeSoft: Color(0x266FD0AD),
                danger: Color(0xFFF07B7B),
                warn: Color(0xFFEEC06C),
                heroGradient: [Color(0xFF362D1D), Color(0xFF463A24)],
                heroInk: Color(0xFFFCF6E8),
                heroSubInk: Color(0xFFD1C2A4),
                heroBadgeBg: Color(0x30F2CC7A),
                heroBadgeInk: Color(0xFFFAE0A5),
                heroBorder: Color(0x38F2CC7A),
                markerSwipe: Color(0x40F2CA72),
                patternColor: Color(0xFFE8C074),
                auraColor: Color(0xFFF2CA74),
                fabGradient: [Color(0xFFE5C17B), Color(0xFFCCA358)],
                fabInk: Color(0xFF241908),
                saveGradient: [Color(0xFFE5C17B), Color(0xFFCCA358)],
                saveInk: Color(0xFF241908),
                incomeGradient: [Color(0xFF6FD0AD), Color(0xFF49B28C)],
                keypadBg: Color(0xFF1B1812),
                keyBg: Color(0xFF28231B),
                keyFn: Color(0xFF211D16),
                segmentTrack: Color(0x17F8E8C0),
                segmentActive: Color(0xFF332D22),
                waterOk: Color(0x2CE2BC74),
                waterWarn: Color(0x2CEEC06C),
                waterOver: Color(0x33F07B7B),
                chartColors: [
                  Color(0xFFE2BC74),
                  Color(0xFF6FD0AD),
                  Color(0xFF89B4D8),
                  Color(0xFFC2A6E8),
                  Color(0xFFF096A0),
                  Color(0xFF9AC994),
                  Color(0xFFE8A67A),
                  Color(0xFFA89F90),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.dog,
                brightness: Brightness.light,
                canvas: Color(0xFFF9F5EB),
                card: Color(0xFFFFFFFF),
                surface2: Color(0xFFF2ECDC),
                dockSurface: Color(0xE6FFFDF7),
                headerGlass: Color(0xE8F9F5EB),
                border: Color(0x1EB08E54),
                borderStrong: Color(0x34B08E54),
                ink: Color(0xFF342B1D),
                ink2: Color(0xFF7A6E5A),
                ink3: Color(0xFFABA08A),
                brandColor: Color(0xFFC59C5B),
                brandDeep: Color(0xFFA67E40),
                brandSoft: Color(0x22C59C5B),
                income: Color(0xFF45A382),
                incomeSoft: Color(0x2045A382),
                danger: Color(0xFFD65E5E),
                warn: Color(0xFFC99038),
                heroGradient: [Color(0xFFEFE0BE), Color(0xFFF7EED8)],
                heroInk: Color(0xFF352C1D),
                heroSubInk: Color(0xFF786A50),
                heroBadgeBg: Color(0xA0FFFFFF),
                heroBadgeInk: Color(0xFF8C692F),
                heroBorder: Color(0x42BC985C),
                markerSwipe: Color(0x4CD0AA68),
                patternColor: Color(0xFFD4AA60),
                auraColor: Color(0xFFF6DC9E),
                fabGradient: [Color(0xFFCEA665), Color(0xFFBC9250)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFFCEA665), Color(0xFFBC9250)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFF56B492), Color(0xFF419A7A)],
                keypadBg: Color(0xFFF3ECDD),
                keyBg: Color(0xFFFFFFFF),
                keyFn: Color(0xFFEAE0CC),
                segmentTrack: Color(0x16B08E54),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x26C59C5B),
                waterWarn: Color(0x28C99038),
                waterOver: Color(0x26D65E5E),
                chartColors: [
                  Color(0xFFC59C5B),
                  Color(0xFF4FA888),
                  Color(0xFF6FA0C4),
                  Color(0xFF9C88CC),
                  Color(0xFFD9828E),
                  Color(0xFF7CB080),
                  Color(0xFFD48E6C),
                  Color(0xFF9C9380),
                ],
              ),
      AppThemeStyle.panda =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.panda,
                brightness: Brightness.dark,
                canvas: Color(0xFF0F1513),
                card: Color(0xFF18211D),
                surface2: Color(0xFF212E28),
                dockSurface: Color(0xE618211D),
                headerGlass: Color(0xE80F1513),
                border: Color(0x1AC4F4E0),
                borderStrong: Color(0x2EC4F4E0),
                ink: Color(0xFFECF7F2),
                ink2: Color(0xFF9BB5AA),
                ink3: Color(0xFF6A8378),
                brandColor: Color(0xFF7CCBA9),
                brandDeep: Color(0xFF5CAE8B),
                brandSoft: Color(0x2A7CCBA9),
                income: Color(0xFFEEA872),
                incomeSoft: Color(0x26EEA872),
                danger: Color(0xFFF07B7B),
                warn: Color(0xFFEEC06C),
                heroGradient: [Color(0xFF1C352B), Color(0xFF264739)],
                heroInk: Color(0xFFEFFAF5),
                heroSubInk: Color(0xFFA5CBB9),
                heroBadgeBg: Color(0x307CE2B8),
                heroBadgeInk: Color(0xFFB4F2D8),
                heroBorder: Color(0x387CE2B8),
                markerSwipe: Color(0x4072E0B4),
                patternColor: Color(0xFF74D4AD),
                auraColor: Color(0xFF72E0B4),
                fabGradient: [Color(0xFF84D4B2), Color(0xFF62B592)],
                fabInk: Color(0xFF09241A),
                saveGradient: [Color(0xFF84D4B2), Color(0xFF62B592)],
                saveInk: Color(0xFF09241A),
                incomeGradient: [Color(0xFFEEA872), Color(0xFFD48850)],
                keypadBg: Color(0xFF131B18),
                keyBg: Color(0xFF1E2924),
                keyFn: Color(0xFF18221D),
                segmentTrack: Color(0x17C4F4E0),
                segmentActive: Color(0xFF26362F),
                waterOk: Color(0x2C7CCBA9),
                waterWarn: Color(0x2CEEC06C),
                waterOver: Color(0x33F07B7B),
                chartColors: [
                  Color(0xFF7CCBA9),
                  Color(0xFFEEA872),
                  Color(0xFF89B4D8),
                  Color(0xFFC2A6E8),
                  Color(0xFFF096A0),
                  Color(0xFFA2D196),
                  Color(0xFFE8C87A),
                  Color(0xFF8CA69C),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.panda,
                brightness: Brightness.light,
                canvas: Color(0xFFF0F6F2),
                card: Color(0xFFFFFFFF),
                surface2: Color(0xFFE4EFE8),
                dockSurface: Color(0xE6F9FEFB),
                headerGlass: Color(0xE8F0F6F2),
                border: Color(0x1E4A9E7C),
                borderStrong: Color(0x344A9E7C),
                ink: Color(0xFF1C3128),
                ink2: Color(0xFF5A7368),
                ink3: Color(0xFF8DA499),
                brandColor: Color(0xFF5EA587),
                brandDeep: Color(0xFF458A6D),
                brandSoft: Color(0x225EA587),
                income: Color(0xFFD48E5C),
                incomeSoft: Color(0x20D48E5C),
                danger: Color(0xFFD65E5E),
                warn: Color(0xFFC99038),
                heroGradient: [Color(0xFFC9E4D7), Color(0xFFE0F1E8)],
                heroInk: Color(0xFF1C3128),
                heroSubInk: Color(0xFF537064),
                heroBadgeBg: Color(0xA0FFFFFF),
                heroBadgeInk: Color(0xFF387A5F),
                heroBorder: Color(0x425EA587),
                markerSwipe: Color(0x4768B292),
                patternColor: Color(0xFF54B890),
                auraColor: Color(0xFF9AEAC8),
                fabGradient: [Color(0xFF69B092), Color(0xFF549A7C)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFF69B092), Color(0xFF549A7C)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFFDF9B6A), Color(0xFFC9804E)],
                keypadBg: Color(0xFFE6F0EA),
                keyBg: Color(0xFFFFFFFF),
                keyFn: Color(0xFFD9E8E0),
                segmentTrack: Color(0x164A9E7C),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x265EA587),
                waterWarn: Color(0x28C99038),
                waterOver: Color(0x26D65E5E),
                chartColors: [
                  Color(0xFF5EA587),
                  Color(0xFFD48E5C),
                  Color(0xFF6FA0C4),
                  Color(0xFF9C88CC),
                  Color(0xFFD9828E),
                  Color(0xFF7CB080),
                  Color(0xFFD4B05C),
                  Color(0xFF809C90),
                ],
              ),
      AppThemeStyle.capybara =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.capybara,
                brightness: Brightness.dark,
                canvas: Color(0xFF161310),
                card: Color(0xFF211C18),
                surface2: Color(0xFF2B241F),
                dockSurface: Color(0xE6211C18),
                headerGlass: Color(0xE8161310),
                border: Color(0x1AF2DECA),
                borderStrong: Color(0x2EF2DECA),
                ink: Color(0xFFF6EFE7),
                ink2: Color(0xFFBBA897),
                ink3: Color(0xFF857466),
                brandColor: Color(0xFFDEA674),
                brandDeep: Color(0xFFC28855),
                brandSoft: Color(0x2ADEA674),
                income: Color(0xFF75C892),
                incomeSoft: Color(0x2675C892),
                danger: Color(0xFFF07B7B),
                warn: Color(0xFFEEC06C),
                heroGradient: [Color(0xFF34271D), Color(0xFF453427)],
                heroInk: Color(0xFFFAF3EB),
                heroSubInk: Color(0xFFCEB9A6),
                heroBadgeBg: Color(0x30EEB47A),
                heroBadgeInk: Color(0xFFF7D1A8),
                heroBorder: Color(0x38EEB47A),
                markerSwipe: Color(0x40EEB070),
                patternColor: Color(0xFFE2AA74),
                auraColor: Color(0xFFEEB070),
                fabGradient: [Color(0xFFE5AE7A), Color(0xFFCA8E56)],
                fabInk: Color(0xFF241407),
                saveGradient: [Color(0xFFE5AE7A), Color(0xFFCA8E56)],
                saveInk: Color(0xFF241407),
                incomeGradient: [Color(0xFF75C892), Color(0xFF52AC72)],
                keypadBg: Color(0xFF1A1613),
                keyBg: Color(0xFF27211C),
                keyFn: Color(0xFF211C17),
                segmentTrack: Color(0x17F2DECA),
                segmentActive: Color(0xFF322A23),
                waterOk: Color(0x2CDEA674),
                waterWarn: Color(0x2CEEC06C),
                waterOver: Color(0x33F07B7B),
                chartColors: [
                  Color(0xFFDEA674),
                  Color(0xFF75C892),
                  Color(0xFF89B4D8),
                  Color(0xFFC2A6E8),
                  Color(0xFFF096A0),
                  Color(0xFF9AC994),
                  Color(0xFFE8C87A),
                  Color(0xFFA8988C),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.capybara,
                brightness: Brightness.light,
                canvas: Color(0xFFF6F2EB),
                card: Color(0xFFFFFEFC),
                surface2: Color(0xFFEDE6DA),
                dockSurface: Color(0xE6FFFDF9),
                headerGlass: Color(0xE8F6F2EB),
                border: Color(0x1E9A7656),
                borderStrong: Color(0x349A7656),
                ink: Color(0xFF33281F),
                ink2: Color(0xFF786759),
                ink3: Color(0xFFA69688),
                brandColor: Color(0xFFB88D68),
                brandDeep: Color(0xFF9B714D),
                brandSoft: Color(0x22B88D68),
                income: Color(0xFF50A272),
                incomeSoft: Color(0x2050A272),
                danger: Color(0xFFD65E5E),
                warn: Color(0xFFC99038),
                heroGradient: [Color(0xFFE7D8C7), Color(0xFFF2E8DC)],
                heroInk: Color(0xFF34281E),
                heroSubInk: Color(0xFF786454),
                heroBadgeBg: Color(0xA3FFFFFF),
                heroBadgeInk: Color(0xFF9A6638),
                heroBorder: Color(0x42B08A68),
                markerSwipe: Color(0x52ECB070),
                patternColor: Color(0xFFCE9562),
                auraColor: Color(0xFFF2CA9E),
                fabGradient: [Color(0xFFD09C6E), Color(0xFFBE8859)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFFD09C6E), Color(0xFFBE8859)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFF60B282), Color(0xFF4A986A)],
                keypadBg: Color(0xFFEFE7DC),
                keyBg: Color(0xFFFFFEFC),
                keyFn: Color(0xFFE6DBCD),
                segmentTrack: Color(0x169A7656),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x26B88D68),
                waterWarn: Color(0x28C99038),
                waterOver: Color(0x26D65E5E),
                chartColors: [
                  Color(0xFFC79263),
                  Color(0xFF50A272),
                  Color(0xFF6FA0C4),
                  Color(0xFF9C88CC),
                  Color(0xFFD9828E),
                  Color(0xFF7CB080),
                  Color(0xFFD4AC64),
                  Color(0xFF9C8E82),
                ],
              ),
      AppThemeStyle.taro =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.taro,
                brightness: Brightness.dark,
                canvas: Color(0xFF110F1A),
                card: Color(0xFF1B1827),
                surface2: Color(0xFF252036),
                dockSurface: Color(0xE61B1827),
                headerGlass: Color(0xE8110F1A),
                border: Color(0x1AE2D6FC),
                borderStrong: Color(0x2EE2D6FC),
                ink: Color(0xFFF3F0FC),
                ink2: Color(0xFFAEA3C7),
                ink3: Color(0xFF7B7096),
                brandColor: Color(0xFFB9A6EB),
                brandDeep: Color(0xFF9A84D6),
                brandSoft: Color(0x2AB9A6EB),
                income: Color(0xFF6FCDB6),
                incomeSoft: Color(0x266FCDB6),
                danger: Color(0xFFF07B94),
                warn: Color(0xFFEEC06C),
                heroGradient: [Color(0xFF292142), Color(0xFF372C59)],
                heroInk: Color(0xFFF6F3FE),
                heroSubInk: Color(0xFFC1B4E0),
                heroBadgeBg: Color(0x30C4AEFC),
                heroBadgeInk: Color(0xFFDFD2FC),
                heroBorder: Color(0x38C4AEFC),
                markerSwipe: Color(0x40BCA4FA),
                patternColor: Color(0xFFBFA8F6),
                auraColor: Color(0xFFBCA6FA),
                fabGradient: [Color(0xFFC2B0F0), Color(0xFFA28CE0)],
                fabInk: Color(0xFF1B1234),
                saveGradient: [Color(0xFFC2B0F0), Color(0xFFA28CE0)],
                saveInk: Color(0xFF1B1234),
                incomeGradient: [Color(0xFF6FCDB6), Color(0xFF4CB098)],
                keypadBg: Color(0xFF161221),
                keyBg: Color(0xFF221D32),
                keyFn: Color(0xFF1B1728),
                segmentTrack: Color(0x17E2D6FC),
                segmentActive: Color(0xFF2C2640),
                waterOk: Color(0x2CB9A6EB),
                waterWarn: Color(0x2CEEC06C),
                waterOver: Color(0x33F07B94),
                chartColors: [
                  Color(0xFFB9A6EB),
                  Color(0xFF6FCDB6),
                  Color(0xFF89B4D8),
                  Color(0xFFF09AC4),
                  Color(0xFFEBA880),
                  Color(0xFF9AC994),
                  Color(0xFFE8C87A),
                  Color(0xFF9B92B0),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.taro,
                brightness: Brightness.light,
                canvas: Color(0xFFF4F1FA),
                card: Color(0xFFFFFFFF),
                surface2: Color(0xFFEAE4F6),
                dockSurface: Color(0xE6FCFAFF),
                headerGlass: Color(0xE8F4F1FA),
                border: Color(0x1E9078D6),
                borderStrong: Color(0x349078D6),
                ink: Color(0xFF28213D),
                ink2: Color(0xFF6D638A),
                ink3: Color(0xFF9F96B8),
                brandColor: Color(0xFF9281C4),
                brandDeep: Color(0xFF7766AB),
                brandSoft: Color(0x229281C4),
                income: Color(0xFF45A68E),
                incomeSoft: Color(0x2045A68E),
                danger: Color(0xFFD6607B),
                warn: Color(0xFFC99038),
                heroGradient: [Color(0xFFDCD4F0), Color(0xFFEBE6F7)],
                heroInk: Color(0xFF29223D),
                heroSubInk: Color(0xFF665C82),
                heroBadgeBg: Color(0xA0FFFFFF),
                heroBadgeInk: Color(0xFF68579E),
                heroBorder: Color(0x429281C4),
                markerSwipe: Color(0x479A8ACC),
                patternColor: Color(0xFF9A82E2),
                auraColor: Color(0xFFCCBCFC),
                fabGradient: [Color(0xFF9E8DCF), Color(0xFF8776B9)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFF9E8DCF), Color(0xFF8776B9)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFF56B69E), Color(0xFF419B84)],
                keypadBg: Color(0xFFECE6F7),
                keyBg: Color(0xFFFFFFFF),
                keyFn: Color(0xFFE2D9F4),
                segmentTrack: Color(0x169078D6),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x269281C4),
                waterWarn: Color(0x28C99038),
                waterOver: Color(0x26D6607B),
                chartColors: [
                  Color(0xFF9281C4),
                  Color(0xFF45A68E),
                  Color(0xFF6FA0C4),
                  Color(0xFFD984AE),
                  Color(0xFFD4936C),
                  Color(0xFF7CB080),
                  Color(0xFFD4B25C),
                  Color(0xFF9088A6),
                ],
              ),
      AppThemeStyle.matcha =>
        dark
            ? const AppPalette(
                style: AppThemeStyle.matcha,
                brightness: Brightness.dark,
                canvas: Color(0xFF0F1510),
                card: Color(0xFF182119),
                surface2: Color(0xFF212D23),
                dockSurface: Color(0xE6182119),
                headerGlass: Color(0xE80F1510),
                border: Color(0x1AD4F2D8),
                borderStrong: Color(0x2ED4F2D8),
                ink: Color(0xFFEEF6EE),
                ink2: Color(0xFF9EB5A1),
                ink3: Color(0xFF6D8370),
                brandColor: Color(0xFF8CC894),
                brandDeep: Color(0xFF6DAE75),
                brandSoft: Color(0x2A8CC894),
                income: Color(0xFFECA870),
                incomeSoft: Color(0x26ECA870),
                danger: Color(0xFFF07B7B),
                warn: Color(0xFFEEC06C),
                heroGradient: [Color(0xFF1E3422), Color(0xFF29462E)],
                heroInk: Color(0xFFF1FAF2),
                heroSubInk: Color(0xFFAECAA9),
                heroBadgeBg: Color(0x3092DA9A),
                heroBadgeInk: Color(0xFFC2F0C7),
                heroBorder: Color(0x3892DA9A),
                markerSwipe: Color(0x408ADA94),
                patternColor: Color(0xFF8CD095),
                auraColor: Color(0xFF8ADA94),
                fabGradient: [Color(0xFF94D29B), Color(0xFF73B57B)],
                fabInk: Color(0xFF0D2210),
                saveGradient: [Color(0xFF94D29B), Color(0xFF73B57B)],
                saveInk: Color(0xFF0D2210),
                incomeGradient: [Color(0xFFECA870), Color(0xFFD2884E)],
                keypadBg: Color(0xFF131B14),
                keyBg: Color(0xFF1E2920),
                keyFn: Color(0xFF182119),
                segmentTrack: Color(0x17D4F2D8),
                segmentActive: Color(0xFF263629),
                waterOk: Color(0x2C8CC894),
                waterWarn: Color(0x2CEEC06C),
                waterOver: Color(0x33F07B7B),
                chartColors: [
                  Color(0xFF8CC894),
                  Color(0xFFECA870),
                  Color(0xFF89B4D8),
                  Color(0xFFC2A6E8),
                  Color(0xFFF096A0),
                  Color(0xFF72C9A8),
                  Color(0xFFE8C87A),
                  Color(0xFF8EA691),
                ],
              )
            : const AppPalette(
                style: AppThemeStyle.matcha,
                brightness: Brightness.light,
                canvas: Color(0xFFF0F6EF),
                card: Color(0xFFFFFFFF),
                surface2: Color(0xFFE5EFE3),
                dockSurface: Color(0xE6F9FEF9),
                headerGlass: Color(0xE8F0F6EF),
                border: Color(0x1E609A68),
                borderStrong: Color(0x34609A68),
                ink: Color(0xFF1F3022),
                ink2: Color(0xFF5D7461),
                ink3: Color(0xFF8FA593),
                brandColor: Color(0xFF6EA374),
                brandDeep: Color(0xFF538859),
                brandSoft: Color(0x226EA374),
                income: Color(0xFFD48E58),
                incomeSoft: Color(0x20D48E58),
                danger: Color(0xFFD65E5E),
                warn: Color(0xFFC99038),
                heroGradient: [Color(0xFFCFE4CE), Color(0xFFE3F0E2)],
                heroInk: Color(0xFF1F3022),
                heroSubInk: Color(0xFF546F58),
                heroBadgeBg: Color(0xA0FFFFFF),
                heroBadgeInk: Color(0xFF467A4D),
                heroBorder: Color(0x426EA374),
                markerSwipe: Color(0x477AB680),
                patternColor: Color(0xFF6BB474),
                auraColor: Color(0xFFB2E8B4),
                fabGradient: [Color(0xFF79AE7F), Color(0xFF629768)],
                fabInk: Color(0xFFFFFFFF),
                saveGradient: [Color(0xFF79AE7F), Color(0xFF629768)],
                saveInk: Color(0xFFFFFFFF),
                incomeGradient: [Color(0xFFDF9B66), Color(0xFFC8804A)],
                keypadBg: Color(0xFFE7F0E6),
                keyBg: Color(0xFFFFFFFF),
                keyFn: Color(0xFFDAE8D8),
                segmentTrack: Color(0x16609A68),
                segmentActive: Color(0xFFFFFFFF),
                waterOk: Color(0x266EA374),
                waterWarn: Color(0x28C99038),
                waterOver: Color(0x26D65E5E),
                chartColors: [
                  Color(0xFF6EA374),
                  Color(0xFFD48E58),
                  Color(0xFF6FA0C4),
                  Color(0xFF9C88CC),
                  Color(0xFFD9828E),
                  Color(0xFF5DA890),
                  Color(0xFFD4B25C),
                  Color(0xFF849C87),
                ],
              ),
    };
  }

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>() ??
        resolve(AppThemeStyle.emerald, theme.brightness);
  }

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return t < 0.5 ? this : other;
  }
}

bool night(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color secondaryInk(BuildContext c) => AppPalette.of(c).ink2;
Color mutedInk(BuildContext c) => AppPalette.of(c).ink3;
Color expenseInk(BuildContext c) => AppPalette.of(c).brandColor;
Color incomeInk(BuildContext c) => AppPalette.of(c).income;
Color hairline(BuildContext c) => AppPalette.of(c).border;
Color softSurface(BuildContext c) => AppPalette.of(c).card;

String moneySymbol(String currency) => switch (currency) {
  'CNY' => '¥',
  'USD' => '\$',
  'HKD' => 'HK\$',
  'EUR' => '€',
  'GBP' => '£',
  'JPY' => '¥',
  _ => currency,
};

ThemeData appTheme(
  Brightness brightness, {
  AppThemeStyle style = AppThemeStyle.emerald,
}) {
  final p = AppPalette.resolve(style, brightness);
  final dark = p.isDark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.brandColor,
        brightness: brightness,
      ).copyWith(
        primary: p.brandColor,
        onPrimary: p.fabInk,
        primaryContainer: p.brandSoft,
        onPrimaryContainer: p.brandColor,
        surface: p.canvas,
        surfaceContainerLowest: p.card,
        surfaceContainerLow: p.surface2,
        surfaceContainerHigh: p.card,
        error: p.danger,
        onSurface: p.ink,
        onSurfaceVariant: p.ink2,
        outline: p.ink3,
        outlineVariant: p.borderStrong,
        secondaryContainer: p.surface2,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: base.textTheme.copyWith(
      bodyLarge: TextStyle(fontSize: 14, color: p.ink),
      bodyMedium: TextStyle(fontSize: 13, color: p.ink, height: 1.4),
      bodySmall: TextStyle(fontSize: 11, color: p.ink2, height: 1.4),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: p.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      labelLarge: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
    ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: appSystemBars(brightness),
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      toolbarHeight: 46,
      centerTitle: true,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: p.ink,
      ),
      iconTheme: IconThemeData(size: 20, color: p.ink),
    ),
    iconTheme: IconThemeData(size: 19, color: p.ink2),
    listTileTheme: ListTileThemeData(
      dense: true,
      minVerticalPadding: 7,
      iconColor: p.ink2,
      titleTextStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: p.ink,
      ),
      subtitleTextStyle: TextStyle(fontSize: 11.5, color: p.ink2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      isDense: true,
      labelStyle: TextStyle(fontSize: 12, color: p.ink2),
      hintStyle: TextStyle(fontSize: 12.5, color: p.ink3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.brandColor, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.brandColor,
        foregroundColor: p.fabInk,
        minimumSize: const Size(48, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.borderStrong),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brandColor,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        minimumSize: const Size(40, 36),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.brandSoft
              : p.surface2,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.brandColor : p.ink2,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.borderStrong)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.brandSoft,
      side: BorderSide(color: p.borderStrong),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      labelStyle: TextStyle(fontSize: 11.5, color: p.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
    ),
    dividerTheme: DividerThemeData(
      color: p.border,
      thickness: 0.7,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.canvas,
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.fabInk
            : (dark ? p.ink2 : Colors.white),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.brandColor
            : p.segmentTrack,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}

class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (!p.style.isCute || p.patternColor == null || p.auraColor == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: p.canvas),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: p.canvas),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ThemeWallpaperPainter(
                    style: p.style,
                    patternColor: p.patternColor!,
                    auraColor: p.auraColor!,
                    isDark: p.isDark,
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 页面背景必须随路由一起移动，避免 iOS 侧滑时透出上一页文字。
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({required WidgetBuilder builder})
    : super(builder: (context) => AppBackdrop(child: builder(context)));
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final Color? color;
  final bool bordered;
  final bool elevated;
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.blur = false,
    this.color,
    this.bordered = true,
    this.elevated = true,
  });
  @override
  Widget build(BuildContext c) {
    final p = AppPalette.of(c);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: blur
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: p.isDark ? 0.36 : 0.09),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: p.isDark ? 0.16 : 0.04),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ]
            : elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: p.isDark ? 0.22 : 0.032,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          enabled: blur,
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? (blur ? p.dockSurface : p.card),
              borderRadius: BorderRadius.circular(radius),
              border: bordered
                  ? Border.all(
                      color: blur ? p.borderStrong : p.border,
                      width: 0.9,
                    )
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// 现代胶囊分段控件（替代默认生硬边框 SegmentedButton）
class AppSegmentControl<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final bool expand;
  final EdgeInsetsGeometry itemPadding;
  final double fontSize;
  const AppSegmentControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.expand = false,
    this.itemPadding = const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
    this.fontSize = 12,
  });
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    Widget buildItem((T, String) item) {
      final active = item.$1 == value;
      final button = Semantics(
        selected: active,
        button: true,
        label: item.$2,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(item.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: itemPadding,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? p.segmentActive : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: p.isDark ? 0.28 : 0.08,
                        ),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              item.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? p.ink : p.ink2,
              ),
            ),
          ),
        ),
      );
      return expand ? Expanded(child: button) : button;
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.segmentTrack,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [for (final item in items) buildItem(item)],
      ),
    );
  }
}

class CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final Color? color;
  final Color? fill;
  const CircleAction({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color,
    this.fill,
  });
  @override
  Widget build(BuildContext c) {
    final p = AppPalette.of(c);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.all(3),
      ),
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill ?? p.card,
          border: Border.all(
            color: fill != null ? Colors.transparent : p.borderStrong,
            width: 0.8,
          ),
        ),
        child: Icon(icon, size: 17, color: color ?? p.ink),
      ),
    );
  }
}

class CategoryBadge extends StatelessWidget {
  final String? name, icon, color;
  final double size;
  const CategoryBadge({
    super.key,
    this.name,
    this.icon,
    this.color,
    this.size = 34,
  });
  @override
  Widget build(BuildContext c) {
    final p = AppPalette.of(c);
    final key = icon ?? name ?? '';
    var (bg, fg) = switch (key) {
      'restaurant' ||
      '餐饮' ||
      'gift' ||
      '人情' => (const Color(0xFFF6E7DB), const Color(0xFFC86A2B)),
      'bus' ||
      '交通' ||
      'flight' ||
      '旅行' => (const Color(0xFFE0ECF4), const Color(0xFF3B82A6)),
      'shopping' ||
      '购物' ||
      '日用' => (const Color(0xFFECE6F5), const Color(0xFF7E6BB5)),
      'home' || '居住' => (const Color(0xFFF5ECDC), const Color(0xFFB57A2A)),
      'work' || '工资' => (p.incomeSoft, p.income),
      _ => (p.brandSoft, p.brandColor),
    };
    if (color != null && color != '#126C62' && color != '#20836A') {
      fg = dictionaryColor(color);
      bg = fg.withValues(alpha: 0.12);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.isDark ? fg.withValues(alpha: 0.18) : bg,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Center(
        child: CatalogIcon(
          key,
          size: size * .54,
          color: p.isDark ? Color.lerp(fg, Colors.white, .28) : fg,
        ),
      ),
    );
  }
}

Widget panel(Widget child) => Builder(
  builder: (c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassPanel(
      radius: isAndroidPlatform ? 20 : 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: child,
    ),
  ),
);

Widget hint(String text) => Builder(
  builder: (c) => Text(
    text,
    style: TextStyle(fontSize: 11, color: secondaryInk(c), height: 1.45),
  ),
);
const space = SizedBox(height: 10);

IconData dictionaryIcon(String? key) => switch (key) {
  'transfer' => CupertinoIcons.arrow_right_arrow_left,
  'restaurant' || '餐饮' => Icons.restaurant_outlined,
  'bus' || '交通' => Icons.directions_bus_outlined,
  'book' || '学习' => CupertinoIcons.book,
  'game' || '娱乐' => CupertinoIcons.game_controller,
  'shopping' || '购物' || '日用' => CupertinoIcons.bag,
  'home' || '居住' => CupertinoIcons.house,
  'flight' || '旅行' => CupertinoIcons.airplane,
  'favorite' || '健康' => CupertinoIcons.heart,
  'work' || '工资' => CupertinoIcons.briefcase,
  'gift' || '人情' => CupertinoIcons.gift,
  _ => CupertinoIcons.leaf_arrow_circlepath,
};

Color dictionaryColor(String? value) =>
    Color(int.parse((value ?? '#0E7460').substring(1), radix: 16) | 0xff000000);

Future<bool> approve(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

void message(BuildContext context, Object error) => notifyApp(
  error.toString().replaceFirst('FormatException: ', ''),
  error: error is Exception,
);

/// 弹层通过顶部握柄拖动；背景点击及系统返回仅放弃当前弹层草稿。
Future<T?> glassSheet<T>(
  BuildContext context,
  Widget child, {
  double height = .84,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .28),
  isDismissible: true,
  enableDrag: true,
  builder: (c) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
    child: MediaQuery.removeViewInsets(
      context: c,
      removeBottom: true,
      child: _GlassSheet(height: height, child: child),
    ),
  ),
);

class _GlassSheet extends StatefulWidget {
  final Widget child;
  final double height;
  const _GlassSheet({required this.child, required this.height});
  @override
  State<_GlassSheet> createState() => _GlassSheetState();
}

class _GlassSheetState extends State<_GlassSheet> {
  late double fraction = widget.height;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * fraction,
      child: Material(
        color: p.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => setState(
                () => fraction =
                    (fraction - d.delta.dy / MediaQuery.sizeOf(context).height)
                        .clamp(.2, .94),
              ),
              onVerticalDragEnd: (d) {
                if (fraction < .3 || d.primaryVelocity! > 1000) {
                  Navigator.pop(context);
                } else {
                  setState(() => fraction = fraction < .6 ? .45 : widget.height);
                }
              },
              onTap: () =>
                  setState(() => fraction = fraction < .6 ? widget.height : .45),
              child: SizedBox(
                height: 28,
                width: double.infinity,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: p.borderStrong,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

class SwipeEntry extends StatefulWidget {
  final Widget child;
  final void Function(String) action;
  final bool canRefund, canTemplate;
  const SwipeEntry({
    super.key,
    required this.child,
    required this.action,
    this.canRefund = false,
    this.canTemplate = false,
  });
  @override
  State<SwipeEntry> createState() => _SwipeEntryState();
}

class _SwipeEntryState extends State<SwipeEntry> {
  double offset = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final width = (c.maxWidth * .78).clamp(180.0, 260.0);
      return ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: width,
                  child: Row(
                    children: [
                      for (final action in [
                        '复制',
                        '编辑',
                        if (widget.canRefund) '退款',
                        '删除',
                      ])
                        Expanded(
                          child: SizedBox.expand(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: const RoundedRectangleBorder(),
                                foregroundColor: Colors.white,
                                backgroundColor: switch (action) {
                                  '复制' => const Color(0xFFB89F63),
                                  '编辑' => const Color(0xFFD98C4E),
                                  '退款' => const Color(0xFF2F8A7D),
                                  _ => const Color(0xFFD64545),
                                },
                              ),
                              onPressed: () {
                                setState(() => offset = 0);
                                widget.action(action);
                              },
                              child: Text(
                                action,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              transform: Matrix4.translationValues(offset, 0, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () async {
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    builder: (c) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final name in [
                            '复制',
                            '编辑',
                            if (widget.canTemplate) '存为模板',
                            if (widget.canRefund) '退款',
                            '删除',
                          ])
                            ListTile(
                              title: Text(name),
                              onTap: () => Navigator.pop(c, name),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (selected != null && mounted) {
                    setState(() => offset = 0);
                    widget.action(selected);
                  }
                },
                onHorizontalDragUpdate: (d) => setState(
                  () => offset = (offset + d.delta.dx).clamp(-width, 0),
                ),
                onHorizontalDragEnd: (_) =>
                    setState(() => offset = offset < -width / 3 ? -width : 0),
                child: Material(
                  color: softSurface(context),
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Wait for the exit animation before callers dispose form controllers.
Future<T?> settledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final value = await Navigator.of(context).push(route);
  await route.completed;
  return value;
}
