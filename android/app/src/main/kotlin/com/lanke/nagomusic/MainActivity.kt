package com.lanke.nagomusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.github.proify.lyricon.lyric.model.LyricWord
import io.github.proify.lyricon.lyric.model.RichLyricLine
import io.github.proify.lyricon.lyric.model.Song
import io.github.proify.lyricon.provider.LyriconFactory
import io.github.proify.lyricon.provider.LyriconProvider

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.lanke.nagomusic/meizu_lyrics"
    private val lyriconChannelName = "com.lanke.nagomusic/lyricon"
    private val notificationId = 10010
    private val notificationChannelId = "meizu_lyric_channel"
    private var flagShowTicker: Int? = null
    private var flagUpdateTicker: Int? = null
    private var lyriconProvider: LyriconProvider? = null
    private var lyriconEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkSupport" -> {
                    result.success(checkSupport())
                }
                "updateLyric" -> {
                    val text = call.argument<String>("text") ?: ""
                    updateLyric(text)
                    result.success(null)
                }
                "stopLyric" -> {
                    stopLyric()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            lyriconChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setServiceEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setLyriconEnabled(enabled)
                    result.success(null)
                }
                "setPlaybackState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    setLyriconPlaybackState(isPlaying)
                    result.success(null)
                }
                "setSong" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        setLyriconSong(args)
                    }
                    result.success(null)
                }
                "updatePosition" -> {
                    val position = call.argument<Int>("position") ?: 0
                    updateLyriconPosition(position.toLong())
                    result.success(null)
                }
                "setDisplayTranslation" -> {
                    val display = call.argument<Boolean>("display") ?: false
                    setLyriconDisplayTranslation(display)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setLyriconEnabled(enabled: Boolean) {
        lyriconEnabled = enabled
        val provider = ensureLyriconProvider() ?: return
        if (enabled) {
            provider.register()
        } else {
            provider.unregister()
        }
    }

    private fun setLyriconPlaybackState(isPlaying: Boolean) {
        if (!lyriconEnabled) return
        lyriconProvider?.player?.setPlaybackState(isPlaying)
    }

    private fun setLyriconDisplayTranslation(display: Boolean) {
        if (!lyriconEnabled) return
        lyriconProvider?.player?.setDisplayTranslation(display)
    }

    private fun updateLyriconPosition(position: Long) {
        if (!lyriconEnabled) return
        lyriconProvider?.player?.setPosition(position)
    }

    private fun setLyriconSong(args: Map<*, *>) {
        if (!lyriconEnabled) return
        val lyrics = (args["lyrics"] as? List<*>)?.mapNotNull { item ->
            val lineMap = item as? Map<*, *> ?: return@mapNotNull null
            val begin = toLong(lineMap["begin"])
            val end = toLong(lineMap["end"])
            val words = (lineMap["words"] as? List<*>)?.mapNotNull { wordItem ->
                val wordMap = wordItem as? Map<*, *> ?: return@mapNotNull null
                LyricWord(
                    begin = toLong(wordMap["begin"]),
                    end = toLong(wordMap["end"]),
                    text = wordMap["text"] as? String
                )
            }
            RichLyricLine(
                begin = begin,
                end = end,
                text = lineMap["text"] as? String,
                translation = lineMap["translation"] as? String,
                words = words
            )
        } ?: emptyList()
        val song = Song(
            id = args["id"]?.toString(),
            name = args["name"] as? String,
            artist = args["artist"] as? String,
            duration = toLong(args["duration"]),
            lyrics = lyrics
        )
        lyriconProvider?.player?.setSong(song)
    }

    private fun ensureLyriconProvider(): LyriconProvider? {
        if (lyriconProvider == null) {
            lyriconProvider = LyriconFactory.createProvider(this)
        }
        return lyriconProvider
    }

    private fun toLong(value: Any?): Long {
        return when (value) {
            is Long -> value
            is Int -> value.toLong()
            is Double -> value.toLong()
            is Float -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    private fun checkSupport(): Boolean {
        val show = ensureTickerFlags()
        val update = flagUpdateTicker ?: 0
        return show > 0 && update > 0
    }

    private fun ensureTickerFlags(): Int {
        if (flagShowTicker != null && flagUpdateTicker != null) {
            return flagShowTicker ?: 0
        }
        return try {
            val cls = Class.forName("android.app.Notification")
            val showField = cls.getDeclaredField("FLAG_ALWAYS_SHOW_TICKER")
            val updateField = cls.getDeclaredField("FLAG_ONLY_UPDATE_TICKER")
            flagShowTicker = showField.getInt(null)
            flagUpdateTicker = updateField.getInt(null)
            flagShowTicker ?: 0
        } catch (_: Throwable) {
            flagShowTicker = 0
            flagUpdateTicker = 0
            0
        }
    }

    private fun updateLyric(text: String) {
        if (text.isBlank()) return
        if (!checkSupport()) return
        ensureNotificationChannel()
        val builder = NotificationCompat.Builder(this, notificationChannelId)
            .setPriority(Notification.PRIORITY_MAX)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("歌词")
            .setContentText(text)

        builder.setTicker(text)
        val notification = builder.build()
        notification.flags = notification.flags or Notification.FLAG_NO_CLEAR
        val showFlag = flagShowTicker ?: 0
        val updateFlag = flagUpdateTicker ?: 0
        if (showFlag > 0) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                notification.extras.putBoolean("ticker_icon_switch", false)
                notification.extras.putInt("ticker_icon", R.mipmap.ic_launcher)
            }
            notification.flags = notification.flags or showFlag
            notification.flags = notification.flags or updateFlag
        }
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId, notification)
    }

    private fun stopLyric() {
        if (!checkSupport()) return
        ensureNotificationChannel()
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(notificationChannelId) != null) return
        val channel = NotificationChannel(
            notificationChannelId,
            "Lyric",
            NotificationManager.IMPORTANCE_HIGH
        )
        manager.createNotificationChannel(channel)
    }
}
