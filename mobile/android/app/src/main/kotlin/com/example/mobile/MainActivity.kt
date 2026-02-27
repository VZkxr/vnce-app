package com.example.mobile

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.vnce.player"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchPlayer" -> {
                    pendingResult = result

                    // Subtitles
                    val subtitles = call.argument<List<Map<String, String>>>("subtitles")
                    val subsJson = JSONArray()
                    subtitles?.forEach { sub ->
                        subsJson.put(JSONObject().apply {
                            put("label", sub["label"] ?: "Subtítulo")
                            put("lang", sub["lang"] ?: "es")
                            put("url", sub["url"] ?: "")
                        })
                    }

                    // Post-play data (movies)
                    val postPlay = call.argument<Map<String, Any>>("postPlay")
                    val postPlayJson = if (postPlay != null) {
                        JSONObject().apply {
                            put("triggerMinutes", postPlay["triggerMinutes"] ?: 0.0)
                            put("recTitle", postPlay["recTitle"] ?: "")
                            put("recSynopsis", postPlay["recSynopsis"] ?: "")
                            put("recBackdrop", postPlay["recBackdrop"] ?: "")
                            put("hasStream", postPlay["hasStream"] ?: false)
                        }.toString()
                    } else null

                    // Next episode data (series)
                    val nextEp = call.argument<Map<String, Any>>("nextEpisode")
                    val nextEpJson = if (nextEp != null) {
                        JSONObject().apply {
                            put("triggerMinutes", nextEp["triggerMinutes"] ?: 1.0)
                            put("title", nextEp["title"] ?: "")
                        }.toString()
                    } else null

                    val intent = Intent(this, NativePlayerActivity::class.java).apply {
                        putExtra("videoUrl", call.argument<String>("videoUrl"))
                        putExtra("title", call.argument<String>("title"))
                        putExtra("username", call.argument<String>("username"))
                        putExtra("startPosition", call.argument<Number>("startPosition")?.toLong() ?: 0L)
                        putExtra("subtitlesJson", subsJson.toString())
                        if (postPlayJson != null) putExtra("postPlayJson", postPlayJson)
                        if (nextEpJson != null) putExtra("nextEpJson", nextEpJson)
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, 1001)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            pendingResult?.success(mapOf(
                "position" to (data?.getLongExtra("position", 0L) ?: 0L),
                "duration" to (data?.getLongExtra("duration", 0L) ?: 0L),
                "action" to (data?.getStringExtra("action") ?: "none")
            ))
            pendingResult = null
        }
    }
}
