package dev.taskapp.task_app

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.webkit.JavascriptInterface
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import org.json.JSONObject
import java.util.UUID

/** Generic capture transport. Business bridges and adapters come from the module. */
@SuppressLint("SetJavaScriptEnabled")
class BrowserCaptureDialog(
    activity: Activity,
    private val initialUrl: String,
    private val script: String,
    private val completed: (String?) -> Unit
) : Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar) {
    private val main = Handler(Looper.getMainLooper())
    private val web = WebView(context)
    private val address = EditText(context)
    private val status = TextView(context)
    private val run = Button(context)
    private val progress = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal)
    private var loadFailed = false
    private var failedUrl: String? = null
    private var pageReady = false
    private var token: String? = null
    private var payload: String? = null
    private var closed = false
    private var prompt: AlertDialog? = null

    init {
        require(validUrl(initialUrl)) { "教务网址无效" }
        require(script.isNotBlank() && script.toByteArray(Charsets.UTF_8).size <= 256 * 1024) { "采集脚本无效" }
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            fitsSystemWindows = true
        }
        content.setBackgroundColor(Color.WHITE)
        val header = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(12), dp(8))
        }
        header.addView(TextView(context).apply {
            text = "网页采集"
            gravity = Gravity.CENTER_VERTICAL
            textSize = 20f
            setTextColor(Color.rgb(25, 32, 43))
            setTypeface(typeface, Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, dp(48), 1f).apply { gravity = Gravity.CENTER_VERTICAL })
        header.addView(actionButton("关闭") { dismiss() }, LinearLayout.LayoutParams(dp(68), dp(44)))
        content.addView(header)
        val addressRow = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), 0, dp(12), dp(8))
        }
        address.setTextColor(Color.rgb(25, 32, 43))
        address.textSize = 14f
        address.setPadding(dp(12), 0, dp(12), 0)
        address.background = rounded(Color.rgb(242, 244, 247))
        address.setSingleLine(true)
        address.inputType = android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_URI or
            android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        address.imeOptions = EditorInfo.IME_ACTION_GO or EditorInfo.IME_FLAG_FORCE_ASCII
        address.setText(initialUrl)
        address.contentDescription = "教务网址"
        address.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_GO) { navigate(address.text.toString()); true } else false
        }
        addressRow.addView(address, LinearLayout.LayoutParams(0, dp(48), 1f))
        addressRow.addView(actionButton("前往") { navigate(address.text.toString()) },
            LinearLayout.LayoutParams(dp(68), dp(44)).apply { leftMargin = dp(8) })
        content.addView(addressRow)
        val actions = LinearLayout(context).apply { setPadding(dp(12), 0, dp(12), dp(8)) }
        actions.addView(actionButton("返回") { goBack() },
            LinearLayout.LayoutParams(dp(68), dp(44)))
        actions.addView(actionButton("刷新") { beginNavigation(); web.reload() },
            LinearLayout.LayoutParams(dp(68), dp(44)).apply { leftMargin = dp(8) })
        styleButton(run, primary = true)
        run.text = "执行采集"
        run.isEnabled = false
        run.setOnClickListener { capture() }
        actions.addView(run, LinearLayout.LayoutParams(0, dp(44), 1f).apply { leftMargin = dp(8) })
        content.addView(actions)
        status.setTextColor(Color.rgb(86, 96, 111))
        status.textSize = 13f
        status.text = "登录后进入个人课表页面，选择学期，再点击执行采集"
        status.setPadding(dp(16), dp(4), dp(16), dp(12))
        content.addView(status)
        progress.isIndeterminate = true
        content.addView(progress, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2)))
        content.addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(content)
        window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            useWideViewPort = true
            loadWithOverviewMode = true
        }
        web.addJavascriptInterface(CaptureTransport(), "XudianCaptureTransport")
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: android.webkit.WebResourceRequest): Boolean {
                if (!validUrl(request.url.toString())) return true
                if (request.isForMainFrame && !request.isRedirect) beginNavigation()
                return false
            }
            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                address.setText(url)
                // HTTP errors can arrive before onPageStarted on WebView.
                // Preserve that navigation's failure until an explicit retry.
                if (loadFailed && failedUrl == url) return
                beginNavigation()
            }
            override fun onPageFinished(view: WebView, url: String) {
                progress.visibility = View.GONE
                if (closed || loadFailed) return
                pageReady = validUrl(url)
                run.isEnabled = pageReady
                status.text = "页面已加载，确认课表后执行采集"
            }
            override fun onReceivedError(view: WebView, request: android.webkit.WebResourceRequest, error: android.webkit.WebResourceError) {
                if (!request.isForMainFrame) return
                val reason = when (error.errorCode) {
                    ERROR_HOST_LOOKUP -> "无法解析域名 ${request.url.host}。请检查网址和设备网络；校内网址可能需要校园网或学校 VPN。"
                    ERROR_CONNECT -> "无法连接服务器，请检查设备网络或稍后刷新。"
                    ERROR_TIMEOUT -> "连接超时，请检查设备网络或稍后刷新。"
                    else -> "页面加载失败：${error.description}"
                }
                failLoading("$reason\n错误码：${error.errorCode} · ${error.description}", request.url.toString())
            }
            override fun onReceivedHttpError(view: WebView, request: android.webkit.WebResourceRequest, response: android.webkit.WebResourceResponse) {
                if (request.isForMainFrame) failLoading("服务器返回 HTTP ${response.statusCode}，请确认网址或稍后刷新。", request.url.toString())
            }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                handler.cancel()
                failLoading("网站证书验证失败，请检查设备日期或联系学校教务管理员。", error.url)
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onJsAlert(view: WebView, url: String, message: String, result: JsResult): Boolean {
                prompt = AlertDialog.Builder(context).setMessage(message)
                    .setPositiveButton("确定") { _, _ -> result.confirm() }
                    .setOnCancelListener { result.cancel() }.create()
                prompt?.show(); return true
            }
            override fun onJsConfirm(view: WebView, url: String, message: String, result: JsResult): Boolean {
                prompt = AlertDialog.Builder(context).setMessage(message)
                    .setPositiveButton("确定") { _, _ -> result.confirm() }
                    .setNegativeButton("取消") { _, _ -> result.cancel() }
                    .setOnCancelListener { result.cancel() }.create()
                prompt?.show(); return true
            }
            override fun onJsPrompt(view: WebView, url: String, message: String, defaultValue: String, result: JsPromptResult): Boolean {
                val input = EditText(context).apply { setText(defaultValue) }
                prompt = AlertDialog.Builder(context).setMessage(message).setView(input)
                    .setPositiveButton("确定") { _, _ -> result.confirm(input.text.toString()) }
                    .setNegativeButton("取消") { _, _ -> result.cancel() }
                    .setOnCancelListener { result.cancel() }.create()
                prompt?.show(); return true
            }
        }
        setOnDismissListener {
            if (!closed) {
                closed = true
                token = null
                prompt?.dismiss()
                web.stopLoading()
                web.removeJavascriptInterface("XudianCaptureTransport")
                web.destroy()
                completed(payload)
            }
        }
        web.loadUrl(initialUrl)
    }

    override fun show() {
        super.show()
        window?.decorView?.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && web.canGoBack()) { goBack(); return true }
        return super.onKeyDown(keyCode, event)
    }

    private fun navigate(url: String) {
        if (validUrl(url)) { beginNavigation(); web.loadUrl(url) } else status.text = "请输入 HTTP 或 HTTPS 网址"
    }

    private fun goBack() {
        if (web.canGoBack()) { beginNavigation(); web.goBack() }
    }

    private fun beginNavigation() {
        token = null
        prompt?.dismiss()
        loadFailed = false
        failedUrl = null
        pageReady = false
        run.isEnabled = false
        progress.visibility = View.VISIBLE
        status.setTextColor(Color.rgb(86, 96, 111))
        status.text = "正在加载页面…"
    }

    private fun capture() {
        if (closed || !pageReady || loadFailed || !validUrl(web.url ?: "")) return
        val current = UUID.randomUUID().toString()
        token = current
        status.text = "正在采集；结果将在课表中预览后保存"
        // Each execution has a distinct token. Navigation and closing invalidate it.
        val source = """
            (function() {
                if (window.__xudianCaptureCleanup) window.__xudianCaptureCleanup();
                const session = ${JSONObject.quote(current)};
                const send = (type, value) => XudianCaptureTransport.postMessage(JSON.stringify({session, type, value}));
                window.xudianCapture = Object.freeze({send});
                const error = event => send('error', String(event.reason?.message || event.reason || event.message || '脚本执行失败'));
                window.addEventListener('unhandledrejection', error);
                window.__xudianCaptureCleanup = () => window.removeEventListener('unhandledrejection', error);
                try {
                    new Function(${JSONObject.quote(script)})();
                } catch (error) { send('error', String(error.message || error)); }
            })();
        """.trimIndent()
        web.evaluateJavascript(source, null)
    }

    private fun failLoading(message: String, url: String) {
        loadFailed = true
        failedUrl = url
        pageReady = false
        token = null
        run.isEnabled = false
        progress.visibility = View.GONE
        status.setTextColor(Color.rgb(166, 34, 34))
        status.text = message
    }

    private fun dp(value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

    private fun rounded(color: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(12).toFloat()
    }

    private fun actionButton(label: String, action: () -> Unit) = Button(context).apply {
        styleButton(this)
        text = label
        setOnClickListener { action() }
    }

    private fun styleButton(button: Button, primary: Boolean = false) {
        button.isAllCaps = false
        button.textSize = 14f
        button.minWidth = 0
        button.minimumWidth = 0
        button.setPadding(dp(8), 0, dp(8), 0)
        button.background = rounded(Color.WHITE)
        button.stateListAnimator = null
        button.elevation = 0f
        val states = arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf())
        button.backgroundTintList = ColorStateList(states, intArrayOf(
            Color.rgb(236, 239, 243), if (primary) Color.rgb(46, 92, 210) else Color.rgb(240, 243, 248)))
        button.setTextColor(ColorStateList(states, intArrayOf(
            Color.rgb(145, 153, 166), if (primary) Color.WHITE else Color.rgb(40, 56, 79))))
    }

    inner class CaptureTransport {
        @JavascriptInterface
        fun postMessage(message: String) {
            if (message.toByteArray(Charsets.UTF_8).size > 2 * 1024 * 1024) return
            main.post {
                if (closed) return@post
                try {
                    val data = JSONObject(message)
                    if (token == null || data.optString("session") != token) return@post
                    when (data.optString("type")) {
                        "status" -> status.text = data.optString("value").take(1000)
                        "error" -> { status.text = "采集未完成：${data.optString("value").take(1000)}"; token = null }
                        "complete" -> {
                            val value = data.getJSONObject("value")
                            payload = value.toString()
                            dismiss()
                        }
                    }
                } catch (_: Exception) { status.text = "采集结果格式无效，请重新采集"; token = null }
            }
        }
    }

    private fun validUrl(value: String): Boolean {
        val uri = Uri.parse(value)
        return (uri.scheme == "https" || uri.scheme == "http") && !uri.host.isNullOrBlank() && uri.userInfo == null
    }
}
