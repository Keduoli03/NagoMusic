/// 哔哩哔哩 Web 接口封装：搜索 / 分P / playurl / 收藏夹 / 扫码登录 / 字幕。
///
/// 唯一的规则：这个包**绝不能反过来 import app 侧的任何代码**（`package:nagomusic/...`）。
/// 它被设计成一个不依赖 `SongEntity` / `SongDao` / Flutter 框架 UI 的纯接口层，
/// 依赖方向必须永远是 app → bili_api，破了这条规则 pub 会直接报一个跟真实原因
/// 对不上号的错误。
library;

export 'src/api.dart';
export 'src/audio_selector.dart';
export 'src/cookie_repository.dart';
export 'src/models.dart';
export 'src/prefs.dart';
export 'src/song_id.dart';
export 'src/subtitle_service.dart';
