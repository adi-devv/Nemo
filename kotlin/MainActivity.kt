package com.hisaab.app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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

    private val txnSavedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            runOnUiThread {
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, "com.hisaab.app/events")
                        .invokeMethod("txn_saved", null)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerReceiver(txnSavedReceiver,
            IntentFilter(OverlayService.ACTION_TXN_SAVED))
    }

    override fun onDestroy() {
        try { unregisterReceiver(txnSavedReceiver) } catch (_: Exception) {}
        super.onDestroy()
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
                        val sqDb       = db.readableDatabase
                        val status     = call.argument<String>("status") ?: "confirmed"
                        val limit      = call.argument<Int>("limit") ?: 20
                        val offset     = call.argument<Int>("offset") ?: 0
                        val conditions = mutableListOf("status = ?")
                        val args       = mutableListOf(status)

                        if (from != null) { conditions.add("timestamp >= ?"); args.add(from.toString()) }
                        if (to   != null) { conditions.add("timestamp < ?");  args.add(to.toString()) }
                        if (cat  != null) { conditions.add("category = ?");   args.add(cat) }

                        val where = conditions.joinToString(" AND ")
                        val c = sqDb.query("transactions", null, where, args.toTypedArray(),
                            null, null, "timestamp DESC", "$limit OFFSET $offset")
                        val list = mutableListOf<Map<String, Any>>()
                        while (c.moveToNext()) {
                            list.add(mapOf(
                                "id"               to c.getLong(c.getColumnIndexOrThrow("id")),
                                "ref_number"       to c.getString(c.getColumnIndexOrThrow("ref_number")),
                                "payee_key"        to c.getString(c.getColumnIndexOrThrow("payee_key")),
                                "merchant_name"    to c.getString(c.getColumnIndexOrThrow("merchant_name")),
                                "category"         to c.getString(c.getColumnIndexOrThrow("category")),
                                "amount"           to c.getDouble(c.getColumnIndexOrThrow("amount")),
                                "type"             to c.getString(c.getColumnIndexOrThrow("type")),
                                "timestamp"        to c.getLong(c.getColumnIndexOrThrow("timestamp")),
                                "status"           to c.getString(c.getColumnIndexOrThrow("status")),
                                "linked_payee_key" to (c.getString(c.getColumnIndexOrThrow("linked_payee_key")) ?: ""),
                                "is_cash"          to (c.getInt(c.getColumnIndexOrThrow("is_cash")) == 1),
                            ))
                        }
                        c.close()
                        result.success(list)
                    }

                    "getCategoryTotals" -> {
                        result.success(db.getCategoryTotals(from, to))
                    }

                    "getCategoryFrequency" -> {
                        result.success(db.getTopCategories())
                    }

                    "getWeeklyTotals" -> {
                        val year  = call.argument<Int>("year")  ?: return@setMethodCallHandler
                        val month = call.argument<Int>("month") ?: return@setMethodCallHandler
                        val raw   = db.getWeeklyTotals(year, month)
                        // Convert Map<Int, Map<String,Double>> to Flutter-friendly Map<String, Map<String,Double>>
                        result.success(raw.map { (wk, cats) -> wk.toString() to cats }.toMap())
                    }

                    "getDailyTotals" -> {
                        val fromTs = call.argument<String>("from")?.toLongOrNull()
                            ?: return@setMethodCallHandler
                        result.success(db.getDailyTotals(fromTs))
                    }

                    // Save a cash transaction from Flutter
                    "saveCashTransaction" -> {
                        val amount   = call.argument<Double>("amount") ?: 0.0
                        val name     = call.argument<String>("merchant_name") ?: "Cash"
                        val category = call.argument<String>("category") ?: "Misc"
                        val type     = call.argument<String>("type") ?: "debit"
                        val ref      = "CASH_${System.currentTimeMillis()}"
                        val key      = "CASH_${name.uppercase().replace(" ", "_")}"
                        db.saveMerchant(key, name, category)
                        db.saveTransaction(ref, key, name, category, amount, type, isCash = true)
                        result.success(mapOf(
                            "merchant_name" to name,
                            "category"      to category,
                            "amount"        to amount,
                            "type"          to type,
                        ))
                    }

                    // Confirm a pending transaction
                    "confirmTransaction" -> {
                        val id             = call.argument<Int>("id")?.toLong() ?: return@setMethodCallHandler
                        val name           = call.argument<String>("merchant_name") ?: ""
                        val category       = call.argument<String>("category") ?: "Misc"
                        val linkedPayeeKey = call.argument<String>("linked_payee_key")
                        val payeeKey       = call.argument<String>("payee_key") ?: ""
                        if (name.isNotBlank()) db.saveMerchant(payeeKey, name, category)
                        db.confirmTransaction(id, name, category, linkedPayeeKey)
                        result.success(null)
                    }

                    // Delete a transaction (for dismissing pending items)
                    "deleteTransaction" -> {
                        val id = call.argument<Int>("id")?.toLong() ?: return@setMethodCallHandler
                        db.deleteTransaction(id)
                        result.success(null)
                    }

                    "updateCategory" -> {
                        val id       = call.argument<Int>("id")?.toLong() ?: return@setMethodCallHandler
                        val category = call.argument<String>("category") ?: return@setMethodCallHandler
                        db.writableDatabase.execSQL(
                            "UPDATE transactions SET category=? WHERE id=?",
                            arrayOf(category, id)
                        )
                        result.success(null)
                    }

                    "updateVendorCategory" -> {
                        val payeeKey = call.argument<String>("payee_key") ?: return@setMethodCallHandler
                        val category = call.argument<String>("category") ?: return@setMethodCallHandler
                        val wdb = db.writableDatabase
                        // Update merchant record so future transactions use new category
                        wdb.execSQL("UPDATE merchants SET category=? WHERE payee_key=?",
                            arrayOf(category, payeeKey))
                        // Update all existing transactions for this vendor
                        wdb.execSQL("UPDATE transactions SET category=? WHERE payee_key=?",
                            arrayOf(category, payeeKey))
                        result.success(null)
                    }

                    // Recent debit merchants for refund linking
                    "getRecentMerchants" -> {
                        val merchants = db.getRecentMerchants()
                        result.success(merchants)
                    }

                    // Scan SMS inbox for past transactions
                    "scanInbox" -> {
                        val fromTs = call.argument<String>("from")?.toLongOrNull()
                            ?: return@setMethodCallHandler

                        val uri    = android.net.Uri.parse("content://sms/inbox")
                        val cursor = contentResolver.query(uri,
                            arrayOf("address", "body", "date"),
                            "date >= ?", arrayOf(fromTs.toString()),
                            "date DESC"
                        )

                        val mobilePattern = Regex("""^\+?91?\d{10}$""")
                        val groups    = mutableMapOf<String, MutableList<Map<String, Any>>>()
                        val knownSaved = mutableListOf<String>()

                        cursor?.use { c ->
                            val addrIdx = c.getColumnIndex("address")
                            val bodyIdx = c.getColumnIndex("body")
                            val dateIdx = c.getColumnIndex("date")
                            while (c.moveToNext()) {
                                val sender    = c.getString(addrIdx) ?: continue
                                val body      = c.getString(bodyIdx) ?: continue
                                val smsDate   = c.getLong(dateIdx)   // actual payment date
                                if (mobilePattern.matches(sender)) continue
                                val parsed = SmsParser.parse(body) ?: continue
                                if (db.refExists(parsed.refNumber)) continue

                                val merchant = db.getMerchant(parsed.payeeKey)
                                if (merchant != null) {
                                    db.saveTransaction(parsed.refNumber, parsed.payeeKey,
                                        merchant.first, merchant.second,
                                        parsed.amount, parsed.type,
                                        timestamp = smsDate)
                                    knownSaved.add(parsed.refNumber)
                                } else {
                                    val entry = mapOf(
                                        "ref_number"  to parsed.refNumber,
                                        "amount"      to parsed.amount,
                                        "type"        to parsed.type,
                                        "payee_key"   to parsed.payeeKey,
                                        "payee_hint"  to parsed.payeeHint,
                                        "is_refund"   to parsed.isRefund,
                                        "timestamp"   to smsDate,
                                    )
                                    groups.getOrPut(parsed.payeeKey) { mutableListOf() }.add(entry)
                                }
                            }
                        }

                        val unknownGroups = groups.map { (key, txns) ->
                            val totalAmt = txns.sumOf { (it["amount"] as Double) }
                            mapOf(
                                "payee_key"  to key,
                                "payee_hint" to (txns.first()["payee_hint"] as String),
                                "is_refund"  to (txns.first()["is_refund"] as Boolean),
                                "count"      to txns.size,
                                "total"      to totalAmt,
                                "txns"       to txns,
                            )
                        }

                        result.success(mapOf(
                            "known_count"    to knownSaved.size,
                            "unknown_groups" to unknownGroups,
                        ))
                    }

                    // Save a scanned group (all txns for one payee)
                    "saveScanGroup" -> {
                        val payeeKey = call.argument<String>("payee_key") ?: return@setMethodCallHandler
                        val name     = call.argument<String>("name") ?: return@setMethodCallHandler
                        val category = call.argument<String>("category") ?: return@setMethodCallHandler
                        val txnsList = call.argument<List<Map<String, Any>>>("txns")
                            ?: return@setMethodCallHandler

                        db.saveMerchant(payeeKey, name, category)
                        for (t in txnsList) {
                            val ts = (t["timestamp"] as? Long)
                                ?: (t["timestamp"] as? Int)?.toLong()
                                ?: System.currentTimeMillis()
                            db.saveTransaction(
                                t["ref_number"] as String,
                                payeeKey, name, category,
                                (t["amount"] as Double),
                                t["type"] as String,
                                timestamp = ts,
                            )
                        }
                        result.success(null)
                    }

                    "getUserCategories" -> {
                        result.success(db.getUserCategories())
                    }

                    "addUserCategory" -> {
                        val name = call.argument<String>("name") ?: return@setMethodCallHandler
                        // Don't persist default categories — they're always there
                        if (!DatabaseHelper.DEFAULT_CATEGORIES.contains(name)) {
                            db.addUserCategory(name)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}