package com.hisaab.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Permissions channel ───────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hisaab.app/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkSms" -> result.success(
                        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS)
                                == PackageManager.PERMISSION_GRANTED
                    )
                    "checkOverlay" -> result.success(Settings.canDrawOverlays(this))
                    "requestSms" -> {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
                            101
                        )
                        result.success(null)
                    }
                    "requestOverlay" -> {
                        startActivity(Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── DB channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hisaab.app/db")
            .setMethodCallHandler { call, result ->
                val db   = DatabaseHelper(this)
                val from = call.argument<String>("from")?.toLongOrNull()
                val to   = call.argument<String>("to")?.toLongOrNull()
                val cat  = call.argument<String>("category")

                when (call.method) {
                    "getTransactions" -> {
                        val sqDb      = db.readableDatabase
                        val conditions = mutableListOf<String>()
                        val args       = mutableListOf<String>()

                        if (from != null) { conditions.add("timestamp >= ?"); args.add(from.toString()) }
                        if (to   != null) { conditions.add("timestamp < ?");  args.add(to.toString()) }
                        if (cat  != null) { conditions.add("category = ?");   args.add(cat) }

                        val where = if (conditions.isEmpty()) null else conditions.joinToString(" AND ")
                        val whereArgs = if (args.isEmpty()) null else args.toTypedArray()

                        val c = sqDb.query("transactions", null, where, whereArgs,
                            null, null, "timestamp DESC")
                        val list = mutableListOf<Map<String, Any>>()
                        while (c.moveToNext()) {
                            list.add(mapOf(
                                "id"            to c.getLong(c.getColumnIndexOrThrow("id")),
                                "ref_number"    to c.getString(c.getColumnIndexOrThrow("ref_number")),
                                "payee_key"     to c.getString(c.getColumnIndexOrThrow("payee_key")),
                                "merchant_name" to c.getString(c.getColumnIndexOrThrow("merchant_name")),
                                "category"      to c.getString(c.getColumnIndexOrThrow("category")),
                                "amount"        to c.getDouble(c.getColumnIndexOrThrow("amount")),
                                "type"          to c.getString(c.getColumnIndexOrThrow("type")),
                                "timestamp"     to c.getLong(c.getColumnIndexOrThrow("timestamp"))
                            ))
                        }
                        c.close()
                        result.success(list)
                    }

                    "getCategoryTotals" -> {
                        val sqDb       = db.readableDatabase
                        val conditions = mutableListOf("type='debit'")
                        val args       = mutableListOf<String>()

                        if (from != null) { conditions.add("timestamp >= ?"); args.add(from.toString()) }
                        if (to   != null) { conditions.add("timestamp < ?");  args.add(to.toString()) }

                        val c = sqDb.rawQuery("""
                            SELECT category, SUM(amount) as total
                            FROM transactions
                            WHERE ${conditions.joinToString(" AND ")}
                            GROUP BY category
                            ORDER BY total DESC
                        """, if (args.isEmpty()) null else args.toTypedArray())

                        val map = mutableMapOf<String, Double>()
                        while (c.moveToNext()) map[c.getString(0)] = c.getDouble(1)
                        c.close()
                        result.success(map)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}