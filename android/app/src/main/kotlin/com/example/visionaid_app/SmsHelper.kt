package com.example.visionaid_app

import android.app.Activity
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

class SmsHelper(private val activity: Activity) {
    
    companion object {
        const val SMS_PERMISSION_CODE = 101
    }
    
    fun sendSms(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            // Check permission
            if (ContextCompat.checkSelfPermission(activity, android.Manifest.permission.SEND_SMS) 
                != PackageManager.PERMISSION_GRANTED) {
                result.error("PERMISSION_DENIED", "SMS permission not granted", null)
                return
            }
            
            val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                activity.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            
            // Split message if too long
            val parts = smsManager.divideMessage(message)
            
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            }
            
            result.success(true)
        } catch (e: Exception) {
            result.error("SMS_FAILED", e.message, null)
        }
    }
    
    fun requestPermission() {
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(android.Manifest.permission.SEND_SMS),
            SMS_PERMISSION_CODE
        )
    }
    
    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(activity, android.Manifest.permission.SEND_SMS) == 
            PackageManager.PERMISSION_GRANTED
    }
}
