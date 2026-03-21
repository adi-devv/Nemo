package com.hisaab.app

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.*

class OverlayService : Service() {

    private var wm: WindowManager? = null
    private var root: LinearLayout? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val amount       = intent?.getDoubleExtra("amount", 0.0) ?: 0.0
        val type         = intent?.getStringExtra("type") ?: "debit"
        val payeeKey     = intent?.getStringExtra("payee_key") ?: ""
        val payeeHint    = intent?.getStringExtra("payee_hint") ?: ""
        val refNumber    = intent?.getStringExtra("ref_number") ?: ""
        val body         = intent?.getStringExtra("body") ?: ""
        val mode         = intent?.getStringExtra("mode") ?: "unknown"
        val merchantName = intent?.getStringExtra("merchant_name") ?: ""
        val category     = intent?.getStringExtra("category") ?: ""

        removeOverlay()

        if (mode == "known") showKnownOverlay(amount, type, merchantName, category, payeeKey, refNumber, body)
        else showUnknownOverlay(amount, type, payeeKey, payeeHint, refNumber, body)

        return START_NOT_STICKY
    }

    // ── Known merchant ────────────────────────────────────────────

    private fun showKnownOverlay(
        amount: Double, type: String,
        name: String, category: String,
        payeeKey: String, refNumber: String, body: String
    ) {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val isDebit  = type == "debit"
        val amtColor = if (isDebit) Color.parseColor("#FF453A") else Color.parseColor("#30D158")
        val prefix   = if (isDebit) "-₹" else "+₹"

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background  = card("#1C1C1E", 24f)
            setPadding(dp(24), dp(20), dp(24), dp(24))
            alpha = 0f; translationY = dp(40).toFloat()
        }

        layout.addView(TextView(this).apply {
            text = "$prefix${fmt(amount)}"
            textSize = 30f; setTextColor(amtColor)
            typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
        })
        layout.addView(TextView(this).apply {
            text = name; textSize = 16f; setTextColor(Color.WHITE)
            gravity = Gravity.CENTER; setPadding(0, dp(4), 0, 0)
        })
        layout.addView(TextView(this).apply {
            text = category; textSize = 13f
            setTextColor(Color.parseColor("#8E8E93"))
            gravity = Gravity.CENTER; setPadding(0, dp(2), 0, 0)
        })

        root = layout
        wm?.addView(layout, overlayParams(false))
        animateIn(layout)

        DatabaseHelper(this).saveTransaction(refNumber, payeeKey, name, category, amount, type)

        Handler(Looper.getMainLooper()).postDelayed({
            animateOut(layout) { removeOverlay(); stopSelf() }
        }, 3000)
    }

    // ── Unknown merchant ──────────────────────────────────────────

    private fun showUnknownOverlay(
        amount: Double, type: String,
        payeeKey: String, payeeHint: String,
        refNumber: String, body: String
    ) {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val isDebit  = type == "debit"
        val amtColor = if (isDebit) Color.parseColor("#FF453A") else Color.parseColor("#30D158")
        val prefix   = if (isDebit) "-₹" else "+₹"

        val db          = DatabaseHelper(this)
        val topCats     = db.getTopCategories()
        val defaults    = listOf("Food", "Commute", "Shopping", "Misc")
        val seen        = mutableSetOf<String>()
        val orderedCats = mutableListOf<String>()
        for (cat in topCats + defaults) {
            if (seen.add(cat)) orderedCats.add(cat)
            if (orderedCats.size == 5) break
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background  = card("#1C1C1E", 28f)
            setPadding(dp(24), dp(24), dp(24), dp(28))
            alpha = 0f; translationY = dp(40).toFloat()
        }

        layout.addView(TextView(this).apply {
            text = "$prefix${fmt(amount)}"
            textSize = 34f; setTextColor(amtColor)
            typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
        })
        // Show payee hint as subtitle so user knows who it is
        if (payeeHint.isNotBlank()) {
            layout.addView(TextView(this).apply {
                text = payeeHint; textSize = 13f
                setTextColor(Color.parseColor("#636366"))
                gravity = Gravity.CENTER; setPadding(0, dp(4), 0, dp(12))
            })
        }

        layout.addView(label("What's this called?"))
        val nameInput = EditText(this).apply {
            setText(payeeHint) // pre-fill with payee hint
            setSelectAllOnFocus(true)
            setHintTextColor(Color.parseColor("#48484A"))
            setTextColor(Color.WHITE); textSize = 15f
            background = card("#2C2C2E", 12f)
            setPadding(dp(16), dp(14), dp(16), dp(14)); setSingleLine(true)
        }
        layout.addView(nameInput)

        layout.addView(label("Category").apply { setPadding(0, dp(16), 0, dp(8)) })

        val chipRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        layout.addView(chipRow)

        val customInput = EditText(this).apply {
            hint = "Type category…"
            setHintTextColor(Color.parseColor("#48484A"))
            setTextColor(Color.WHITE); textSize = 14f
            background = card("#2C2C2E", 12f)
            setPadding(dp(16), dp(12), dp(16), dp(12)); setSingleLine(true)
            visibility = android.view.View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, dp(10), 0, 0) }
        }
        layout.addView(customInput)

        var selectedCategory = orderedCats.firstOrNull() ?: "Misc"
        val chips = mutableListOf<TextView>()

        fun selectChip(index: Int) {
            for (i in chips.indices) {
                chips[i].background = card(if (i == index) "#FFFFFF" else "#2C2C2E", 20f)
                chips[i].setTextColor(if (i == index) Color.BLACK else Color.parseColor("#8E8E93"))
            }
        }

        for (idx in orderedCats.indices) {
            val catName = orderedCats[idx]
            val chip = TextView(this).apply {
                text = catName; textSize = 12f
                setPadding(dp(12), dp(8), dp(12), dp(8))
                setTextColor(if (idx == 0) Color.BLACK else Color.parseColor("#8E8E93"))
                background = card(if (idx == 0) "#FFFFFF" else "#2C2C2E", 20f)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { setMargins(0, 0, dp(8), 0) }
                setOnClickListener {
                    selectedCategory = catName
                    customInput.visibility = android.view.View.GONE
                    selectChip(idx)
                }
            }
            chips.add(chip); chipRow.addView(chip)
        }

        chipRow.addView(TextView(this).apply {
            text = "+ Add"; textSize = 12f
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setTextColor(Color.parseColor("#8E8E93"))
            background = card("#2C2C2E", 20f)
            setOnClickListener {
                customInput.visibility = android.view.View.VISIBLE
                customInput.requestFocus()
                val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                imm.showSoftInput(customInput, InputMethodManager.SHOW_IMPLICIT)
                for (c in chips) {
                    c.background = card("#2C2C2E", 20f)
                    c.setTextColor(Color.parseColor("#8E8E93"))
                }
                selectedCategory = ""
            }
        })

        layout.addView(android.view.View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1)
            ).apply { setMargins(0, dp(20), 0, 0) }
            setBackgroundColor(Color.parseColor("#2C2C2E"))
        })

        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, 0)
        }
        btnRow.addView(TextView(this).apply {
            text = "Skip"; textSize = 15f
            setTextColor(Color.parseColor("#48484A")); setPadding(0, 0, dp(32), 0)
            setOnClickListener { animateOut(layout) { removeOverlay(); stopSelf() } }
        })
        btnRow.addView(TextView(this).apply {
            text = "  Save  "; textSize = 15f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.BLACK); background = card("#FFFFFF", 22f)
            setPadding(dp(28), dp(14), dp(28), dp(14))
            setOnClickListener {
                val name = nameInput.text.toString().trim()
                if (name.isEmpty()) { nameInput.hint = "Please enter a name"; return@setOnClickListener }
                if (customInput.visibility == android.view.View.VISIBLE) {
                    val custom = customInput.text.toString().trim()
                    if (custom.isNotEmpty()) selectedCategory = custom
                }
                if (selectedCategory.isEmpty()) selectedCategory = "Misc"
                val dbHelper = DatabaseHelper(this@OverlayService)
                dbHelper.saveMerchant(payeeKey, name, selectedCategory)
                dbHelper.saveTransaction(refNumber, payeeKey, name, selectedCategory, amount, type)
                animateOut(layout) { removeOverlay(); stopSelf() }
            }
        })
        layout.addView(btnRow)

        root = layout
        wm?.addView(layout, overlayParams(true))
        animateIn(layout)

        Handler(Looper.getMainLooper()).postDelayed({
            nameInput.requestFocus()
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(nameInput, InputMethodManager.SHOW_IMPLICIT)
        }, 400)
    }

    // ── Animations ────────────────────────────────────────────────

    private fun animateIn(view: android.view.View) {
        val alpha = ObjectAnimator.ofFloat(view, "alpha", 0f, 1f).apply { duration = 280 }
        val slide = ObjectAnimator.ofFloat(view, "translationY", dp(40).toFloat(), 0f).apply {
            duration = 320
            interpolator = android.view.animation.DecelerateInterpolator(2f)
        }
        AnimatorSet().apply { playTogether(alpha, slide); start() }
    }

    private fun animateOut(view: android.view.View, onEnd: () -> Unit) {
        val alpha = ObjectAnimator.ofFloat(view, "alpha", 1f, 0f).apply { duration = 200 }
        val slide = ObjectAnimator.ofFloat(view, "translationY", 0f, dp(30).toFloat()).apply { duration = 200 }
        AnimatorSet().apply {
            playTogether(alpha, slide)
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) { onEnd() }
            })
            start()
        }
    }

    // ── Helpers ───────────────────────────────────────────────────

    private fun overlayParams(focusable: Boolean) = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        if (focusable)
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
        else
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.BOTTOM; y = dp(16) }

    private fun card(hex: String, radius: Float) = GradientDrawable().apply {
        setColor(Color.parseColor(hex))
        cornerRadius = radius * resources.displayMetrics.density
    }

    private fun label(text: String) = TextView(this).apply {
        this.text = text; textSize = 12f
        setTextColor(Color.parseColor("#636366")); letterSpacing = 0.05f
    }

    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()

    private fun fmt(amount: Double) =
        if (amount == amount.toLong().toDouble()) amount.toLong().toString()
        else String.format("%.2f", amount)

    private fun removeOverlay() {
        root?.let { try { wm?.removeView(it) } catch (_: Exception) {}; root = null }
    }

    override fun onDestroy() { removeOverlay(); super.onDestroy() }
}
