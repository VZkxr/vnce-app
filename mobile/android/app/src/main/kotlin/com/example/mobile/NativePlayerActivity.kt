package com.example.mobile

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.SingleSampleMediaSource
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.IOException
import kotlin.concurrent.thread

@UnstableApi
class NativePlayerActivity : AppCompatActivity() {

    private var player: ExoPlayer? = null
    private lateinit var rootFrame: FrameLayout
    private lateinit var playerView: androidx.media3.ui.PlayerView
    private lateinit var controlsOverlay: FrameLayout
    private lateinit var titleText: TextView
    private lateinit var positionText: TextView
    private lateinit var durationText: TextView
    private lateinit var seekBar: SeekBar
    private lateinit var playPauseBtn: ImageButton
    private lateinit var bufferingIndicator: ProgressBar
    private var errorText: TextView? = null

    // Post-play
    private var postPlayOverlay: FrameLayout? = null
    private var postPlayTriggered = false
    private var postPlayDismissed = false
    private var postPlayTriggerMs = Long.MAX_VALUE
    private var recTitle = ""; private var recSynopsis = ""; private var recBackdrop = ""
    private var recHasStream = false

    // Next episode
    private var nextEpOverlay: LinearLayout? = null
    private var nextEpTriggered = false
    private var nextEpTriggerMs = Long.MAX_VALUE
    private var nextEpTitle = ""

    private val handler = Handler(Looper.getMainLooper())
    private var controlsVisible = true
    private var isDragging = false
    private var showRemainingTime = false
    private var username = ""; private var videoTitle = ""; private var resultAction = "none"

    private val hideRunnable = Runnable { if (player?.isPlaying == true && !isDragging) setControlsVisibility(false) }
    private val progressRunnable = object : Runnable {
        override fun run() { updateProgress(); checkTriggers(); handler.postDelayed(this, 500) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)

        val videoUrl = intent.getStringExtra("videoUrl") ?: run { finish(); return }
        videoTitle = intent.getStringExtra("title") ?: ""
        username = intent.getStringExtra("username") ?: "anonimo"
        val startMs = intent.getLongExtra("startPosition", 0L)
        val subsJson = intent.getStringExtra("subtitlesJson") ?: "[]"

        intent.getStringExtra("postPlayJson")?.let {
            try { val o = JSONObject(it)
                postPlayTriggerMs = parseTriggerMs(o.optDouble("triggerMinutes", 0.0))
                recTitle = o.optString("recTitle"); recSynopsis = o.optString("recSynopsis")
                recBackdrop = o.optString("recBackdrop"); recHasStream = o.optBoolean("hasStream", false)
            } catch (_: Exception) {} }

        intent.getStringExtra("nextEpJson")?.let {
            try { val o = JSONObject(it)
                nextEpTriggerMs = parseTriggerMs(o.optDouble("triggerMinutes", 1.0))
                nextEpTitle = o.optString("title")
            } catch (_: Exception) {} }

        buildUI()
        initPlayer(videoUrl, startMs, subsJson)
    }

    private fun parseTriggerMs(value: Double): Long {
        val m = value.toInt()
        val s = Math.round((value - m) * 100).toInt()
        return (m * 60 + s) * 1000L
    }

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    // ═══════════════════════════════════════════════════════════════
    //  UI
    // ═══════════════════════════════════════════════════════════════
    private fun buildUI() {
        rootFrame = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.BLACK)
        }

        playerView = androidx.media3.ui.PlayerView(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            useController = false
            setOnClickListener { toggleControls() }
            // Raise subtitles slightly above the bottom bar
            subtitleView?.setPadding(0, 0, 0, dp(36))
        }
        // Set subtitle appearance: white text on semi-transparent dark gray
        playerView.subtitleView?.setApplyEmbeddedStyles(false)
        playerView.subtitleView?.setStyle(
            androidx.media3.ui.CaptionStyleCompat(
                Color.WHITE,
                Color.argb(160, 0, 0, 0),
                Color.TRANSPARENT,
                androidx.media3.ui.CaptionStyleCompat.EDGE_TYPE_NONE,
                Color.WHITE,
                null
            )
        )
        rootFrame.addView(playerView)

        bufferingIndicator = ProgressBar(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER)
            indeterminateTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#E50914"))
        }
        rootFrame.addView(bufferingIndicator)

        errorText = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER)
                .apply { leftMargin = dp(32); rightMargin = dp(32) }
            setTextColor(Color.parseColor("#FF6B6B")); textSize = 13f; visibility = View.GONE; gravity = Gravity.CENTER
        }
        rootFrame.addView(errorText)

        // Controls
        controlsOverlay = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setOnClickListener { toggleControls() }
        }
        rootFrame.addView(controlsOverlay)

        // Top bar
        val topBar = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(72), Gravity.TOP)
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(16), dp(8), dp(8))
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(Color.argb(200, 0, 0, 0), Color.TRANSPARENT))
        }
        topBar.addView(iconBtn(R.drawable.ic_arrow_back, dp(40)) { finishWithResult() })
        titleText = TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            text = videoTitle; setTextColor(Color.WHITE); textSize = 16f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            maxLines = 1; ellipsize = TextUtils.TruncateAt.END; setPadding(dp(8), 0, dp(8), 0)
        }
        topBar.addView(titleText)
        topBar.addView(iconBtn(R.drawable.ic_settings, dp(40)) { showTrackDialog() })
        controlsOverlay.addView(topBar)

        // Center controls
        val center = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER)
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        }
        center.addView(iconBtn(R.drawable.ic_replay_10, dp(52)) { player?.seekTo((player!!.currentPosition - 10000).coerceAtLeast(0)) })
        center.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(32), 1) })
        playPauseBtn = iconBtn(R.drawable.ic_pause, dp(64)) { togglePlayPause() }
        center.addView(playPauseBtn)
        center.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(32), 1) })
        center.addView(iconBtn(R.drawable.ic_forward_10, dp(52)) { player?.seekTo((player!!.currentPosition + 10000).coerceAtMost(player!!.duration.coerceAtLeast(0))) })
        controlsOverlay.addView(center)

        // Bottom bar
        val bottom = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64), Gravity.BOTTOM)
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(16))
            background = GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, intArrayOf(Color.argb(210, 0, 0, 0), Color.TRANSPARENT))
        }
        positionText = TextView(this).apply {
            setTextColor(Color.WHITE); textSize = 12f; text = "00:00"; typeface = Typeface.MONOSPACE
            setOnClickListener { showRemainingTime = !showRemainingTime; updateProgress(); scheduleHide() }
        }
        bottom.addView(positionText)
        seekBar = SeekBar(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(10); marginEnd = dp(10) }
            progressTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#E50914"))
            thumbTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#E50914"))
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(Color.argb(80, 255, 255, 255))
            max = 1000; setOnSeekBarChangeListener(seekListener)
        }
        bottom.addView(seekBar)
        durationText = TextView(this).apply { setTextColor(Color.argb(180, 255, 255, 255)); textSize = 12f; text = "00:00"; typeface = Typeface.MONOSPACE }
        bottom.addView(durationText)
        controlsOverlay.addView(bottom)

        // Post-play overlay (hidden)
        postPlayOverlay = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            visibility = View.GONE
        }
        rootFrame.addView(postPlayOverlay)

        // Next episode button (hidden)
        nextEpOverlay = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.END)
                .apply { rightMargin = dp(24); bottomMargin = dp(80) }
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            background = GradientDrawable().apply { setColor(Color.argb(200, 255, 255, 255)); cornerRadius = dp(6).toFloat() }
            setPadding(dp(16), dp(12), dp(16), dp(12))
        }

        val nextEpContent = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setOnClickListener { resultAction = "next_ep"; finishWithResult() }
        }
        nextEpContent.addView(TextView(this).apply {
            text = "Siguiente episodio"; setTextColor(Color.BLACK); textSize = 14f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        })
        nextEpContent.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(8), 1) })
        nextEpContent.addView(ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(18), dp(18))
            setImageResource(R.drawable.ic_play); setColorFilter(Color.BLACK)
        })
        nextEpOverlay!!.addView(nextEpContent)

        // Close X for Next Episode
        nextEpOverlay!!.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(12), 1) })
        nextEpOverlay!!.addView(FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(24), dp(24))
            setOnClickListener {
                nextEpOverlay?.visibility = View.GONE
                nextEpTriggered = true // keeps it hidden
            }
            addView(TextView(this@NativePlayerActivity).apply {
                layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER)
                text = "✕"; setTextColor(Color.BLACK); textSize = 12f
            })
        })

        rootFrame.addView(nextEpOverlay)

        setContentView(rootFrame)
    }

    // ─── Post-play content ─────────────────────────────────────────
    private fun buildPostPlayContent() {
        val overlay = postPlayOverlay ?: return
        overlay.removeAllViews()

        // Dark overlay background
        overlay.setBackgroundColor(Color.argb(200, 0, 0, 0))

        // Backdrop image (loaded async, placed at z=0)
        if (recBackdrop.isNotEmpty()) {
            thread {
                try {
                    val bmp = BitmapFactory.decodeStream(java.net.URL(recBackdrop).openStream())
                    handler.post {
                        if (postPlayOverlay?.visibility == View.VISIBLE) {
                            overlay.addView(ImageView(this).apply {
                                layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                                scaleType = ImageView.ScaleType.CENTER_CROP
                                setImageBitmap(bmp); alpha = 0.35f
                            }, 0)
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        val container = LinearLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }

        // LEFT: miniature player (16:9 aspect ratio)
        val miniWrapper = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 0.38f)
                .apply { rightMargin = dp(20); gravity = Gravity.CENTER_VERTICAL }
        }
        // Calculate 16:9 height based on available width (~38% of screen)
        val screenW = resources.displayMetrics.widthPixels
        val miniW = (screenW * 0.38f).toInt() - dp(44)
        val miniH = (miniW * 9f / 16f).toInt()

        val miniFrame = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, miniH)
            background = GradientDrawable().apply {
                setColor(Color.BLACK); cornerRadius = dp(8).toFloat()
            }
            clipChildren = true; clipToPadding = true
        }
        // Move playerView into the mini frame
        (playerView.parent as? ViewGroup)?.removeView(playerView)
        playerView.setOnClickListener(null)
        miniFrame.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        miniWrapper.addView(miniFrame)
        container.addView(miniWrapper)

        // RIGHT: recommendation info
        val info = LinearLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 0.62f)
            orientation = LinearLayout.VERTICAL
        }
        info.addView(TextView(this).apply {
            text = "A CONTINUACIÓN"; setTextColor(Color.parseColor("#E50914")); textSize = 11f
            typeface = Typeface.create("sans-serif", Typeface.BOLD); letterSpacing = 0.2f
            setPadding(0, 0, 0, dp(8))
        })
        info.addView(TextView(this).apply {
            text = recTitle; setTextColor(Color.WHITE); textSize = 20f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD); maxLines = 2
            setPadding(0, 0, 0, dp(6))
        })
        info.addView(TextView(this).apply {
            text = recSynopsis; setTextColor(Color.argb(200, 200, 200, 200)); textSize = 12f
            maxLines = 3; ellipsize = TextUtils.TruncateAt.END; setLineSpacing(0f, 1.2f)
            setPadding(0, 0, 0, dp(16))
        })

        // Buttons
        val btns = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        }
        // Reproducir
        val playBtn = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(6).toFloat() }
            setPadding(dp(20), dp(10), dp(24), dp(10))
            setOnClickListener {
                if (recHasStream) { resultAction = "play_rec"; finishWithResult() }
                else { Toast.makeText(this@NativePlayerActivity, "No disponible en streaming", Toast.LENGTH_SHORT).show() }
            }
        }
        playBtn.addView(ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(18), dp(18)).apply { rightMargin = dp(8) }
            setImageResource(R.drawable.ic_play); setColorFilter(Color.BLACK)
        })
        playBtn.addView(TextView(this).apply {
            text = "Reproducir"; setTextColor(Color.BLACK); textSize = 14f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        })
        btns.addView(playBtn)
        btns.addView(View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(14), 1) })

        // Close X
        val closeBtn = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40))
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(2, Color.WHITE); setColor(Color.TRANSPARENT) }
            setOnClickListener { dismissPostPlay() }
        }
        closeBtn.addView(TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER)
            text = "✕"; setTextColor(Color.WHITE); textSize = 16f
        })
        btns.addView(closeBtn)

        info.addView(btns)
        container.addView(info)
        overlay.addView(container)
    }

    private fun dismissPostPlay() {
        postPlayDismissed = true
        postPlayOverlay?.visibility = View.GONE
        // Restore playerView to root as full-screen
        (playerView.parent as? ViewGroup)?.removeView(playerView)
        rootFrame.addView(playerView, 0, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        playerView.setOnClickListener { toggleControls() }
        playerView.subtitleView?.setPadding(0, 0, 0, dp(36))
        // Restore controls
        controlsOverlay.visibility = View.VISIBLE
        controlsOverlay.alpha = 1f
        controlsVisible = true
        scheduleHide()
    }

    private fun showPostPlay() {
        if (postPlayTriggered || postPlayDismissed || recTitle.isEmpty()) return
        postPlayTriggered = true
        controlsOverlay.alpha = 0f
        buildPostPlayContent()
        postPlayOverlay?.visibility = View.VISIBLE
        postPlayOverlay?.alpha = 0f
        postPlayOverlay?.animate()?.alpha(1f)?.setDuration(400)?.start()
    }

    private fun showNextEp() {
        if (nextEpTriggered || nextEpTitle.isEmpty()) return
        nextEpTriggered = true
        nextEpOverlay?.visibility = View.VISIBLE
        nextEpOverlay?.alpha = 0f
        nextEpOverlay?.animate()?.alpha(1f)?.setDuration(300)?.start()
    }

    private fun checkTriggers() {
        val p = player ?: return; val dur = p.duration; val pos = p.currentPosition
        if (dur <= 0) return; val remaining = dur - pos
        if (!postPlayTriggered && !postPlayDismissed && postPlayTriggerMs < Long.MAX_VALUE && remaining <= postPlayTriggerMs) showPostPlay()
        if (!nextEpTriggered && nextEpTriggerMs < Long.MAX_VALUE && remaining <= nextEpTriggerMs) showNextEp()
    }

    private fun iconBtn(res: Int, size: Int, action: () -> Unit) = ImageButton(this).apply {
        layoutParams = LinearLayout.LayoutParams(size, size)
        setImageResource(res); scaleType = ImageView.ScaleType.CENTER_INSIDE
        setPadding(dp(6), dp(6), dp(6), dp(6)); setColorFilter(Color.WHITE)
        setBackgroundColor(Color.TRANSPARENT); setOnClickListener { action() }
    }

    // ═══════════════════════════════════════════════════════════════
    //  ExoPlayer
    // ═══════════════════════════════════════════════════════════════
    private fun initPlayer(videoUrl: String, startMs: Long, subsJson: String) {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(mapOf(
                "User-Agent" to "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                "Referer" to "https://vnc-e.com/", "Origin" to "https://vnc-e.com"))
            .setConnectTimeoutMs(15000).setReadTimeoutMs(15000).setAllowCrossProtocolRedirects(true)

        val sanFactory = SanitizingDataSource.Factory(httpFactory, username)
        val mediaItem = MediaItem.Builder().setUri(videoUrl).setMimeType(MimeTypes.APPLICATION_M3U8).build()
        val hlsSource = HlsMediaSource.Factory(sanFactory).setAllowChunklessPreparation(true).createMediaSource(mediaItem)

        val subSources = mutableListOf<MediaSource>()
        var defaultSubLang: String? = null
        try { val arr = JSONArray(subsJson)
            for (i in 0 until arr.length()) { val s = arr.getJSONObject(i)
                var url = s.getString("url"); val lang = s.optString("lang", "es"); val label = s.optString("label", "Subtítulo")
                if (url.contains("vnc-e.com") && !url.contains("u=")) url = "$url${if (url.contains("?")) "&" else "?"}u=${Uri.encode(username)}"
                val forced = lang.contains("forced"); if (forced) defaultSubLang = lang
                subSources.add(SingleSampleMediaSource.Factory(sanFactory).createMediaSource(
                    MediaItem.SubtitleConfiguration.Builder(Uri.parse(url)).setMimeType(MimeTypes.TEXT_VTT)
                        .setLanguage(lang).setLabel(label)
                        .setSelectionFlags(if (forced) C.SELECTION_FLAG_FORCED or C.SELECTION_FLAG_DEFAULT else 0).build(), C.TIME_UNSET))
            }
        } catch (e: Exception) { android.util.Log.w("VNCE", "Sub: $e") }

        val src = if (subSources.isNotEmpty()) MergingMediaSource(hlsSource, *subSources.toTypedArray()) else hlsSource

        player = ExoPlayer.Builder(this).build().apply {
            setMediaSource(src); playWhenReady = true
            trackSelectionParameters = trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .setPreferredTextLanguage(defaultSubLang ?: "es").build()
            if (startMs > 0) seekTo(startMs); prepare()
        }
        playerView.player = player

        player?.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> bufferingIndicator.visibility = View.VISIBLE
                    Player.STATE_READY -> { bufferingIndicator.visibility = View.GONE; durationText.text = fmtMs(player?.duration ?: 0) }
                    Player.STATE_ENDED -> { if (nextEpTitle.isNotEmpty() && resultAction == "none") resultAction = "next_ep"; finishWithResult() }
                    else -> {}
                }
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                playPauseBtn.setImageResource(if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play)
                if (isPlaying) scheduleHide()
            }
            override fun onPlayerError(error: PlaybackException) {
                bufferingIndicator.visibility = View.GONE
                errorText?.text = "Error: ${error.message}\n${error.cause?.message ?: ""}"; errorText?.visibility = View.VISIBLE
            }
        })
        handler.post(progressRunnable)
    }

    // ═══════════════════════════════════════════════════════════════
    //  SanitizingDataSource
    // ═══════════════════════════════════════════════════════════════
    class SanitizingDataSource(private val up: DataSource, private val user: String) : DataSource {
        private var san: ByteArrayInputStream? = null; private var isSan = false; private var curUri: Uri? = null
        class Factory(private val f: DataSource.Factory, private val u: String) : DataSource.Factory { override fun createDataSource() = SanitizingDataSource(f.createDataSource(), u) }
        override fun addTransferListener(tl: TransferListener) { up.addTransferListener(tl) }
        @Throws(IOException::class) override fun open(ds: DataSpec): Long {
            var s = ds; val u = ds.uri.toString()
            if (u.contains("vnc-e.com") && !u.contains("u=")) s = ds.withUri(Uri.parse("$u${if (u.contains("?")) "&" else "?"}u=${Uri.encode(user)}"))
            curUri = s.uri
            if (u.contains(".m3u8")) { up.open(s); val b = readAll(up); up.close(); var c = String(b, Charsets.UTF_8); c = c.replace(Regex(",SUBTITLES=\"[^\"]*\""), ""); val o = c.toByteArray(Charsets.UTF_8); san = ByteArrayInputStream(o); isSan = true; return o.size.toLong() }
            isSan = false; san = null; return up.open(s)
        }
        @Throws(IOException::class) override fun read(b: ByteArray, o: Int, l: Int): Int { if (isSan) { val s = san ?: return C.RESULT_END_OF_INPUT; val n = s.read(b, o, l); return if (n == -1) C.RESULT_END_OF_INPUT else n }; return up.read(b, o, l) }
        override fun getUri(): Uri? = curUri ?: up.uri
        @Throws(IOException::class) override fun close() { san?.close(); san = null; isSan = false; curUri = null; up.close() }
        private fun readAll(src: DataSource): ByteArray { val b = ByteArray(8192); val o = java.io.ByteArrayOutputStream(); var n: Int; while (src.read(b, 0, b.size).also { n = it } != C.RESULT_END_OF_INPUT) o.write(b, 0, n); return o.toByteArray() }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Controls
    // ═══════════════════════════════════════════════════════════════
    private fun togglePlayPause() { player?.let { if (it.isPlaying) it.pause() else { it.play(); scheduleHide() } } }
    private fun toggleControls() {
        if (postPlayTriggered && !postPlayDismissed) return
        setControlsVisibility(!controlsVisible)
        if (controlsVisible) {
            scheduleHide()
        } else {
            handler.removeCallbacks(hideRunnable)
        }
    }

    private fun setControlsVisibility(v: Boolean) {
        controlsVisible = v
        if (v) {
            controlsOverlay.visibility = View.VISIBLE
            controlsOverlay.animate().alpha(1f).setDuration(250).withEndAction(null).start()
        } else {
            controlsOverlay.animate().alpha(0f).setDuration(250).withEndAction {
                if (!controlsVisible) controlsOverlay.visibility = View.GONE
            }.start()
        }
    }

    private fun scheduleHide() {
        if (!controlsVisible || isDragging) return
        handler.removeCallbacks(hideRunnable)
        handler.postDelayed(hideRunnable, 5000)
    }

    private fun updateProgress() {
        if (isDragging || player == null) return
        val p = player!!; val pos = p.currentPosition; val dur = p.duration.coerceAtLeast(1)
        seekBar.progress = (pos * 1000 / dur).toInt()
        
        if (showRemainingTime) {
            val remain = (dur - pos).coerceAtLeast(0)
            positionText.text = "-${fmtMs(remain)}"
        } else {
            positionText.text = fmtMs(pos)
        }
    }

    private fun fmtMs(ms: Long): String { val s = ms / 1000; val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60; return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%02d:%02d", m, sec) }

    private val seekListener = object : SeekBar.OnSeekBarChangeListener {
        override fun onProgressChanged(sb: SeekBar?, p: Int, fromUser: Boolean) {
            if (fromUser) {
                val dur = player?.duration ?: 0
                val pos = p.toLong() * dur / 1000
                if (showRemainingTime) {
                    val remain = (dur - pos).coerceAtLeast(0)
                    positionText.text = "-${fmtMs(remain)}"
                } else {
                    positionText.text = fmtMs(pos)
                }
            }
        }
        override fun onStartTrackingTouch(sb: SeekBar?) { isDragging = true }
        override fun onStopTrackingTouch(sb: SeekBar?) { isDragging = false; player?.let { it.seekTo(sb!!.progress.toLong() * it.duration / 1000) }; scheduleHide() }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Track dialog — selected items in RED
    // ═══════════════════════════════════════════════════════════════
    private fun showTrackDialog() {
        val p = player ?: return
        val items = mutableListOf<Pair<CharSequence, () -> Unit>>()
        val RED = Color.parseColor("#E50914")

        // Section header
        items.add(styledText("─── Audio ───", Color.argb(120, 255, 255, 255)) to {})

        for (i in 0 until p.currentTracks.groups.size) { val g = p.currentTracks.groups[i]
            if (g.type == C.TRACK_TYPE_AUDIO) { for (j in 0 until g.length) { val fmt = g.getTrackFormat(j); val sel = g.isTrackSelected(j)
                val label = prettify(fmt.label ?: fmt.language ?: "Audio ${j + 1}")
                val display = if (sel) styledText("✓  $label", RED) else label
                val gi = i; val ji = j
                items.add(display to { p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setOverrideForType(TrackSelectionOverride(p.currentTracks.groups[gi].mediaTrackGroup, listOf(ji))).build() })
            } } }

        items.add(styledText("─── Subtítulos ───", Color.argb(120, 255, 255, 255)) to {})
        val disabled = p.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
        val disLabel = "Desactivar subtítulos"
        items.add((if (disabled) styledText("✓  $disLabel", RED) else disLabel) to {
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
        })
        for (i in 0 until p.currentTracks.groups.size) { val g = p.currentTracks.groups[i]
            if (g.type == C.TRACK_TYPE_TEXT) { for (j in 0 until g.length) { val fmt = g.getTrackFormat(j); val sel = g.isTrackSelected(j) && !disabled
                val label = fmt.label ?: fmt.language ?: "Sub ${j + 1}"
                val display = if (sel) styledText("✓  $label", RED) else label
                val gi = i; val ji = j
                items.add(display to { p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false).setOverrideForType(TrackSelectionOverride(p.currentTracks.groups[gi].mediaTrackGroup, listOf(ji))).build() })
            } } }

        // Build custom adapter for colored items
        val adapter = object : ArrayAdapter<CharSequence>(this, android.R.layout.simple_list_item_1, items.map { it.first }) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val view = super.getView(position, convertView, parent)
                (view as? TextView)?.let { tv ->
                    val item = items[position].first
                    if (item is SpannableString) tv.text = item
                    tv.textSize = 16f
                    tv.setPadding(dp(16), dp(12), dp(16), dp(12))
                }
                return view
            }
        }

        AlertDialog.Builder(this)
            .setAdapter(adapter) { _, w -> items[w].second() }
            .show()
    }

    private fun styledText(text: String, color: Int): SpannableString {
        val sp = SpannableString(text)
        sp.setSpan(ForegroundColorSpan(color), 0, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return sp
    }

    private fun prettify(raw: String): String { val l = raw.lowercase(); return when { l.contains("spa") || l.contains("español") || l == "es" -> "Español Latino"; l.contains("eng") || l.contains("inglés") || l == "en" -> "Inglés"; l.contains("fre") || l.contains("francés") || l == "fr" -> "Francés"; else -> raw } }

    private fun finishWithResult() {
        setResult(Activity.RESULT_OK, Intent().apply {
            putExtra("position", player?.currentPosition ?: 0L)
            putExtra("duration", player?.duration ?: 0L)
            putExtra("action", resultAction)
        }); finish()
    }

    override fun onPause() { super.onPause(); player?.pause() }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); player?.release(); player = null; super.onDestroy() }
    @Deprecated("Deprecated in Java") override fun onBackPressed() { finishWithResult() }
}
