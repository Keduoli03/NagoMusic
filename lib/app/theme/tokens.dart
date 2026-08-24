/// 设计 token 汇总入口。
///
/// 页面 / 组件里 **`import '../theme/tokens.dart';` 一行**即可拿到：
/// - [AppColors] —— 颜色
/// - [AppRadii] —— 圆角
/// - [AppSpacing] —— 间距
/// - [AppTypography] —— 排版
///
/// 只导出这四个纯 token 文件，**不导出** `app_theme.dart`（会带进整个
/// `ThemeData` 构造逻辑）和 `app_surfaces.dart`（原 `app_styles.dart`，
/// 依赖 `settings_background_state` 这样的 App 状态）——
/// token 层不能把状态或主题构造拖进每一个引用它的页面。
library;

export 'app_colors.dart';
export 'app_radii.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
