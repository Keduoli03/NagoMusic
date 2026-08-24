/// 音频/元数据本地缓存与代理服务：磁盘缓存、range 转发代理、标签探测。
///
/// 唯一的规则：这个包**绝不能反过来 import app 侧的任何代码**（`package:nagomusic/...`）。
/// 依赖方向必须永远是 app → media_cache。
library;

export 'src/audio_cache_service.dart';
export 'src/audio_proxy_server.dart';
export 'src/cache_key.dart';
export 'src/http_utils.dart';
export 'src/metadata/ogg_vorbis_comment.dart';
export 'src/metadata/probe_handlers.dart';
export 'src/metadata/tag_probe_result.dart';
export 'src/metadata/tag_probe_service.dart';
export 'src/metadata/wav_id3_metadata.dart';
