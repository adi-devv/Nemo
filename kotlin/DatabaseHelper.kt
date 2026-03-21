package com.hisaab.app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class DatabaseHelper(context: Context) : SQLiteOpenHelper(context, "hisaab.db", null, 4) {

    companion object {
        // Ordered default categories — always present, always in this base order
        val DEFAULT_CATEGORIES = listOf(
            "Rent", "Food", "Travel", "Shopping", "Misc"
        )
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE merchants (
                payee_key TEXT PRIMARY KEY,
                name      TEXT NOT NULL,
                category  TEXT NOT NULL
            )
        """)
        db.execSQL("""
            CREATE TABLE transactions (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                ref_number       TEXT    UNIQUE NOT NULL,
                payee_key        TEXT    NOT NULL,
                merchant_name    TEXT    NOT NULL,
                category         TEXT    NOT NULL,
                amount           REAL    NOT NULL,
                type             TEXT    NOT NULL,
                timestamp        INTEGER NOT NULL,
                status           TEXT    NOT NULL DEFAULT 'confirmed',
                linked_payee_key TEXT,
                is_cash          INTEGER NOT NULL DEFAULT 0
            )
        """)
        db.execSQL("""
            CREATE TABLE user_categories (
                name       TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL DEFAULT 0
            )
        """)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE transactions ADD COLUMN status TEXT NOT NULL DEFAULT 'confirmed'")
            db.execSQL("ALTER TABLE transactions ADD COLUMN linked_payee_key TEXT")
        }
        if (oldVersion < 3) {
            db.execSQL("ALTER TABLE transactions ADD COLUMN is_cash INTEGER NOT NULL DEFAULT 0")
        }
        if (oldVersion < 4) {
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS user_categories (
                    name       TEXT PRIMARY KEY,
                    created_at INTEGER NOT NULL DEFAULT 0
                )
            """)
        }
    }

    // ── Merchants ─────────────────────────────────────────────────

    fun getMerchant(payeeKey: String): Pair<String, String>? {
        val db = readableDatabase
        val c  = db.query("merchants", null, "payee_key=?", arrayOf(payeeKey), null, null, null)
        return if (c.moveToFirst()) {
            val name = c.getString(c.getColumnIndexOrThrow("name"))
            val cat  = c.getString(c.getColumnIndexOrThrow("category"))
            c.close()
            Pair(name, cat)
        } else { c.close(); null }
    }

    fun saveMerchant(payeeKey: String, name: String, category: String) {
        val db = writableDatabase
        val v  = ContentValues().apply {
            put("payee_key", payeeKey)
            put("name", name)
            put("category", category)
        }
        db.insertWithOnConflict("merchants", null, v, SQLiteDatabase.CONFLICT_REPLACE)
    }

    // Returns list of recent debit merchants for the refund picker
    fun getRecentMerchants(limit: Int = 20): List<Map<String, String>> {
        val db = readableDatabase
        val c  = db.rawQuery("""
            SELECT DISTINCT m.payee_key, m.name, m.category
            FROM merchants m
            INNER JOIN transactions t ON t.payee_key = m.payee_key
            WHERE t.type = 'debit'
            ORDER BY t.timestamp DESC
            LIMIT ?
        """, arrayOf(limit.toString()))
        val list = mutableListOf<Map<String, String>>()
        while (c.moveToNext()) {
            list.add(mapOf(
                "payee_key" to c.getString(0),
                "name"      to c.getString(1),
                "category"  to c.getString(2),
            ))
        }
        c.close()
        return list
    }

    // ── Transactions ──────────────────────────────────────────────

    fun refExists(refNumber: String): Boolean {
        val db = readableDatabase
        val c  = db.query("transactions", arrayOf("id"), "ref_number=?",
            arrayOf(refNumber), null, null, null)
        val exists = c.moveToFirst()
        c.close()
        return exists
    }

    fun saveTransaction(
        refNumber: String,
        payeeKey: String,
        merchantName: String,
        category: String,
        amount: Double,
        type: String,
        timestamp: Long = System.currentTimeMillis(),
        status: String = "confirmed",
        linkedPayeeKey: String? = null,
        isCash: Boolean = false,
    ) {
        val db = writableDatabase
        val v  = ContentValues().apply {
            put("ref_number",       refNumber)
            put("payee_key",        payeeKey)
            put("merchant_name",    merchantName)
            put("category",         category)
            put("amount",           amount)
            put("type",             type)
            put("timestamp",        timestamp)
            put("status",           status)
            put("linked_payee_key", linkedPayeeKey)
            put("is_cash",          if (isCash) 1 else 0)
        }
        db.insertWithOnConflict("transactions", null, v, SQLiteDatabase.CONFLICT_IGNORE)
    }

    // Confirm a pending transaction (update name, category, linked merchant)
    fun confirmTransaction(
        id: Long,
        merchantName: String,
        category: String,
        linkedPayeeKey: String? = null,
    ) {
        val db = writableDatabase
        val v  = ContentValues().apply {
            put("merchant_name",    merchantName)
            put("category",         category)
            put("status",           "confirmed")
            put("linked_payee_key", linkedPayeeKey)
        }
        db.update("transactions", v, "id=?", arrayOf(id.toString()))
    }

    fun deleteTransaction(id: Long) {
        writableDatabase.delete("transactions", "id=?", arrayOf(id.toString()))
    }

    // ── User categories (persisted custom categories) ─────────────

    fun getUserCategories(): List<String> {
        val db = readableDatabase
        val c  = db.rawQuery(
            "SELECT name FROM user_categories ORDER BY created_at ASC", null)
        val list = mutableListOf<String>()
        while (c.moveToNext()) list.add(c.getString(0))
        c.close()
        return list
    }

    fun addUserCategory(name: String) {
        val db = writableDatabase
        val v  = ContentValues().apply {
            put("name", name)
            put("created_at", System.currentTimeMillis())
        }
        db.insertWithOnConflict("user_categories", null, v, SQLiteDatabase.CONFLICT_IGNORE)
    }

    /**
     * Returns the full ordered category list:
     * 1. All categories sorted by usage frequency (most-used first), excluding Misc
     * 2. Any default or user categories not yet used (preserving default order, then user order)
     * 3. Misc always last
     *
     * Defaults are always present. User-added categories are always present.
     */
    fun getTopCategories(): List<String> {
        val db = readableDatabase

        // Frequency-ranked categories from transactions
        val c = db.rawQuery("""
            SELECT category, COUNT(*) as cnt FROM transactions
            WHERE status = 'confirmed'
            GROUP BY category
            ORDER BY cnt DESC
        """, null)
        val freqOrder = mutableListOf<String>()
        while (c.moveToNext()) {
            val cat = c.getString(0)
            if (cat != "Misc" && cat != "Uncategorised") freqOrder.add(cat)
        }
        c.close()

        // All known categories: defaults + user-added
        val userCats = getUserCategories()
        val allKnown = (DEFAULT_CATEGORIES.filter { it != "Misc" } + userCats).distinct()

        // Build final list: frequency-ranked first, then remaining known cats not yet in list
        val seen   = mutableSetOf<String>()
        val result = mutableListOf<String>()

        for (cat in freqOrder) {
            if (seen.add(cat)) result.add(cat)
        }
        // Append any default/user cats not seen in frequency list (preserves ordering)
        for (cat in allKnown) {
            if (seen.add(cat)) result.add(cat)
        }

        result.add("Misc")
        return result
    }

    // ── Shared spending helpers ────────────────────────────────────
    // Credits are treated as negative debits — one pass, no second query.
    // SUM(CASE WHEN type='debit' THEN amount ELSE -amount END) gives net spend.

    fun getCategoryTotals(from: Long?, to: Long?): Map<String, Double> {
        val db         = readableDatabase
        val conditions = mutableListOf("status='confirmed'")
        val args       = mutableListOf<String>()
        if (from != null) { conditions.add("timestamp >= ?"); args.add(from.toString()) }
        if (to   != null) { conditions.add("timestamp < ?");  args.add(to.toString()) }

        val c = db.rawQuery("""
            SELECT category,
                   SUM(CASE WHEN type='debit' THEN amount ELSE -amount END) AS net
            FROM transactions
            WHERE ${conditions.joinToString(" AND ")}
            GROUP BY category
            HAVING net > 0
            ORDER BY net DESC
        """, if (args.isEmpty()) null else args.toTypedArray())

        val map = mutableMapOf<String, Double>()
        while (c.moveToNext()) map[c.getString(0)] = c.getDouble(1)
        c.close()
        return map
    }

    fun getWeeklyTotals(year: Int, month: Int): Map<Int, Map<String, Double>> {
        val from = java.util.Calendar.getInstance().apply {
            set(year, month - 1, 1, 0, 0, 0); set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
        val to   = java.util.Calendar.getInstance().apply {
            set(year, month, 1, 0, 0, 0); set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis

        val result = mutableMapOf<Int, MutableMap<String, Double>>().apply {
            (1..4).forEach { put(it, mutableMapOf()) }
        }

        val c = readableDatabase.rawQuery("""
            SELECT type, category, amount, timestamp
            FROM transactions
            WHERE status='confirmed' AND timestamp >= ? AND timestamp < ?
        """, arrayOf(from.toString(), to.toString()))

        while (c.moveToNext()) {
            val isDebit = c.getString(0) == "debit"
            val cat     = c.getString(1)
            val amt     = if (isDebit) c.getDouble(2) else -c.getDouble(2)
            val day     = java.util.Calendar.getInstance()
                .apply { timeInMillis = c.getLong(3) }
                .get(java.util.Calendar.DAY_OF_MONTH)
            val wk      = when { day <= 7 -> 1; day <= 14 -> 2; day <= 21 -> 3; else -> 4 }
            val wkMap   = result[wk]!!
            wkMap[cat]  = maxOf(0.0, (wkMap[cat] ?: 0.0) + amt)
        }
        c.close()
        return result
    }

    fun getDailyTotals(fromTs: Long): Map<String, Map<String, Double>> {
        val result = mutableMapOf<String, MutableMap<String, Double>>()

        val c = readableDatabase.rawQuery("""
            SELECT type, category, amount, timestamp
            FROM transactions
            WHERE status='confirmed' AND timestamp >= ?
        """, arrayOf(fromTs.toString()))

        while (c.moveToNext()) {
            val isDebit = c.getString(0) == "debit"
            val cat     = c.getString(1)
            val amt     = if (isDebit) c.getDouble(2) else -c.getDouble(2)
            val cal     = java.util.Calendar.getInstance().apply { timeInMillis = c.getLong(3) }
            val key     = "${cal.get(java.util.Calendar.DAY_OF_MONTH)}/${cal.get(java.util.Calendar.MONTH) + 1}"
            val dayMap  = result.getOrPut(key) { mutableMapOf() }
            dayMap[cat] = maxOf(0.0, (dayMap[cat] ?: 0.0) + amt)
        }
        c.close()
        return result
    }
}