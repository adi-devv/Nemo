package com.hisaab.app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class DatabaseHelper(context: Context) : SQLiteOpenHelper(context, "hisaab.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        // payee_key = normalized payee name (for debit) or UPI ID (for credit)
        db.execSQL("""
            CREATE TABLE merchants (
                payee_key TEXT PRIMARY KEY,
                name      TEXT NOT NULL,
                category  TEXT NOT NULL
            )
        """)
        db.execSQL("""
            CREATE TABLE transactions (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                ref_number    TEXT    UNIQUE NOT NULL,
                payee_key     TEXT    NOT NULL,
                merchant_name TEXT    NOT NULL,
                category      TEXT    NOT NULL,
                amount        REAL    NOT NULL,
                type          TEXT    NOT NULL,
                timestamp     INTEGER NOT NULL
            )
        """)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

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
        timestamp: Long = System.currentTimeMillis()
    ) {
        val db = writableDatabase
        val v  = ContentValues().apply {
            put("ref_number",    refNumber)
            put("payee_key",     payeeKey)
            put("merchant_name", merchantName)
            put("category",      category)
            put("amount",        amount)
            put("type",          type)
            put("timestamp",     timestamp)
        }
        db.insertWithOnConflict("transactions", null, v, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun getTopCategories(): List<String> {
        val db   = readableDatabase
        val c    = db.rawQuery("""
            SELECT category FROM transactions
            WHERE type = 'debit'
            GROUP BY category
            ORDER BY SUM(amount) DESC
            LIMIT 6
        """, null)
        val list = mutableListOf<String>()
        while (c.moveToNext()) list.add(c.getString(0))
        c.close()
        return list
    }
}
