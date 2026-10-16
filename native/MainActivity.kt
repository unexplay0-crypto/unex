package com.exemplo.iptv_player

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.media.MediaCodecList
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "unex.vision/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> result.success(isTelevision())
                "getBrightness" -> result.success(currentBrightness())
                "setBrightness" -> {
                    setBrightness((call.argument<Double>("value") ?: 0.5).toFloat())
                    result.success(null)
                }
                "resetBrightness" -> {
                    val lp = window.attributes
                    lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = lp
                    result.success(null)
                }
                "getVolume" -> result.success(currentVolume())
                "setVolume" -> {
                    setVolume((call.argument<Double>("value") ?: 0.5).toFloat())
                    result.success(null)
                }
                "getTotalRamMb" -> result.success(totalRamMb())
                "hasDecoder" -> {
                    val mime = call.argument<String>("mime") ?: ""
                    result.success(hasHardwareDecoder(mime))
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------- Detecção de dispositivo ----------
    private fun isTelevision(): Boolean {
        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        if (uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
        val pm = packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)) return true
        if (pm.hasSystemFeature("android.software.leanback_only")) return true
        if (pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)) return true
        // TV Boxes genéricas sem touchscreen
        if (!pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)) return true
        return false
    }

    // ---------- Brilho / Volume ----------
    private fun currentBrightness(): Double {
        val b = window.attributes.screenBrightness
        if (b >= 0f) return b.toDouble()
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
        } catch (_: Exception) {
            0.5
        }
    }

    private fun setBrightness(v: Float) {
        val lp = window.attributes
        lp.screenBrightness = v.coerceIn(0.02f, 1f)
        window.attributes = lp
    }

    private fun currentVolume(): Double {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    private fun setVolume(v: Float) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, (v.coerceIn(0f, 1f) * max).toInt(), 0)
    }

    // ---------- Memória ----------
    private fun totalRamMb(): Int {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val info = android.app.ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        return (info.totalMem / (1024 * 1024)).toInt()
    }

    // ---------- Codecs ----------
    private fun hasHardwareDecoder(mime: String): Boolean {
        return try {
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            list.codecInfos.any { info ->
                !info.isEncoder && info.supportedTypes.any { it.equals(mime, true) } &&
                    (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || info.isHardwareAccelerated)
            }
        } catch (_: Exception) {
            true
        }
    }
}
