/// 全项目图标统一入口。
///
/// 调用点只使用语义名称，图标库或图标权重需要调整时只改这里。默认使用
/// Phosphor Regular；已选中、已收藏等状态使用 [AppIconsFilled] 的 Fill 变体。
library;

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

abstract final class AppIcons {
  static const IconData add = PhosphorIconsRegular.plus;
  static const IconData addCircle = PhosphorIconsRegular.plusCircle;
  static const IconData addLink = PhosphorIconsRegular.link;
  static const IconData addPhotos = PhosphorIconsRegular.images;
  static const IconData alarm = PhosphorIconsRegular.alarm;
  static const IconData album = PhosphorIconsRegular.disc;
  static const IconData arrowLeft = PhosphorIconsRegular.arrowLeft;
  static const IconData arrowRight = PhosphorIconsRegular.arrowRight;
  static const IconData arrowDown = PhosphorIconsRegular.arrowDown;
  static const IconData arrowUp = PhosphorIconsRegular.arrowUp;
  static const IconData arrowsLeftRight = PhosphorIconsRegular.arrowsLeftRight;
  static const IconData arrowsClockwise = PhosphorIconsRegular.arrowsClockwise;
  static const IconData alignCenter = PhosphorIconsRegular.textAlignCenter;
  static const IconData alignLeft = PhosphorIconsRegular.textAlignLeft;
  static const IconData alignRight = PhosphorIconsRegular.textAlignRight;
  static const IconData sparkle = PhosphorIconsRegular.sparkle;
  static const IconData magicWand = PhosphorIconsRegular.magicWand;
  static const IconData hardDrive = PhosphorIconsRegular.hardDrive;
  static const IconData chartBar = PhosphorIconsRegular.chartBar;
  static const IconData battery = PhosphorIconsRegular.batteryChargingVertical;
  static const IconData bookmark = PhosphorIconsRegular.bookmarkSimple;
  static const IconData calendar = PhosphorIconsRegular.calendar;
  static const IconData checkCircle = PhosphorIconsRegular.checkCircle;
  static const IconData checks = PhosphorIconsRegular.checks;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData chevronLeft = PhosphorIconsRegular.caretLeft;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData chevronUp = PhosphorIconsRegular.caretUp;
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData circle = PhosphorIconsRegular.circle;
  static const IconData cloud = PhosphorIconsRegular.cloud;
  static const IconData cloudCheck = PhosphorIconsRegular.cloudCheck;
  static const IconData cloudDownload = PhosphorIconsRegular.cloudArrowDown;
  static const IconData cloudOff = PhosphorIconsRegular.cloudSlash;
  static const IconData cloudUpload = PhosphorIconsRegular.cloudArrowUp;
  static const IconData copy = PhosphorIconsRegular.copy;
  static const IconData download = PhosphorIconsRegular.download;
  static const IconData dragHandle = PhosphorIconsRegular.dotsSixVertical;
  static const IconData error = PhosphorIconsRegular.warningCircle;
  static const IconData fire = PhosphorIconsRegular.fire;
  static const IconData file = PhosphorIconsRegular.file;
  static const IconData fileText = PhosphorIconsRegular.fileText;
  static const IconData folder = PhosphorIconsRegular.folder;
  static const IconData folderAdd = PhosphorIconsRegular.folderPlus;
  static const IconData folderOff = PhosphorIconsRegular.folderMinus;
  static const IconData folderOpen = PhosphorIconsRegular.folderOpen;
  static const IconData folderFavorite = PhosphorIconsRegular.folder;
  static const IconData grid = PhosphorIconsRegular.gridFour;
  static const IconData heart = PhosphorIconsRegular.heart;
  static const IconData history = PhosphorIconsRegular.clockCounterClockwise;
  static const IconData hourglass = PhosphorIconsRegular.hourglass;
  static const IconData image = PhosphorIconsRegular.image;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData list = PhosphorIconsRegular.listBullets;
  static const IconData listNumbers = PhosphorIconsRegular.listNumbers;
  static const IconData locate = PhosphorIconsRegular.crosshair;
  static const IconData logOut = PhosphorIconsRegular.signOut;
  static const IconData mapPin = PhosphorIconsRegular.mapPin;
  static const IconData menu = PhosphorIconsRegular.list;
  static const IconData moreHorizontal = PhosphorIconsRegular.dotsThree;
  static const IconData moreVertical = PhosphorIconsRegular.dotsThreeVertical;
  static const IconData moon = PhosphorIconsRegular.moon;
  static const IconData musicNote = PhosphorIconsRegular.musicNote;
  static const IconData musicNotes = PhosphorIconsRegular.musicNotes;
  static const IconData notifications = PhosphorIconsRegular.bell;
  static const IconData openInNew = PhosphorIconsRegular.arrowSquareOut;
  static const IconData palette = PhosphorIconsRegular.palette;
  static const IconData pause = PhosphorIconsRegular.pause;
  static const IconData pencil = PhosphorIconsRegular.pencilSimple;
  static const IconData person = PhosphorIconsRegular.user;
  static const IconData personOff = PhosphorIconsRegular.userMinus;
  static const IconData play = PhosphorIconsRegular.play;
  static const IconData playCircle = PhosphorIconsRegular.playCircle;
  static const IconData playlist = PhosphorIconsRegular.playlist;
  static const IconData queue = PhosphorIconsRegular.queue;
  static const IconData radar = PhosphorIconsRegular.radio;
  static const IconData refresh = PhosphorIconsRegular.arrowClockwise;
  static const IconData repeat = PhosphorIconsRegular.repeat;
  static const IconData repeatOnce = PhosphorIconsRegular.repeatOnce;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData save = PhosphorIconsRegular.floppyDisk;
  static const IconData settings = PhosphorIconsRegular.gear;
  static const IconData shuffle = PhosphorIconsRegular.shuffle;
  static const IconData skipNext = PhosphorIconsRegular.skipForward;
  static const IconData skipPrevious = PhosphorIconsRegular.skipBack;
  static const IconData smartphone = PhosphorIconsRegular.deviceMobile;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData sort = PhosphorIconsRegular.sortAscending;
  static const IconData sliders = PhosphorIconsRegular.slidersHorizontal;
  static const IconData clock = PhosphorIconsRegular.clock;
  static const IconData sun = PhosphorIconsRegular.sun;
  static const IconData timer = PhosphorIconsRegular.timer;
  static const IconData trash = PhosphorIconsRegular.trash;
  static const IconData undo = PhosphorIconsRegular.arrowBendUpLeft;
  static const IconData users = PhosphorIconsRegular.users;
  static const IconData video = PhosphorIconsRegular.videoCamera;
  static const IconData visibility = PhosphorIconsRegular.eye;
  static const IconData visibilityOff = PhosphorIconsRegular.eyeSlash;
  static const IconData volumeLow = PhosphorIconsRegular.speakerLow;
  static const IconData wifi = PhosphorIconsRegular.wifiHigh;
}

/// 选中态图标。不要用颜色代替实心/空心的状态差异。
abstract final class AppIconsFilled {
  static const IconData heart = PhosphorIconsFill.heart;
  static const IconData pause = PhosphorIconsFill.pause;
  static const IconData play = PhosphorIconsFill.play;
  static const IconData skipNext = PhosphorIconsFill.skipForward;
  static const IconData skipPrevious = PhosphorIconsFill.skipBack;
  static const IconData star = PhosphorIconsFill.star;
}
