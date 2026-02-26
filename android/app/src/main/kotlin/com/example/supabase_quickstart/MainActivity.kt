package com.example.supabase_quickstart

import android.app.PendingIntent
import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.MifareUltralight
import android.nfc.tech.Ndef
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.supabase_quickstart/nfc"
    private var nfcAdapter: NfcAdapter? = null
    private var currentTag: Tag? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        // Check if we have a tag from the launch intent
        val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
        if (tag != null) {
            currentTag = tag
        }
    }

    override fun onResume() {
        super.onResume()
        // Enable foreground dispatch to receive NFC intents
        nfcAdapter?.enableForegroundDispatch(
            this,
            PendingIntent.getActivity(
                this, 0, Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_MUTABLE
            ),
            null,
            null
        )
        // Also check if we have a tag in the current intent
        val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
        if (tag != null) {
            currentTag = tag
        }
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Store the tag from the intent
        val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
        if (tag != null) {
            currentTag = tag
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "readMifareUltralight" -> {
                    try {
                        val startPage = call.argument<Int>("startPage") ?: 4
                        val endPage = call.argument<Int>("endPage") ?: 15
                        
                        // Try to get the tag from stored currentTag or current intent
                        var tag: Tag? = currentTag
                        if (tag == null) {
                            val intent = this.intent
                            tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
                        }
                        
                        if (tag != null) {
                            val pages = readMifareUltralightMemory(tag, startPage, endPage)
                            if (pages != null && pages.isNotEmpty()) {
                                result.success(pages)
                            } else {
                                result.error("READ_ERROR", "Could not read MifareUltralight pages", null)
                            }
                        } else {
                            result.error("NO_TAG", "No NFC tag found. Please ensure tag is still in range.", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Unknown error", null)
                    }
                }
                "setTagIdentifier" -> {
                    // This method is called to store tag identifier, but we don't need it
                    // since we store the actual Tag object
                    result.success(null)
                }
                "setAndroidTag" -> {
                    // This method receives tag handle info, but we'll use the stored tag
                    result.success(null)
                }
                "readMifareUltralightByIdentifier" -> {
                    try {
                        val identifier = call.argument<List<Int>>("identifier")
                        val startPage = call.argument<Int>("startPage") ?: 4
                        val endPage = call.argument<Int>("endPage") ?: 15
                        
                        if (identifier != null && identifier.isNotEmpty()) {
                            // Try to find the tag by matching identifier
                            var tag: Tag? = currentTag
                            if (tag == null) {
                                val intent = this.intent
                                tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
                            }
                            
                            // Check if the tag's identifier matches
                            if (tag != null) {
                                val tagId = tag.id
                                val identifierBytes = identifier.map { it.toByte() }.toByteArray()
                                
                                // Compare identifiers (they might be in different byte orders)
                                val matches = tagId.contentEquals(identifierBytes) || 
                                             tagId.contentEquals(identifierBytes.reversedArray())
                                
                                if (matches || currentTag != null) {
                                    // Identifier matches or we have a stored tag, read memory
                                    val pages = readMifareUltralightMemory(tag, startPage, endPage)
                                    if (pages != null && pages.isNotEmpty()) {
                                        result.success(pages)
                                    } else {
                                        result.error("READ_ERROR", "Could not read MifareUltralight pages", null)
                                    }
                                } else {
                                    result.error("NO_MATCH", "Tag identifier does not match", null)
                                }
                            } else {
                                result.error("NO_TAG", "No NFC tag found. Please ensure tag is still in range.", null)
                            }
                        } else {
                            result.error("INVALID_IDENTIFIER", "Invalid identifier provided", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Unknown error", null)
                    }
                }
                "readNdefFromCurrentTag" -> {
                    try {
                        // Try to read NDEF directly from the current tag
                        var tag: Tag? = currentTag
                        if (tag == null) {
                            val intent = this.intent
                            tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
                        }
                        
                        if (tag != null) {
                            val ndefData = readNdefFromTag(tag)
                            if (ndefData != null && ndefData.isNotEmpty()) {
                                result.success(ndefData)
                            } else {
                                result.error("READ_ERROR", "Could not read NDEF from tag", null)
                            }
                        } else {
                            result.error("NO_TAG", "No NFC tag found. Please ensure tag is still in range.", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "Unknown error", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // Helper method to read NDEF data directly from tag
    private fun readNdefFromTag(tag: Tag): List<Int>? {
        var ndef: Ndef? = null
        return try {
            ndef = Ndef.get(tag)
            ndef?.connect()
            
            val ndefMessage = ndef?.ndefMessage
            if (ndefMessage != null) {
                val records = ndefMessage.records
                if (records.isNotEmpty()) {
                    // Get the first record's payload
                    val firstRecord = records[0]
                    val payload = firstRecord.payload
                    if (payload != null) {
                        payload.map { it.toInt() and 0xFF }
                    } else {
                        null
                    }
                } else {
                    null
                }
            } else {
                null
            }
        } catch (e: IOException) {
            null
        } catch (e: Exception) {
            null
        } finally {
            try {
                ndef?.close()
            } catch (e: IOException) {
                // Ignore
            }
        }
    }

    // Helper method to read MifareUltralight memory when we have the Tag
    private fun readMifareUltralightMemory(tag: Tag, startPage: Int, endPage: Int): List<Int>? {
        var mifare: MifareUltralight? = null
        return try {
            mifare = MifareUltralight.get(tag)
            mifare?.connect()
            
            val pages = mutableListOf<Int>()
            for (page in startPage..endPage) {
                val pageData = mifare?.readPages(page)
                if (pageData != null && pageData.size >= 4) {
                    // Add the 4 bytes from this page
                    for (i in 0 until 4) {
                        pages.add(pageData[i].toInt() and 0xFF)
                    }
                }
            }
            pages
        } catch (e: IOException) {
            null
        } catch (e: Exception) {
            null
        } finally {
            try {
                mifare?.close()
            } catch (e: IOException) {
                // Ignore
            }
        }
    }
}
