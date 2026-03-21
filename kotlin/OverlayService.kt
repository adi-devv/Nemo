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
import android.graphics.drawable.LayerDrawable
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.*

class OverlayService : Service() {

    private var wm: WindowManager? = null
    private var root: View? = null

    // Pending state for outside-tap dismiss
    private var pendingAmount   = 0.0
    private var pendingType     = "debit"
    private var pendingPayeeKey = ""
    private var pendingHint     = ""
    private var pendingRef      = ""

    companion object {
        const val ACTION_TXN_SAVED = "com.hisaab.app.TXN_SAVED"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val amount       = intent?.getDoubleExtra("amount", 0.0) ?: 0.0
        val type         = intent?.getStringExtra("type") ?: "debit"
        val payeeKey     = intent?.getStringExtra("payee_key") ?: ""
        val payeeHint    = intent?.getStringExtra("payee_hint") ?: ""
        val refNumber    = intent?.getStringExtra("ref_number") ?: ""
        val mode         = intent?.getStringExtra("mode") ?: "unknown"
        val merchantName = intent?.getStringExtra("merchant_name") ?: ""
        val category     = intent?.getStringExtra("category") ?: ""
        val isRefund     = intent?.getBooleanExtra("is_refund", false) ?: false

        removeOverlay()

        if (mode == "known") {
            // Save immediately, skip the card, go straight to success popup
            DatabaseHelper(this).saveTransaction(refNumber, payeeKey, merchantName, category, amount, type)
            broadcastSaved()
            showSuccessPopup(amount, type, merchantName, category)
        } else {
            // Store for outside-tap fallback
            pendingAmount   = amount
            pendingType     = type
            pendingPayeeKey = payeeKey
            pendingHint     = payeeHint
            pendingRef      = refNumber
            showUnknownOverlay(amount, type, payeeKey, payeeHint, refNumber, isRefund)
        }

        return START_NOT_STICKY
    }

    // ═══════════════════════════════════════════════════════════════
    // UNKNOWN MERCHANT — name + category form (also handles refunds)
    // ═══════════════════════════════════════════════════════════════

    private fun showUnknownOverlay(
        amount: Double, type: String,
        payeeKey: String, payeeHint: String,
        refNumber: String, isRefund: Boolean
    ) {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val isDebit  = type == "debit"
        val amtColor = if (isDebit) Color.parseColor("#FF453A") else Color.parseColor("#30D158")
        val prefix   = if (isDebit) "−₹" else "+₹"

        val db          = DatabaseHelper(this)
        val topCats     = db.getTopCategories()
        // getTopCategories() already returns: frequency-sorted + all defaults + user cats + Misc last
        // Just cap visible chips at 6 (rest accessible via + Other / scrolling)
        val orderedCats = topCats

        val scroll = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            alpha        = 0f
            translationY = dp(40).toFloat()
        }

        // ── Intercept outside touches to save as pending ──────────
        scroll.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_OUTSIDE) {
                savePending()
                animateOut(scroll) { removeOverlay(); stopSelf() }
                true
            } else false
        }

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background  = blurCard()
            setPadding(dp(22), dp(22), dp(22), dp(26))
        }
        scroll.addView(layout)

        // ── Refund badge ─────────────────────────────────────────
        if (isRefund) {
            layout.addView(TextView(this).apply {
                text          = "↩  Looks like a refund"
                textSize      = 11.5f
                letterSpacing = 0.02f
                setTextColor(Color.parseColor("#30D158"))
                background    = pillBg(Color.parseColor("#0D2B1A"), Color.parseColor("#1C4D2E"))
                setPadding(dp(12), dp(6), dp(12), dp(6))
                layoutParams  = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { setMargins(0, 0, 0, dp(14)) }
            })
        }

        // ── Amount ───────────────────────────────────────────────
        layout.addView(TextView(this).apply {
            text     = "$prefix${fmt(amount)}"
            textSize = 32f
            setTextColor(amtColor)
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            gravity  = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, 0, 0, dp(20)) }
        })

        // ── Name field ───────────────────────────────────────────
        layout.addView(fieldLabel("Name"))
        val nameInput = EditText(this).apply {
            setText(payeeHint)
            setSelectAllOnFocus(true)
            hint              = "e.g. Swiggy"
            setHintTextColor(Color.parseColor("#3A3A3C"))
            setTextColor(Color.WHITE)
            textSize          = 14f
            background        = inputBg()
            setPadding(dp(14), dp(12), dp(14), dp(12))
            setSingleLine(true)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, dp(6), 0, dp(18)) }
        }
        layout.addView(nameInput)

        // ── Category chips ───────────────────────────────────────
        layout.addView(fieldLabel("Category"))

        val chipScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, dp(6), 0, 0) }
        }
        val chipRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        chipScroll.addView(chipRow)
        layout.addView(chipScroll)

        val customInput = EditText(this).apply {
            hint              = "Type custom category…"
            setHintTextColor(Color.parseColor("#3A3A3C"))
            setTextColor(Color.WHITE)
            textSize          = 14f
            background        = inputBg()
            setPadding(dp(14), dp(12), dp(14), dp(12))
            setSingleLine(true)
            visibility        = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, dp(10), 0, 0) }
        }
        layout.addView(customInput)

        var selectedCategory = orderedCats.firstOrNull() ?: "Misc"
        val chips = mutableListOf<TextView>()

        fun selectChip(index: Int) {
            chips.forEachIndexed { i, chip ->
                chip.background = chipBg(i == index)
                chip.setTextColor(if (i == index) Color.BLACK else Color.parseColor("#8E8E93"))
            }
        }

        orderedCats.forEachIndexed { idx, catName ->
            val chip = TextView(this).apply {
                text      = catName
                textSize  = 12.5f
                setPadding(dp(14), dp(8), dp(14), dp(8))
                setTextColor(if (idx == 0) Color.BLACK else Color.parseColor("#8E8E93"))
                background = chipBg(idx == 0)
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { setMargins(0, 0, dp(8), 0) }
                setOnClickListener {
                    selectedCategory       = catName
                    customInput.visibility = View.GONE
                    selectChip(idx)
                }
            }
            chips.add(chip)
            chipRow.addView(chip)
        }

        chipRow.addView(TextView(this).apply {
            text      = "+ Other"
            textSize  = 12.5f
            setPadding(dp(14), dp(8), dp(14), dp(8))
            setTextColor(Color.parseColor("#636366"))
            background = chipBg(false)
            setOnClickListener {
                customInput.visibility = View.VISIBLE
                customInput.requestFocus()
                showKeyboard(customInput)
                chips.forEach { c ->
                    c.background = chipBg(false)
                    c.setTextColor(Color.parseColor("#8E8E93"))
                }
                selectedCategory = ""
            }
        })

        // ── Divider ──────────────────────────────────────────────
        layout.addView(View(this).apply {
            setBackgroundColor(Color.parseColor("#1F1F1F"))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(1)
            ).apply { setMargins(0, dp(22), 0, 0) }
        })

        // ── Action row ───────────────────────────────────────────
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER_VERTICAL
            setPadding(0, dp(16), 0, 0)
        }

        // Skip → save as pending
        btnRow.addView(TextView(this).apply {
            text     = "Skip"
            textSize = 14f
            setTextColor(Color.parseColor("#48484A"))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            setOnClickListener {
                savePending()
                animateOut(scroll) { removeOverlay(); stopSelf() }
            }
        })

        val saveBtn = TextView(this).apply {
            text      = "Save"
            textSize  = 14f
            typeface  = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(Color.BLACK)
            background = roundRect("#FFFFFF", 22f)
            setPadding(dp(26), dp(12), dp(26), dp(12))
        }
        btnRow.addView(saveBtn)
        layout.addView(btnRow)

        saveBtn.setOnClickListener {
            val name = nameInput.text.toString().trim()
            if (name.isEmpty()) { nameInput.hint = "Please enter a name"; return@setOnClickListener }
            if (customInput.visibility == View.VISIBLE) {
                val custom = customInput.text.toString().trim()
                if (custom.isNotEmpty()) selectedCategory = custom
            }
            if (selectedCategory.isEmpty()) selectedCategory = "Misc"

            val dbHelper = DatabaseHelper(this@OverlayService)
            dbHelper.saveMerchant(payeeKey, name, selectedCategory)
            dbHelper.saveTransaction(refNumber, payeeKey, name, selectedCategory, amount, type,
                status = "confirmed")
            broadcastSaved()

            hideKeyboard(nameInput)
            animateOut(scroll) {
                removeOverlay()
                showSuccessPopup(amount, type, name, selectedCategory)
            }
        }

        root = scroll
        wm?.addView(scroll, overlayParams(focusable = true))
        animateIn(scroll)

        Handler(Looper.getMainLooper()).postDelayed({
            nameInput.requestFocus()
            showKeyboard(nameInput)
        }, 380)
    }

    // Save current transaction as pending (used by Skip and outside-tap)
    private fun savePending() {
        if (pendingRef.isBlank()) return
        DatabaseHelper(this).saveTransaction(
            pendingRef, pendingPayeeKey,
            pendingHint.ifBlank { pendingPayeeKey }, "Uncategorised",
            pendingAmount, pendingType, status = "pending"
        )
        broadcastSaved()
        pendingRef = "" // prevent double-save
    }

    // Broadcast so Flutter can reload the list
    private fun broadcastSaved() {
        sendBroadcast(Intent(ACTION_TXN_SAVED).setPackage(packageName))
    }

    // ═══════════════════════════════════════════════════════════════
    // SUCCESS POPUP — dot animates to tick after 1.5s, then dismisses
    // ═══════════════════════════════════════════════════════════════

    private fun showSuccessPopup(
        amount: Double, type: String,
        name: String, category: String
    ) {
        val wm2      = getSystemService(WINDOW_SERVICE) as WindowManager
        val isDebit  = type == "debit"
        val amtColor = if (isDebit) Color.parseColor("#FF453A") else Color.parseColor("#30D158")
        val prefix   = if (isDebit) "−₹" else "+₹"

        val pill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER_VERTICAL
            background  = blurCard()
            setPadding(dp(18), dp(14), dp(20), dp(14))
            alpha        = 0f
            translationY = dp(28).toFloat()
        }

        // Dot indicator — starts as colored dot, becomes ✓
        val dotView = TextView(this).apply {
            text     = ""  // empty — dot drawn as background
            layoutParams = LinearLayout.LayoutParams(dp(8), dp(8)).apply {
                setMargins(0, 0, dp(12), 0)
            }
            background = circle(amtColor)
        }
        pill.addView(dotView)

        // Text column
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        col.addView(TextView(this).apply {
            text     = name
            textSize = 14f
            setTextColor(Color.WHITE)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        })
        col.addView(TextView(this).apply {
            text     = category
            textSize = 11f
            setTextColor(Color.parseColor("#636366"))
            setPadding(0, dp(2), 0, 0)
        })
        pill.addView(col)

        // Amount
        pill.addView(TextView(this).apply {
            text     = "$prefix${fmt(amount)}"
            textSize = 15f
            setTextColor(amtColor)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setPadding(dp(12), 0, 0, 0)
        })

        wm2.addView(pill, overlayParams(focusable = false))
        animateIn(pill)

        // After 1.5s — morph dot into ✓
        Handler(Looper.getMainLooper()).postDelayed({
            // Shrink dot out
            val shrink = ObjectAnimator.ofFloat(dotView, "scaleX", 1f, 0f).apply { duration = 150 }
            val shrinkY = ObjectAnimator.ofFloat(dotView, "scaleY", 1f, 0f).apply { duration = 150 }
            AnimatorSet().apply {
                playTogether(shrink, shrinkY)
                addListener(object : android.animation.AnimatorListenerAdapter() {
                    override fun onAnimationEnd(a: android.animation.Animator) {
                        // Swap to tick
                        dotView.text       = "✓"
                        dotView.textSize   = 11f
                        dotView.setTextColor(Color.parseColor("#30D158"))
                        dotView.background = null
                        dotView.layoutParams = (dotView.layoutParams as LinearLayout.LayoutParams).also {
                            it.width  = ViewGroup.LayoutParams.WRAP_CONTENT
                            it.height = ViewGroup.LayoutParams.WRAP_CONTENT
                        }
                        // Grow tick in
                        dotView.scaleX = 0f
                        dotView.scaleY = 0f
                        val growX = ObjectAnimator.ofFloat(dotView, "scaleX", 0f, 1f).apply { duration = 180 }
                        val growY = ObjectAnimator.ofFloat(dotView, "scaleY", 0f, 1f).apply { duration = 180 }
                        AnimatorSet().apply {
                            playTogether(growX, growY)
                            interpolator = android.view.animation.OvershootInterpolator(2f)
                            start()
                        }
                    }
                })
                start()
            }
        }, 1500)

        // After 1.5s dot anim + 1s hold = 2.5s total, then dismiss
        Handler(Looper.getMainLooper()).postDelayed({
            animateOut(pill) {
                pill.visibility = View.INVISIBLE
                try { wm2.removeView(pill) } catch (_: Exception) {}
                stopSelf()
            }
        }, 2800)
    }

    // ═══════════════════════════════════════════════════════════════
    // ANIMATIONS
    // ═══════════════════════════════════════════════════════════════

    private fun animateIn(view: View) {
        val alpha = ObjectAnimator.ofFloat(view, "alpha", 0f, 1f).apply { duration = 260 }
        val slide = ObjectAnimator.ofFloat(view, "translationY",
            view.translationY, 0f).apply {
            duration     = 320
            interpolator = android.view.animation.DecelerateInterpolator(2.2f)
        }
        AnimatorSet().apply { playTogether(alpha, slide); start() }
    }

    private fun animateOut(view: View, onEnd: () -> Unit) {
        val alpha = ObjectAnimator.ofFloat(view, "alpha", 1f, 0f).apply { duration = 190 }
        val slide = ObjectAnimator.ofFloat(view, "translationY", 0f,
            dp(24).toFloat()).apply { duration = 190 }
        AnimatorSet().apply {
            playTogether(alpha, slide)
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) { onEnd() }
            })
            start()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // DRAWABLES / HELPERS
    // ═══════════════════════════════════════════════════════════════

    private fun blurCard(): android.graphics.drawable.Drawable {
        val bg = GradientDrawable().apply {
            setColor(Color.parseColor("#0F0F0F"))
            cornerRadius = dp(20).toFloat()
        }
        val stroke = GradientDrawable().apply {
            setColor(Color.TRANSPARENT)
            cornerRadius = dp(20).toFloat()
            setStroke(dp(1), Color.parseColor("#232323"))
        }
        return LayerDrawable(arrayOf(bg, stroke))
    }

    private fun inputBg() = GradientDrawable().apply {
        setColor(Color.parseColor("#161616"))
        cornerRadius = dp(10).toFloat()
        setStroke(dp(1), Color.parseColor("#2A2A2A"))
    }

    private fun chipBg(selected: Boolean) = GradientDrawable().apply {
        setColor(if (selected) Color.WHITE else Color.parseColor("#1A1A1A"))
        cornerRadius = dp(20).toFloat()
        if (!selected) setStroke(dp(1), Color.parseColor("#2C2C2E"))
    }

    private fun roundRect(hex: String, radius: Float) = GradientDrawable().apply {
        setColor(Color.parseColor(hex))
        cornerRadius = radius * resources.displayMetrics.density
    }

    private fun circle(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
    }

    private fun pillBg(fillColor: Int, borderColor: Int): android.graphics.drawable.Drawable {
        val bg = GradientDrawable().apply {
            setColor(fillColor)
            cornerRadius = dp(20).toFloat()
        }
        val border = GradientDrawable().apply {
            setColor(Color.TRANSPARENT)
            cornerRadius = dp(20).toFloat()
            setStroke(dp(1), borderColor)
        }
        return LayerDrawable(arrayOf(bg, border))
    }

    private fun fieldLabel(text: String) = TextView(this).apply {
        this.text     = text
        textSize      = 11f
        letterSpacing = 0.04f
        setTextColor(Color.parseColor("#505055"))
    }

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
    ).apply {
        gravity = Gravity.BOTTOM
        y = dp(20)
    }

    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()

    private fun fmt(amount: Double) =
        if (amount == amount.toLong().toDouble()) amount.toLong().toString()
        else String.format("%.2f", amount)

    private fun showKeyboard(v: View) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showSoftInput(v, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun hideKeyboard(v: View) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(v.windowToken, 0)
    }

    private fun removeOverlay() {
        root?.let {
            it.visibility = View.INVISIBLE
            try { wm?.removeView(it) } catch (_: Exception) {}
            root = null
        }
    }

    override fun onDestroy() { removeOverlay(); super.onDestroy() }
}