package com.hisaab.app

data class ParsedSms(
    val amount: Double,
    val type: String,       // "debit" | "credit"
    val refNumber: String,  // unique per transaction
    val payeeKey: String,   // normalized name or UPI ID — used as merchant key
    val payeeHint: String,  // raw name to pre-fill overlay
)

object SmsParser {

    fun parse(sms: String): ParsedSms? {
        return parseHdfcDebit(sms)
            ?: parseCreditWithVpa(sms)
            ?: parseGenericCredit(sms)
    }

    // ── HDFC debit format ─────────────────────────────────────────
    // Sent Rs.61.00
    // From HDFC Bank A/C *0516
    // To ROPPEN TRANSPORTATION SER
    // On 14/03/26
    // Ref 119989749015

    private fun parseHdfcDebit(sms: String): ParsedSms? {
        if (!sms.startsWith("Sent Rs.", ignoreCase = true) &&
            !sms.contains("Sent Rs.", ignoreCase = true)) return null

        val amount = parseAmount(sms) ?: return null

        // Extract "To <NAME>" — everything after "To " until newline
        val toMatch = Regex("""(?:^|\n)To\s+(.+)""", RegexOption.MULTILINE).find(sms)
            ?: return null
        val payeeName = toMatch.groupValues[1].trim()
        if (payeeName.isBlank()) return null

        // Extract Ref number
        val refMatch = Regex("""Ref\s+(\d+)""", RegexOption.IGNORE_CASE).find(sms)
            ?: return null
        val refNumber = refMatch.groupValues[1]

        // Normalize payee name as key — uppercase, collapse spaces
        val payeeKey = payeeName.uppercase().replace(Regex("""\s+"""), " ").trim()

        return ParsedSms(
            amount    = amount,
            type      = "debit",
            refNumber = refNumber,
            payeeKey  = payeeKey,
            payeeHint = toTitleCase(payeeName),
        )
    }

    // ── Credit with VPA ───────────────────────────────────────────
    // Rs.189.00 credited to HDFC Bank A/c XX0516
    // from VPA gpayrefund-online@axisbank (UPI 332441830756)

    private fun parseCreditWithVpa(sms: String): ParsedSms? {
        val lower = sms.lowercase()
        if (!lower.contains("credit")) return null

        val amount = parseAmount(sms) ?: return null

        // Extract VPA
        val vpaMatch = Regex("""[\w.\-]+@[a-zA-Z]+""").find(sms) ?: return null
        val upiId    = vpaMatch.value.lowercase()

        // Ref — UPI number or transaction ref
        val refMatch = Regex("""(?:UPI|Ref)\s*[:\s]*(\d{10,})""", RegexOption.IGNORE_CASE).find(sms)
        val refNumber = refMatch?.groupValues?.get(1) ?: System.currentTimeMillis().toString()

        // Hint from VPA handle
        val handle    = upiId.split("@")[0]
            .replace(Regex("""\d"""), "")
            .replace(Regex("""[._\-]"""), " ")
            .trim()
        val payeeHint = if (handle.length >= 3) toTitleCase(handle) else upiId

        return ParsedSms(
            amount    = amount,
            type      = "credit",
            refNumber = refNumber,
            payeeKey  = upiId,
            payeeHint = payeeHint,
        )
    }

    // ── Generic credit (NEFT, IMPS etc) ──────────────────────────
    // INR 40000.00 credited to A/c no. XX3970
    // NEFT/IN42606658070653/ANUB

    private fun parseGenericCredit(sms: String): ParsedSms? {
        val lower = sms.lowercase()
        if (!lower.contains("credit") && !lower.contains("credited")) return null

        val amount = parseAmount(sms) ?: return null

        // Ref from NEFT/IMPS/UPI ref patterns
        val refMatch = Regex("""(?:NEFT|IMPS|UPI|Ref)[/\s]*([A-Z0-9]{10,})""",
            RegexOption.IGNORE_CASE).find(sms)
        val refNumber = refMatch?.groupValues?.get(1) ?: return null

        return ParsedSms(
            amount    = amount,
            type      = "credit",
            refNumber = refNumber,
            payeeKey  = "NEFT_$refNumber",
            payeeHint = "Bank Transfer",
        )
    }

    // ── Helpers ───────────────────────────────────────────────────

    private fun parseAmount(sms: String): Double? {
        val rx = Regex("""(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)""", RegexOption.IGNORE_CASE)
        return rx.find(sms)?.groupValues?.get(1)?.replace(",", "")?.toDoubleOrNull()
    }

    private fun toTitleCase(s: String): String =
        s.trim().split(Regex("""\s+"""))
            .joinToString(" ") { w ->
                if (w.isEmpty()) ""
                else w[0].uppercaseChar() + w.substring(1).lowercase()
            }
}
