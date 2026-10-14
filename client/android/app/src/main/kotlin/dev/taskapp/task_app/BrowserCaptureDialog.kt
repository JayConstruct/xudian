package dev.taskapp.task_app

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.StateListDrawable
import android.net.Uri
import android.net.http.SslError
import android.os.Handler
import android.os.Build
import android.os.Looper
import android.view.KeyEvent
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowInsetsController
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
import android.widget.HorizontalScrollView
import android.widget.CheckedTextView
import org.json.JSONObject
import java.util.UUID
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.pow

/** Values come from Flutter's active Theme, not the school's page or script. */
data class BrowserAppearance(
    val dark: Boolean,
    val canvas: Int, val surface: Int, val text: Int, val muted: Int,
    val primary: Int, val onPrimary: Int, val input: Int, val outline: Int, val error: Int,
    val controlRadius: Float = 14f, val dialogRadius: Float = 24f
) {
    companion object {
        fun from(activity: Activity, values: Map<String, Any?>?): BrowserAppearance {
            val dark = values?.get("dark") as? Boolean ?: (
                activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
            fun color(key: String, light: String, night: String) =
                (values?.get(key) as? Number)?.toInt() ?: Color.parseColor(if (dark) night else light)
            fun radius(key: String, fallback: Float) =
                (values?.get(key) as? Number)?.toFloat()?.takeIf { it.isFinite() && it in 0f..64f } ?: fallback
            return BrowserAppearance(dark,
                color("canvas", "#F5F5F2", "#1D1E22"), color("surface", "#FEFEFC", "#27282D"),
                color("text", "#303239", "#E8E8E8"), color("muted", "#6D707A", "#AEAFB7"),
                color("primary", "#606EAE", "#B9C3F0"), color("onPrimary", "#FFFFFF", "#252F60"),
                color("input", "#F8F8F5", "#222328"), color("outline", "#E3E4E8", "#42444E"),
                color("error", "#BA1A1A", "#FFB4AB"), radius("controlRadius", 14f), radius("dialogRadius", 24f))
        }
    }
}

/** Sample the continuous superellipse corners, sharing Flutter's radius semantics. */
private class BrowserSurfaceDrawable(
    private val color: Int, private val radius: Float,
    private val outline: Int? = null, private val focusColor: Int = color,
    private val stroke: Float = 1f
) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    private var opacity = 255
    override fun isStateful() = true
    override fun onStateChange(state: IntArray): Boolean { invalidateSelf(); return true }
    override fun draw(canvas: Canvas) {
        val focused = state.contains(android.R.attr.state_focused)
        val inset = if (outline == null && !focused) 0f else stroke
        val left = bounds.left + inset; val top = bounds.top + inset
        val right = bounds.right - inset; val bottom = bounds.bottom - inset
        val r = radius.coerceAtMost(minOf((right - left) / 2, (bottom - top) / 2)).coerceAtLeast(0f)
        path.reset()
        val centers = arrayOf(right - r to top + r, right - r to bottom - r,
            left + r to bottom - r, left + r to top + r)
        for ((corner, center) in centers.withIndex()) {
            for (step in 0..24) {
                val angle = (-90 + corner * 90 + step * 90.0 / 24) * Math.PI / 180
                fun coordinate(value: Double) = (if (value < 0) -1 else 1) * kotlin.math.abs(value).pow(0.5)
                val x = center.first + r * coordinate(cos(angle)).toFloat()
                val y = center.second + r * coordinate(sin(angle)).toFloat()
                if (corner == 0 && step == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
        }
        path.close()
        paint.style = Paint.Style.FILL; paint.color = color
        paint.alpha = Color.alpha(color) * opacity / 255
        canvas.drawPath(path, paint)
        if (outline != null || state.contains(android.R.attr.state_focused)) {
            paint.style = Paint.Style.STROKE; paint.strokeWidth = if (focused) 2 * stroke else stroke
            paint.color = if (state.contains(android.R.attr.state_focused)) focusColor else outline!!
            paint.alpha = Color.alpha(paint.color) * opacity / 255
            canvas.drawPath(path, paint)
        }
    }
    override fun setAlpha(alpha: Int) { opacity = alpha; invalidateSelf() }
    override fun setColorFilter(filter: ColorFilter?) { paint.colorFilter = filter; invalidateSelf() }
    @Deprecated("Deprecated in Android") override fun getOpacity() = PixelFormat.TRANSLUCENT
}

/** Generic capture transport. Business bridges and adapters come from the module. */
@SuppressLint("SetJavaScriptEnabled")
class BrowserCaptureDialog(
    activity: Activity,
    private val initialUrl: String,
    private val script: String,
    private val appearance: BrowserAppearance,
    private val completed: (String?) -> Unit
) : Dialog(activity, if (appearance.dark) android.R.style.Theme_Material_NoActionBar else android.R.style.Theme_Material_Light_NoActionBar) {
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
    private val dialogQueue = java.util.ArrayDeque<JSONObject>()

    init {
        require(validUrl(initialUrl)) { "教务网址无效" }
        require(script.isNotBlank() && script.toByteArray(Charsets.UTF_8).size <= 256 * 1024) { "采集脚本无效" }
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            fitsSystemWindows = true
        }
        content.setBackgroundColor(appearance.canvas)
        val header = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(56)
            setPadding(dp(20), dp(12), dp(20), dp(12))
        }
        header.addView(TextView(context).apply {
            text = "网页采集"
            gravity = Gravity.CENTER_VERTICAL
            textSize = 24f
            setTextColor(appearance.text)
            setTypeface(typeface, Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { gravity = Gravity.CENTER_VERTICAL })
        header.addView(actionButton("关闭", outlined = false) { dismiss() }, actionLayout())
        content.addView(header)
        val addressRow = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), 0, dp(20), dp(12))
        }
        address.setTextColor(appearance.text)
        address.textSize = 14f
        address.setPadding(dp(16), dp(12), dp(16), dp(12))
        address.minimumHeight = dp(48)
        address.background = rounded(appearance.input, outline = appearance.outline)
        address.setSingleLine(true)
        address.inputType = android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_URI or
            android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        address.transformationMethod = null
        address.imeOptions = EditorInfo.IME_ACTION_GO or EditorInfo.IME_FLAG_FORCE_ASCII
        address.setText(initialUrl)
        address.contentDescription = "教务网址"
        address.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_GO) { navigate(address.text.toString()); true } else false
        }
        addressRow.addView(address, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addressRow.addView(actionButton("前往") { navigate(address.text.toString()) },
            actionLayout().apply { leftMargin = dp(8) })
        content.addView(addressRow)
        val actionScroll = HorizontalScrollView(context).apply {
            isFillViewport = true
            isHorizontalScrollBarEnabled = true
            setPadding(dp(20), 0, dp(20), dp(12))
        }
        val actions = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        actions.addView(actionButton("返回") { goBack() }, actionLayout())
        actions.addView(actionButton("刷新") { beginNavigation(); web.reload() },
            actionLayout().apply { leftMargin = dp(8) })
        styleButton(run, primary = true)
        run.text = "执行采集"
        run.isEnabled = false
        run.setOnClickListener { capture() }
        actions.addView(run, actionLayout().apply { leftMargin = dp(8) })
        actionScroll.addView(actions)
        content.addView(actionScroll)
        status.setTextColor(appearance.muted)
        status.textSize = 13f
        status.text = "登录后进入个人课表页面，选择学期，再点击执行采集"
        status.setPadding(dp(20), dp(4), dp(20), dp(16))
        content.addView(status)
        progress.isIndeterminate = true
        progress.progressTintList = ColorStateList.valueOf(appearance.primary)
        progress.indeterminateTintList = ColorStateList.valueOf(appearance.primary)
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
                showPagePrompt("提示", message, false, result)
                return true
            }
            override fun onJsConfirm(view: WebView, url: String, message: String, result: JsResult): Boolean {
                showPagePrompt("请确认", message, true, result)
                return true
            }
            override fun onJsPrompt(view: WebView, url: String, message: String, defaultValue: String, result: JsPromptResult): Boolean {
                val input = promptInput(defaultValue)
                var resolved = false
                fun finish(value: String?) {
                    if (resolved) return
                    resolved = true
                    if (value == null) result.cancel() else result.confirm(value)
                }
                prompt?.dismiss()
                prompt = AlertDialog.Builder(context).setTitle("填写信息").setMessage(message).setView(promptContainer(input))
                    .setPositiveButton("继续") { _, _ -> finish(input.text.toString()) }
                    .setNegativeButton("取消") { _, _ -> finish(null) }
                    .setOnCancelListener { finish(null) }.create()
                prompt?.setOnDismissListener { finish(null) }
                presentPrompt(prompt!!)
                return true
            }
        }
        setOnDismissListener {
            if (!closed) {
                closed = true
                token = null
                dialogQueue.clear()
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
        window?.let { captureWindow ->
            // This dialog owns a separate window from Flutter. Its canvas
            // must also cover transparent system bars on Android 15 and later.
            captureWindow.decorView.setBackgroundColor(appearance.canvas)
            configureSystemBars(captureWindow)
        }
        window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    }

    @Suppress("DEPRECATION")
    private fun configureSystemBars(dialogWindow: Window) {
        dialogWindow.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS or
            WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
        dialogWindow.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        dialogWindow.statusBarColor = appearance.canvas
        // Dark navigation icons are supported from Android 8.0 onwards.
        dialogWindow.navigationBarColor = if (Build.VERSION.SDK_INT >= 26) appearance.canvas else Color.BLACK
        if (Build.VERSION.SDK_INT >= 29) {
            dialogWindow.isStatusBarContrastEnforced = false
            dialogWindow.isNavigationBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= 30) {
            val mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            dialogWindow.insetsController?.setSystemBarsAppearance(if (appearance.dark) 0 else mask, mask)
        } else {
            val mask = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
                (if (Build.VERSION.SDK_INT >= 26) View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR else 0)
            dialogWindow.decorView.systemUiVisibility =
                (dialogWindow.decorView.systemUiVisibility and mask.inv()) or
                    (if (appearance.dark) 0 else mask)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && web.canGoBack()) { goBack(); return true }
        return super.onKeyDown(keyCode, event)
    }

    private fun navigate(url: String) {
        val value = url.trim()
        val normalized = when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("http://", ignoreCase = true) || value.startsWith("https://", ignoreCase = true) -> value
            Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:").containsMatchIn(value) &&
                !Regex("^[^/:]+:[0-9]+(?:[/?#]|$)").containsMatchIn(value) -> value
            else -> "https://$value"
        }
        if (validUrl(normalized)) { address.setText(normalized); beginNavigation(); web.loadUrl(normalized) } else status.text = "请输入 HTTP 或 HTTPS 网址"
    }

    private fun goBack() {
        if (web.canGoBack()) { beginNavigation(); web.goBack() }
    }

    private fun beginNavigation() {
        token = null
        dialogQueue.clear()
        prompt?.dismiss()
        loadFailed = false
        failedUrl = null
        pageReady = false
        run.isEnabled = false
        progress.visibility = View.VISIBLE
        status.setTextColor(appearance.muted)
        status.text = "正在加载页面…"
    }

    private fun capture() {
        if (closed || !pageReady || loadFailed || !validUrl(web.url ?: "")) return
        token = null
        dialogQueue.clear()
        prompt?.dismiss()
        val current = UUID.randomUUID().toString()
        token = current
        status.text = "正在采集；结果将在课表中预览后保存"
        // Each execution has a distinct token. Navigation and closing invalidate it.
        val source = """
            (function() {
                if (window.__xudianCaptureCleanup) window.__xudianCaptureCleanup();
                const session = ${JSONObject.quote(current)};
                const send = (type, value) => XudianCaptureTransport.postMessage(JSON.stringify({session, type, value}));
                let dialogId = 0;
                const dialogs = new Map();
                const request = (kind, details) => new Promise(resolve => {
                    const id = ++dialogId;
                    dialogs.set(id, resolve);
                    send('dialog', {id, kind, ...details});
                });
                window.__xudianDialogResolve = (expectedSession, id, value) => {
                    if (expectedSession !== session) return;
                    const resolve = dialogs.get(id);
                    if (resolve) { dialogs.delete(id); resolve(value); }
                };
                window.xudianCapture = Object.freeze({send, request});
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

    private fun promptInput(initial: String) = EditText(context).apply {
        setText(initial)
        textSize = 16f
        setTextColor(appearance.text)
        inputType = android.text.InputType.TYPE_CLASS_TEXT
        transformationMethod = null
        background = rounded(appearance.input, outline = appearance.outline)
        setPadding(dp(16), dp(12), dp(16), dp(12))
        selectAll()
    }

    private fun promptContainer(input: EditText) = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(16), dp(20), dp(20))
        addView(input, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun presentPrompt(dialog: AlertDialog) {
        dialog.show()
        dialog.window?.let { configureSystemBars(it) }
        dialog.window?.setBackgroundDrawable(rounded(appearance.surface, appearance.dialogRadius))
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        fun styleText(view: View) {
            if (view is TextView && view !is Button) {
                view.setTextColor(appearance.text)
                if (view is CheckedTextView) {
                    view.checkMarkTintList = ColorStateList.valueOf(appearance.primary)
                }
            }
            if (view is ViewGroup) for (index in 0 until view.childCount) styleText(view.getChildAt(index))
        }
        dialog.window?.decorView?.let { styleText(it) }
        dialog.listView?.selector = RippleDrawable(
            ColorStateList.valueOf((appearance.primary and 0x00ffffff) or 0x22000000),
            null, rounded(Color.WHITE))
        dialog.listView?.setOnHierarchyChangeListener(object : ViewGroup.OnHierarchyChangeListener {
            override fun onChildViewAdded(parent: View?, child: View?) { child?.let { styleText(it) } }
            override fun onChildViewRemoved(parent: View?, child: View?) {}
        })
        for (which in listOf(AlertDialog.BUTTON_POSITIVE, AlertDialog.BUTTON_NEGATIVE)) {
            dialog.getButton(which)?.let { button ->
                styleButton(button, primary = which == AlertDialog.BUTTON_POSITIVE)
                (button.layoutParams as? LinearLayout.LayoutParams)?.let { params ->
                    params.leftMargin = dp(8)
                    params.bottomMargin = dp(8)
                    button.layoutParams = params
                }
            }
        }
    }

    private fun showPagePrompt(title: String, message: String, cancellable: Boolean, result: JsResult) {
        prompt?.dismiss()
        var resolved = false
        fun finish(confirmed: Boolean) {
            if (resolved) return
            resolved = true
            if (confirmed) result.confirm() else result.cancel()
        }
        val builder = AlertDialog.Builder(context).setTitle(title).setMessage(message)
            .setPositiveButton("确定") { _, _ -> finish(true) }
            .setOnCancelListener { finish(false) }
        if (cancellable) builder.setNegativeButton("取消") { _, _ -> finish(false) }
        prompt = builder.create().apply { setOnDismissListener { finish(false) } }
        presentPrompt(prompt!!)
    }

    private fun showCapturePrompt() {
        if (closed || token == null || prompt?.isShowing == true || dialogQueue.isEmpty()) return
        val data = dialogQueue.removeFirst()
        val session = token!!
        val id = data.getInt("id")
        var resolved = false
        fun resolve(value: Any?) {
            if (resolved) return
            resolved = true
            if (!closed && token == session) {
                val json = JSONObject.wrap(value)?.toString() ?: "null"
                val encoded = if (value is String) JSONObject.quote(value) else json
                web.evaluateJavascript("window.__xudianDialogResolve && window.__xudianDialogResolve(${JSONObject.quote(session)}, $id, $encoded)", null)
            }
        }
        val builder = AlertDialog.Builder(context).setTitle(data.optString("title", "导入课表"))
        val message = data.optString("content")
        if (message.isNotEmpty()) builder.setMessage(message)
        val kind = data.optString("kind")
        when (kind) {
            "prompt" -> {
                val input = promptInput(data.optString("initial"))
                builder.setView(promptContainer(input)).setPositiveButton("继续") { _, _ -> resolve(input.text.toString()) }
            }
            "selection" -> {
                val raw = data.getJSONArray("items")
                val items = Array(raw.length()) { raw.getString(it) }
                builder.setSingleChoiceItems(items, data.optInt("selected", -1)) { dialog, index ->
                    resolve(index)
                    dialog.dismiss()
                }
            }
            else -> builder.setPositiveButton(data.optString("confirmLabel", "确定")) { _, _ -> resolve(true) }
        }
        if (kind != "alert") builder.setNegativeButton("取消") { _, _ -> resolve(if (kind == "confirm") false else null) }
        prompt = builder.create().apply {
            setOnCancelListener { resolve(if (kind == "confirm") false else null) }
            setOnDismissListener {
                resolve(if (kind == "confirm") false else null)
                prompt = null
                showCapturePrompt()
            }
        }
        presentPrompt(prompt!!)
    }

    private fun failLoading(message: String, url: String) {
        loadFailed = true
        failedUrl = url
        pageReady = false
        token = null
        dialogQueue.clear()
        prompt?.dismiss()
        run.isEnabled = false
        progress.visibility = View.GONE
        status.setTextColor(appearance.error)
        status.text = message
    }

    private fun dp(value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

    private fun rounded(color: Int, radius: Float = appearance.controlRadius, outline: Int? = null): Drawable =
        BrowserSurfaceDrawable(color, radius * context.resources.displayMetrics.density, outline,
            (appearance.primary and 0x00ffffff) or 0x80000000.toInt(), context.resources.displayMetrics.density)

    private fun actionLayout() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)

    private fun actionButton(label: String, outlined: Boolean = true, action: () -> Unit) = Button(context).apply {
        styleButton(this, outlined = outlined)
        text = label
        setOnClickListener { action() }
    }

    private fun styleButton(button: Button, primary: Boolean = false, outlined: Boolean = false) {
        button.isAllCaps = false
        button.textSize = 14f
        button.minWidth = dp(48)
        button.minimumWidth = dp(48)
        button.minHeight = dp(48)
        button.minimumHeight = dp(48)
        button.setPadding(dp(20), dp(12), dp(20), dp(12))
        val background = if (primary) appearance.primary else if (outlined) appearance.surface else Color.TRANSPARENT
        button.backgroundTintList = null
        val backgrounds = StateListDrawable().apply {
            addState(intArrayOf(-android.R.attr.state_enabled), rounded(appearance.input))
            addState(intArrayOf(), rounded(background, outline = if (outlined) appearance.outline else null))
        }
        button.background = RippleDrawable(
            ColorStateList.valueOf((appearance.primary and 0x00ffffff) or 0x22000000),
            backgrounds,
            rounded(Color.WHITE))
        button.stateListAnimator = null
        button.elevation = 0f
        val states = arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf())
        button.setTextColor(ColorStateList(states, intArrayOf(
            appearance.muted, if (primary) appearance.onPrimary else appearance.primary)))
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
                        "dialog" -> {
                            val request = data.getJSONObject("value")
                            if (request.optString("kind") !in listOf("alert", "confirm", "prompt", "selection")) return@post
                            if (request.optInt("id") <= 0 || dialogQueue.size >= 32) return@post
                            dialogQueue.addLast(request)
                            showCapturePrompt()
                        }
                        "status" -> status.text = data.optString("value").take(1000)
                        "error" -> {
                            status.text = "采集未完成：${data.optString("value").take(1000)}"
                            token = null
                            dialogQueue.clear()
                            prompt?.dismiss()
                        }
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
