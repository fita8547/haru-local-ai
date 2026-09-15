package com.example.ai_chat

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.util.Log
import com.arm.aichat.AiChat
import com.arm.aichat.InferenceEngine
import com.whispercpp.whisper.WhisperContext
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Calendar

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    companion object {
        private const val CHANNEL_NAME = "app.haru/native"
        private const val AUDIO_PERMISSION_REQUEST_CODE = 4302
        private const val MODEL_FILE = "Qwen3-1.7B-Q4_K_M.gguf"
        private const val MODEL_SIZE = 1_280_000_000L
        private const val MODEL_SHA256 =
            "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"
        private const val MODEL_URL =
            "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/" +
                MODEL_FILE + "?download=true"
        private const val ASR_FILE = "ggml-tiny.bin"
        private const val ASR_SIZE = 75_000_000L
        private const val ASR_SHA1 = "bd577a113a864445d4c299885e0cb97d4ba92b5f"
        private const val ASR_URL =
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true"
    }

    private val worker = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val engineMutex = Mutex()
    private lateinit var channel: MethodChannel
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var engine: InferenceEngine? = null
    private var modelLoaded = false
    private var downloading = false
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var conversationDate = ""
    private var lastInteractionAt = 0L
    private var turnsSinceReset = 0
    private val systemPrompt =
        "/no_think. 너는 하루라는 한국어 감정 대화 동반자다. " +
            "사용자가 오늘 힘들었던 일을 털어놓으면 먼저 감정을 인정하고 차분히 들어준다. " +
            "사용자가 원하는 역할이나 상황이 분명하지 않으면, 무엇을 해주면 좋을지 짧게 하나만 물어본다. " +
            "위로나 정리, 현실적인 조언 중 사용자가 원하는 방식을 확인한 뒤 그 역할에 맞춰 답한다. " +
            "이미 물어본 질문을 그대로 반복하지 말고, 직전 사용자의 말에 새롭게 반응한다. " +
            "사용자가 이어서 답하면 앞서 말한 내용과 연결해 한 단계만 더 진행한다. " +
            "질문과 관계없는 자기소개, 시스템 설명, 날짜 반복은 하지 않는다. " +
            "반드시 자연스러운 한국어 한글로만 답한다. 중국어, 영어, 번역투, 알 수 없는 기호를 사용하지 않는다. " +
            "답변은 3~5문장으로 하고 빈 인사말은 쓰지 않는다."

    private val modelFile by lazy { File(filesDir, MODEL_FILE) }
    private val asrFile by lazy { File(filesDir, ASR_FILE) }
    private val oldLargeModelFile by lazy {
        File(filesDir, "qwen2.5-1.5b-instruct-q4_k_m.gguf")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Remove the stalled 1.5B artifact from the previous prototype.
        if (oldLargeModelFile.exists()) oldLargeModelFile.delete()
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    val key = call.argument<String>("key")
                    result.success(key?.let {
                        getSharedPreferences("haru", MODE_PRIVATE).getString(it, null)
                    })
                }
                "write" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key == null || value == null) {
                        result.error("invalid_arguments", "저장할 값이 없습니다.", null)
                    } else {
                        getSharedPreferences("haru", MODE_PRIVATE)
                            .edit().putString(key, value).apply()
                        result.success(null)
                    }
                }
                "recognizeKorean" -> requestKoreanSpeech(result)
                "modelStatus" -> result.success(modelStatus())
                "installModel" -> installModel(result)
                "askLocal" -> askLocal(call.argument<String>("prompt").orEmpty(), result)
                "getDailyReminder" -> result.success(dailyReminderEnabled())
                "setDailyReminder" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    setDailyReminder(enabled)
                    result.success(enabled)
                }
                else -> result.notImplemented()
            }
        }
        val preferences = getSharedPreferences("haru", MODE_PRIVATE)
        if (!preferences.contains("daily_reminder")) {
            setDailyReminder(true)
        } else if (preferences.getBoolean("daily_reminder", true)) {
            setDailyReminder(true)
        }

        if (modelFile.exists() && modelFile.length() > MODEL_SIZE * 9 / 10) {
            worker.launch {
                runCatching { ensureModelLoaded() }
                    .onFailure { emitStatus("error", it.message ?: "모델 로드 실패") }
            }
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.KOREAN) ?: TextToSpeech.ERROR
            ttsReady = result != TextToSpeech.LANG_MISSING_DATA &&
                result != TextToSpeech.LANG_NOT_SUPPORTED
            tts?.setSpeechRate(1.03f)
        }
    }

    private fun modelStatus(): Map<String, Any> = mapOf(
        "installed" to (
            modelFile.exists() && modelFile.length() > MODEL_SIZE * 9 / 10 &&
                asrFile.exists() && asrFile.length() > ASR_SIZE * 9 / 10
            ),
        "loaded" to modelLoaded,
        "downloading" to downloading,
        "bytes" to listOf(modelFile, asrFile).sumOf { if (it.exists()) it.length() else 0L },
        "requiredBytes" to MODEL_SIZE + ASR_SIZE,
        "name" to "Qwen3 1.7B Q4"
    )

    private fun dailyReminderEnabled(): Boolean =
        getSharedPreferences("haru", MODE_PRIVATE).getBoolean("daily_reminder", true)

    private fun setDailyReminder(enabled: Boolean) {
        getSharedPreferences("haru", MODE_PRIVATE).edit()
            .putBoolean("daily_reminder", enabled).apply()
        val alarmManager = getSystemService(AlarmManager::class.java)
        val intent = Intent(this, DailyReminderReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            this, 1001, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (!enabled) {
            alarmManager.cancel(pending)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1002)
        }
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 9)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        alarmManager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            next.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pending
        )
    }

    private fun installModel(result: MethodChannel.Result) {
        if (downloading) {
            result.error("busy", "이미 모델을 설치하고 있습니다.", null)
            return
        }
        if (modelStatus()["installed"] == true) {
            result.success(modelStatus())
            return
        }
        downloading = true
        result.success(modelStatus())
        worker.launch {
            val partial = File(filesDir, "$MODEL_FILE.part")
            val asrPartial = File(filesDir, "$ASR_FILE.part")
            runCatching {
                if (!modelFile.exists() || modelFile.length() < MODEL_SIZE * 9 / 10) {
                    downloadTo(MODEL_URL, partial)
                    val checksum = digest(partial, "SHA-256")
                    require(checksum.equals(MODEL_SHA256, ignoreCase = true)) {
                        "모델 파일 검증에 실패했습니다."
                    }
                    if (modelFile.exists()) modelFile.delete()
                    require(partial.renameTo(modelFile)) { "모델 파일을 저장하지 못했습니다." }
                }
                emitStatus("downloading", "한국어 음성 모델을 설치하고 있어요")
                if (!asrFile.exists() || asrFile.length() < ASR_SIZE * 9 / 10) {
                    downloadTo(ASR_URL, asrPartial)
                    require(digest(asrPartial, "SHA-1").equals(ASR_SHA1, ignoreCase = true)) {
                        "음성 모델 파일 검증에 실패했습니다."
                    }
                    if (asrFile.exists()) asrFile.delete()
                    require(asrPartial.renameTo(asrFile)) { "음성 모델을 저장하지 못했습니다." }
                }
                downloading = false
                emitStatus("installed", "모델 설치 완료")
                ensureModelLoaded()
            }.onFailure {
                partial.delete()
                asrPartial.delete()
                downloading = false
                val cause = it.message?.takeIf { message -> message.isNotBlank() }
                    ?: "${it::class.java.simpleName}: 원인을 확인할 수 없습니다"
                Log.e("HaruDownload", "Model installation failed: $cause", it)
                emitStatus("error", "모델 설치 실패: $cause")
            }
        }
    }

    private fun downloadTo(url: String, output: File) {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 15_000
        connection.readTimeout = 120_000
        connection.setRequestProperty("User-Agent", "Haru-Android/1.0")
        connection.connect()
        require(connection.responseCode in 200..299) {
            "다운로드 오류 ${connection.responseCode}"
        }
        val total = connection.contentLengthLong.takeIf { it > 0 } ?: MODEL_SIZE
        connection.inputStream.use { input ->
            output.outputStream().buffered().use { target ->
                val buffer = ByteArray(1024 * 256)
                var copied = 0L
                var lastPercent = -1
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    target.write(buffer, 0, count)
                    copied += count
                    val percent = ((copied * 100) / total).toInt().coerceIn(0, 100)
                    if (percent != lastPercent) {
                        lastPercent = percent
                        emitProgress(percent, copied, total)
                    }
                }
            }
        }
        connection.disconnect()
    }

    private fun digest(file: File, algorithm: String): String {
        val digest = MessageDigest.getInstance(algorithm)
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 256)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private suspend fun ensureModelLoaded() = engineMutex.withLock {
        if (modelLoaded) return@withLock
        require(modelFile.exists()) { "먼저 모델을 설치해 주세요." }
        emitStatus("loading", "로컬 AI를 준비하고 있어요")
        val localEngine = engine ?: AiChat.getInferenceEngine(applicationContext).also {
            engine = it
        }
        val state = localEngine.state.first {
            it is InferenceEngine.State.Initialized || it is InferenceEngine.State.Error
        }
        if (state is InferenceEngine.State.Error) throw state.exception
        localEngine.loadModel(modelFile.absolutePath)
        localEngine.setSystemPrompt(systemPrompt)
        modelLoaded = true
        conversationDate = todayKey()
        lastInteractionAt = System.currentTimeMillis()
        emitStatus("ready", "로컬 AI 준비 완료")
    }

    private fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    private suspend fun resetConversationIfNeeded() {
        val now = System.currentTimeMillis()
        val dateChanged = conversationDate.isNotEmpty() && conversationDate != todayKey()
        val idleTooLong = lastInteractionAt > 0 && now - lastInteractionAt >= 30 * 60 * 1000L
        val turnLimitReached = turnsSinceReset >= 14
        if (dateChanged || idleTooLong || turnLimitReached) {
            engine?.resetConversation()
            engine?.setSystemPrompt(systemPrompt)
            turnsSinceReset = 0
            emitStatus(
                "ready",
                when {
                    dateChanged -> "새로운 하루 대화를 시작했어요"
                    turnLimitReached -> "대화가 길어져 문맥을 정리했어요"
                    else -> "오래 쉬어서 대화를 정리했어요"
                }
            )
        }
        conversationDate = todayKey()
        lastInteractionAt = now
    }

    private fun askLocal(prompt: String, result: MethodChannel.Result) {
        if (prompt.isBlank()) {
            result.error("empty", "질문을 말씀해 주세요.", null)
            return
        }
        worker.launch {
            runCatching {
                ensureModelLoaded()
                resetConversationIfNeeded()
                val date = SimpleDateFormat(
                    "yyyy년 M월 d일 EEEE a h시 m분",
                    Locale.KOREAN
                ).format(Date())
                val answer = StringBuilder()
                val dateQuestion = prompt.contains("몇 일이") || prompt.contains("오늘 날짜") ||
                    prompt.contains("오늘이 무슨") || prompt.contains("현재 시간") ||
                    prompt.contains("몇 시")
                val userPrompt = if (dateQuestion) {
                    "사용자 질문에 답하세요. 현재 시각은 $date 입니다. 질문: $prompt"
                } else {
                    prompt
                }
                engine!!.sendUserPrompt(
                    userPrompt,
                    128
                ).collect { answer.append(it) }
                turnsSinceReset += 1
                answer.toString().trim()
            }.onSuccess { answer ->
                runOnUiThread {
                    if (ttsReady && answer.isNotBlank()) {
                        tts?.speak(answer, TextToSpeech.QUEUE_FLUSH, null, "haru-answer")
                    }
                    result.success(answer)
                }
            }.onFailure { error ->
                runOnUiThread {
                    result.error("inference_failed", error.message ?: "답변 생성 실패", null)
                }
            }
        }
    }

    private fun emitProgress(percent: Int, bytes: Long, total: Long) {
        runOnUiThread {
            channel.invokeMethod(
                "modelProgress",
                mapOf("percent" to percent, "bytes" to bytes, "total" to total)
            )
        }
    }

    private fun emitStatus(state: String, message: String) {
        runOnUiThread {
            channel.invokeMethod("modelState", mapOf("state" to state, "message" to message))
        }
    }

    private fun requestKoreanSpeech(result: MethodChannel.Result) {
        if (pendingSpeechResult != null) {
            result.error("busy", "이미 음성을 듣고 있습니다.", null)
            return
        }
        pendingSpeechResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), AUDIO_PERMISSION_REQUEST_CODE)
            return
        }
        recordAndTranscribe()
    }

    private fun recordAndTranscribe() {
        worker.launch {
            runCatching {
                require(asrFile.exists()) { "음성 모델을 먼저 설치해 주세요." }
                emitStatus("listening", "7초 동안 듣고 있어요…")
                val audio = recordAudio(7_000)
                emitStatus("transcribing", "한국어 음성을 폰 안에서 인식하고 있어요…")
                val whisper = WhisperContext.createContextFromFile(asrFile.absolutePath)
                try {
                    whisper.transcribeData(audio, printTimestamp = false).trim()
                } finally {
                    whisper.release()
                }
            }.onSuccess { transcript ->
                runOnUiThread {
                    pendingSpeechResult?.success(transcript)
                    pendingSpeechResult = null
                }
            }.onFailure { error ->
                runOnUiThread {
                    finishSpeechWithError("recognition_failed", error.message ?: "음성 인식 실패")
                }
            }
        }
    }

    @Suppress("MissingPermission")
    private fun recordAudio(durationMs: Long): FloatArray {
        val sampleRate = 16_000
        val minimum = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        require(minimum > 0) { "마이크 버퍼를 만들 수 없습니다." }
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minimum * 2
        )
        val maximumSamples = (sampleRate * durationMs / 1_000).toInt()
        val samples = FloatArray(maximumSamples)
        val buffer = ShortArray(minimum / 2)
        var offset = 0
        try {
            recorder.startRecording()
            while (offset < maximumSamples) {
                val count = recorder.read(buffer, 0, minOf(buffer.size, maximumSamples - offset))
                require(count >= 0) { "마이크 읽기 오류 $count" }
                for (index in 0 until count) {
                    samples[offset + index] = (buffer[index] / 32768.0f).coerceIn(-1f, 1f)
                }
                offset += count
            }
            recorder.stop()
        } finally {
            recorder.release()
        }
        return if (offset == samples.size) samples else samples.copyOf(offset)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != AUDIO_PERMISSION_REQUEST_CODE) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            recordAndTranscribe()
        } else {
            finishSpeechWithError("permission_denied", "마이크 권한이 필요합니다.")
        }
    }

    private fun finishSpeechWithError(code: String, message: String) {
        pendingSpeechResult?.error(code, message, null)
        pendingSpeechResult = null
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        engine?.destroy()
        worker.cancel()
        super.onDestroy()
    }
}
