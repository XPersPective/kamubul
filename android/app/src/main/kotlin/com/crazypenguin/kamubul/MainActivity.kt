package com.crazypenguin.kamubul

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Deneme süresi: ANDROID_ID uygulama imzasına özgüdür ve yeniden kurulumda değişmez.
        // Ham kimlik Dart'a/sunucuya verilmez; yalnız tuzlu SHA-256 karması döner.
        MethodChannel(messenger, "kamubul/device").setMethodCallHandler { call, result ->
            if (call.method != "trialHash") { result.notImplemented(); return@setMethodCallHandler }
            val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            if (id.isNullOrBlank()) { result.success(null); return@setMethodCallHandler }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest("kamubul-trial-v1:$id".toByteArray(Charsets.UTF_8))
            result.success(digest.joinToString("") { "%02x".format(it) })
        }
        MethodChannel(messenger, "kamubul/secure_push", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            try {
                val file = AtomicFile(File(noBackupFilesDir, "kamubul_push.v1"))
                val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                val alias = "kamubul.push.v1"
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                when (call.method) {
                    "read" -> {
                        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) {
                            result.success(null)
                        } else {
                            require(file.baseFile.length() <= 131100)
                            require(File(file.baseFile.path + ".bak").length() <= 131100)
                            val bytes = file.readFully()
                            require(bytes.size in 28..131100)
                            val key = keys.getKey(alias, null) as? SecretKey
                                ?: error("missing_key")
                            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                            cipher.updateAAD(alias.toByteArray(Charsets.UTF_8))
                            result.success(cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8))
                        }
                    }
                    "write" -> {
                        val value = (call.arguments as? String)?.toByteArray(Charsets.UTF_8)
                            ?: error("invalid_value")
                        require(value.size <= 131072)
                        val key = (keys.getKey(alias, null) as? SecretKey) ?: KeyGenerator
                            .getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                                    .setKeySize(256).build())
                            }.generateKey()
                        cipher.init(Cipher.ENCRYPT_MODE, key)
                        cipher.updateAAD(alias.toByteArray(Charsets.UTF_8))
                        require(cipher.iv.size == 12)
                        val bytes = cipher.iv + cipher.doFinal(value)
                        val output = file.startWrite()
                        try { output.write(bytes); file.finishWrite(output) }
                        catch (error: Exception) { file.failWrite(output); throw error }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // Do not disclose key/ciphertext/state in platform errors.
                result.error("secure_storage_unavailable", "Bildirim anahtarı güvenli saklanamadı.", null)
            }
        }
    }
}
