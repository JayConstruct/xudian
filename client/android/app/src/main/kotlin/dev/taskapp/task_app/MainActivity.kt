package dev.taskapp.task_app

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var captureWindow: BrowserCaptureDialog? = null
    private var pendingSave: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private val saveRequest = 41201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xudian.host/browser")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capture" -> {
                        if (captureWindow != null) {
                            result.error("busy", "另一个采集窗口尚未关闭", null)
                        } else {
                            try {
                                val window = BrowserCaptureDialog(
                                    this,
                                    call.argument<String>("url") ?: "",
                                    call.argument<String>("script") ?: ""
                                ) { payload ->
                                    captureWindow = null
                                    result.success(payload)
                                }
                                captureWindow = window
                                window.show()
                            } catch (error: Exception) {
                                captureWindow = null
                                result.error("browser", error.message, null)
                            }
                        }
                    }
                    "cancel" -> { captureWindow?.dismiss(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xudian.host/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveText") {
                    result.notImplemented()
                } else if (pendingSave != null) {
                    result.error("busy", "另一个文件保存窗口尚未关闭", null)
                } else {
                    val text = call.argument<String>("text") ?: ""
                    val bytes = text.toByteArray(Charsets.UTF_8)
                    if (bytes.size > 2 * 1024 * 1024) {
                        result.error("size", "文件超过 2 MiB", null)
                    } else {
                        pendingSave = result
                        pendingBytes = bytes
                        try {
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "export.json")
                            }, saveRequest)
                        } catch (error: Exception) {
                            pendingSave = null
                            pendingBytes = null
                            result.error("picker", error.message, null)
                        }
                    }
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequest) return
        val result = pendingSave ?: return
        val bytes = pendingBytes ?: byteArrayOf()
        pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingSave = null
            result.success(false)
            return
        }
        Thread {
            try {
                val stream = contentResolver.openOutputStream(uri, "wt")
                    ?: throw java.io.IOException("无法写入所选文件")
                stream.use { it.write(bytes) }
                runOnUiThread {
                    if (pendingSave === result) { pendingSave = null; result.success(true) }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (pendingSave === result) { pendingSave = null; result.error("write", error.message, null) }
                }
            }
        }.start()
    }

    override fun onDestroy() {
        captureWindow?.dismiss()
        pendingSave?.error("closed", "文件保存窗口已关闭", null)
        pendingSave = null
        pendingBytes = null
        super.onDestroy()
    }
}
