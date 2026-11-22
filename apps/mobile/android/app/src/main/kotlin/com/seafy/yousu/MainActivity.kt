package com.seafy.yousu

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initial: String? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 28) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        if (Build.VERSION.SDK_INT >= 29) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        initial = intent?.dataString
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.seafy.yousu/system")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "openPurchaseLink" -> {
                    try { val uri = Uri.parse(call.arguments as String); require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrEmpty() && uri.userInfo.isNullOrEmpty()); startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(true) } catch(e: Exception) { result.success(false) }
                }
                "openExternal" -> {
                    try { val uri=Uri.parse(call.arguments as String); require(uri.scheme in listOf("https","mailto")); startActivity(Intent(Intent.ACTION_VIEW,uri)); result.success(true) } catch(e:Exception) {result.success(false)}
                }
                "appVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(mapOf("version" to info.versionName, "build" to if(Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()))
                }
                "canInstallUpdates" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "updateDirectory" -> { val dir = File(cacheDir, "updates"); dir.mkdirs(); result.success(dir.absolutePath) }
                "installUpdate" -> {
                    try {
                        val file = File(call.argument<String>("path") ?: "").canonicalFile
                        require(file.parentFile == File(cacheDir,"updates").canonicalFile && file.name == "youshu-update.apk") { "无效安装路径" }
                        val flags = if(Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                        val current = packageManager.getPackageInfo(packageName, flags)
                        val archive = packageManager.getPackageArchiveInfo(file.path, flags) ?: error("无法读取安装包")
                        require(archive.packageName == packageName) { "安装包应用标识不匹配" }
                        val version = if(Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
                        val currentVersion = if(Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
                        require(version == call.argument<Number>("build")!!.toLong() && version > currentVersion) { "安装包版本无效" }
                        val oldSign = if(Build.VERSION.SDK_INT >= 28) current.signingInfo!!.apkContentsSigners else current.signatures!!
                        val newSign = if(Build.VERSION.SDK_INT >= 28) archive.signingInfo!!.apkContentsSigners else archive.signatures!!
                        require(oldSign.map { it.toCharsString() }.toSet() == newSign.map { it.toCharsString() }.toSet()) { "安装包签名不匹配" }
                        if(Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                            result.success(false)
                        } else {
                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                            startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            result.success(true)
                        }
                    } catch(e:Exception) { result.error("UPDATE",e.message,null) }
                }
                "initialAction" -> { result.success(initial); initial = null }
                "updateWidget" -> {
                    val edit = getSharedPreferences("yousu_widget", MODE_PRIVATE).edit()
                    for (key in listOf("ledger", "expense", "remaining", "updated", "period")) edit.putString(key, call.argument<String>(key))
                    edit.apply()
                    YousuWidget.updateAll(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.dataString?.let { channel?.invokeMethod("quickAdd", it) }
    }
}
