/// 全项目图标统一入口。
///
/// 调用点只使用语义名称，图标库或图标权重需要调整时只改这里。默认使用
/// Phosphor Regular；已选中、已收藏等状态使用 [AppIconsFilled] 的 Fill 变体。
library;

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

abstract final class AppIcons {
  static const IconData arrowLeft = PhosphorIconsRegular.arrowLeft;
  static const IconData arrowRight = PhosphorIconsRegular.arrowRight;
  static const IconData bookmark = PhosphorIconsRegular.bookmarkSimple;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData chevronLeft = PhosphorIconsRegular.caretLeft;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData error = PhosphorIconsRegular.warningCircle;
  static const IconData folderFavorite = PhosphorIconsRegular.folder;
  static const IconData history = PhosphorIconsRegular.clockCounterClockwise;
  static const IconData hourglass = PhosphorIconsRegular.hourglass;
  static const IconData list = PhosphorIconsRegular.listBullets;
  static const IconData logOut = PhosphorIconsRegular.signOut;
  static const IconData moon = PhosphorIconsRegular.moon;
  static const IconData person = PhosphorIconsRegular.user;
  static const IconData play = PhosphorIconsRegular.play;
  static const IconData playlist = PhosphorIconsRegular.playlist;
  static const IconData refresh = PhosphorIconsRegular.arrowClockwise;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData settings = PhosphorIconsRegular.gear;
  static const IconData smartphone = PhosphorIconsRegular.deviceMobile;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData sun = PhosphorIconsRegular.sun;
  static const IconData undo = PhosphorIconsRegular.arrowBendUpLeft;
  static const IconData video = PhosphorIconsRegular.videoCamera;
}

/// 选中态图标。不要用颜色代替实心/空心的状态差异。
abstract final class AppIconsFilled {
  static const IconData star = PhosphorIconsFill.star;
}
