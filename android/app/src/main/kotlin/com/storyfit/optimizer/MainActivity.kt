package com.storyfit.optimizer

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "storyfit/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveVideoToMovies" -> {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name") ?: "storyfit_export.mp4"

                    if (path.isNullOrBlank()) {
                        result.error("missing_path", "No export path was provided.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val saved = saveVideoToMovies(path, name)
                        result.success(saved)
                    } catch (error: Exception) {
                        result.error("save_failed", error.message ?: "Could not save video.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveVideoToMovies(sourcePath: String, fileName: String): String {
        val source = File(sourcePath)
        require(source.exists()) { "Exported video was not found." }

        val safeName = if (fileName.endsWith(".mp4", ignoreCase = true)) fileName else "$fileName.mp4"

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(source, safeName)
        } else {
            saveWithLegacyStorage(source, safeName)
        }
    }

    private fun saveWithMediaStore(source: File, fileName: String): String {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(
                MediaStore.Video.Media.RELATIVE_PATH,
                Environment.DIRECTORY_MOVIES + File.separator + "StoryFit"
            )
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }

        val uri: Uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: error("Could not create local video file.")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            } ?: error("Could not open local storage output.")

            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun saveWithLegacyStorage(source: File, fileName: String): String {
        val movies = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        val directory = File(movies, "StoryFit")
        if (!directory.exists()) {
            directory.mkdirs()
        }

        val destination = File(directory, fileName)
        FileInputStream(source).use { input ->
            FileOutputStream(destination).use { output -> input.copyTo(output) }
        }

        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(destination.absolutePath),
            arrayOf("video/mp4"),
            null
        )

        return destination.absolutePath
    }
}
