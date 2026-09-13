package com.bobby.omni_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class PlayerNotificationService : Service() {
    companion object {
        const val CHANNEL_ID = "omni_player_media_channel"
        const val NOTIFICATION_ID = 1001
        var mediaSession: MediaSessionCompat? = null
        var currentTitle = "Omni Player"
        var currentThumbPath: String? = null
        var currentBitmap: Bitmap? = null
        var isPlaying = true
        var durationMs: Long = 0
        var positionMs: Long = 0
        var channelMessenger: MethodChannel? = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        setupMediaSession()
    }

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "OmniPlayerMediaSession").apply {
            isActive = true
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    channelMessenger?.invokeMethod("onMediaPlayPause", null)
                }

                override fun onPause() {
                    channelMessenger?.invokeMethod("onMediaPlayPause", null)
                }

                override fun onSkipToNext() {
                    channelMessenger?.invokeMethod("onMediaNext", null)
                }

                override fun onSkipToPrevious() {
                    channelMessenger?.invokeMethod("onMediaPrevious", null)
                }

                override fun onFastForward() {
                    channelMessenger?.invokeMethod("onMediaForward", null)
                }

                override fun onRewind() {
                    channelMessenger?.invokeMethod("onMediaRewind", null)
                }

                override fun onSeekTo(pos: Long) {
                    channelMessenger?.invokeMethod("onMediaSeekTo", pos)
                }
            })
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        currentTitle = intent?.getStringExtra("title") ?: currentTitle
        isPlaying = intent?.getBooleanExtra("isPlaying", true) ?: isPlaying
        durationMs = intent?.getLongExtra("duration", 0L) ?: durationMs
        positionMs = intent?.getLongExtra("position", 0L) ?: positionMs

        val newThumb = intent?.getStringExtra("thumbPath")
        if (newThumb != null && newThumb != currentThumbPath) {
            currentThumbPath = newThumb
            try {
                val file = File(newThumb)
                if (file.exists()) {
                    currentBitmap = BitmapFactory.decodeFile(file.absolutePath)
                }
            } catch (_: Exception) {
                currentBitmap = null
            }
        }

        updateMetadata()
        updatePlaybackState()

        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    private fun updateMetadata() {
        val metaBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, "Omni Player")
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "Video Playback")
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)

        if (currentBitmap != null) {
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, currentBitmap)
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, currentBitmap)
        }

        mediaSession?.setMetadata(metaBuilder.build())
    }

    private fun updatePlaybackState() {
        val state = if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val playbackState = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_FAST_FORWARD or
                        PlaybackStateCompat.ACTION_REWIND or
                        PlaybackStateCompat.ACTION_SEEK_TO
            )
            .setState(state, positionMs, 1.0f)
            .build()
        mediaSession?.setPlaybackState(playbackState)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Media Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Omni Player Media Controls"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openAppIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText("Omni Player")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(openAppIntent)
            .setOngoing(isPlaying)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession?.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        if (currentBitmap != null) {
            builder.setLargeIcon(currentBitmap)
        }

        return builder.build()
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaSession?.release()
    }
}

class MainActivity : FlutterActivity() {
    private val PIP_CHANNEL = "com.bobby.omni_player/pip"
    private val BG_CHANNEL = "com.bobby.omni_player/background"
    private var pipChannel: MethodChannel? = null
    private var bgChannel: MethodChannel? = null

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                "PIP_ACTION_REWIND" -> pipChannel?.invokeMethod("onPipRewind", null)
                "PIP_ACTION_PLAY_PAUSE" -> pipChannel?.invokeMethod("onPipPlayPause", null)
                "PIP_ACTION_FORWARD" -> pipChannel?.invokeMethod("onPipForward", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        pipChannel = MethodChannel(messenger, PIP_CHANNEL)
        bgChannel = MethodChannel(messenger, BG_CHANNEL)
        PlayerNotificationService.channelMessenger = bgChannel

        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPiP" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val width = call.argument<Int>("width") ?: 16
                    val height = call.argument<Int>("height") ?: 9
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        enterCustomPiP(isPlaying, width, height)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "updatePiPState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        updatePiPActions(isPlaying)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        bgChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startNotification", "updateNotification" -> {
                    val title = call.argument<String>("title") ?: PlayerNotificationService.currentTitle
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: PlayerNotificationService.isPlaying
                    val duration = (call.argument<Int>("duration") ?: 0).toLong()
                    val position = (call.argument<Int>("position") ?: 0).toLong()
                    val thumbPath = call.argument<String>("thumbPath")

                    val intent = Intent(this, PlayerNotificationService::class.java).apply {
                        putExtra("title", title)
                        putExtra("isPlaying", isPlaying)
                        putExtra("duration", duration)
                        putExtra("position", position)
                        if (thumbPath != null) putExtra("thumbPath", thumbPath)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopNotification" -> {
                    val intent = Intent(this, PlayerNotificationService::class.java).apply {
                        action = "STOP"
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val filter = IntentFilter().apply {
            addAction("PIP_ACTION_REWIND")
            addAction("PIP_ACTION_PLAY_PAUSE")
            addAction("PIP_ACTION_FORWARD")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(pipReceiver, filter)
        }
    }

    private fun getSafeRational(w: Int, h: Int): Rational {
        var num = if (w > 0) w else 16
        var den = if (h > 0) h else 9
        val ratio = num.toFloat() / den.toFloat()
        if (ratio < 0.418410f) {
            num = 418
            den = 1000
        } else if (ratio > 2.390000f) {
            num = 2390
            den = 1000
        }
        return Rational(num, den)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun enterCustomPiP(isPlaying: Boolean, width: Int, height: Int) {
        val rational = getSafeRational(width, height)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(rational)
            .setActions(buildPiPActions(isPlaying))
            .build()
        enterPictureInPictureMode(params)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun updatePiPActions(isPlaying: Boolean) {
        val params = PictureInPictureParams.Builder()
            .setActions(buildPiPActions(isPlaying))
            .build()
        setPictureInPictureParams(params)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildPiPActions(isPlaying: Boolean): ArrayList<RemoteAction> {
        val actions = ArrayList<RemoteAction>()

        val rewindIntent = PendingIntent.getBroadcast(
            this, 101, Intent("PIP_ACTION_REWIND").setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_rew),
                "Rewind 10s", "Rewind 10s", rewindIntent
            )
        )

        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseIntent = PendingIntent.getBroadcast(
            this, 102, Intent("PIP_ACTION_PLAY_PAUSE").setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, playPauseIcon),
                if (isPlaying) "Pause" else "Play", if (isPlaying) "Pause" else "Play", playPauseIntent
            )
        )

        val forwardIntent = PendingIntent.getBroadcast(
            this, 103, Intent("PIP_ACTION_FORWARD").setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions.add(
            RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_ff),
                "Forward 10s", "Forward 10s", forwardIntent
            )
        )

        return actions
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(pipReceiver)
        } catch (_: Exception) {}
    }
}