package com.hisaab.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsBroadcastReceiver : BroadcastReceiver() {

    private val mobilePattern = Regex("""^\+?91?\d{10}$""")

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val sender = messages[0].originatingAddress ?: return
        val body   = messages.joinToString("") { it.messageBody }

        if (body.isBlank()) return
        if (mobilePattern.matches(sender)) return

        val parsed = SmsParser.parse(body) ?: return

        val db = DatabaseHelper(context)
        if (db.refExists(parsed.refNumber)) return

        val merchant = db.getMerchant(parsed.payeeKey)

        val overlayIntent = Intent(context, OverlayService::class.java).apply {
            putExtra("amount",        parsed.amount)
            putExtra("type",          parsed.type)
            putExtra("payee_key",     parsed.payeeKey)
            putExtra("payee_hint",    parsed.payeeHint)
            putExtra("ref_number",    parsed.refNumber)
            putExtra("body",          body)
            putExtra("is_refund",     parsed.isRefund)
            if (merchant != null) {
                putExtra("mode",          "known")
                putExtra("merchant_name", merchant.first)
                putExtra("category",      merchant.second)
            } else {
                putExtra("mode", "unknown")
            }
        }
        context.startService(overlayIntent)
    }
}
