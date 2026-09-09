package dev.flutterquill.quill_native_bridge.util

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.IOException

/**
 * Similar to [ImageDecoder] but compatible with older Android versions by fallback to use
 * older APIs.
 * */
object ImageDecoderCompat {
    // Clipboard images are rendered inside the editor. Bounding their longest
    // edge keeps a single image from allocating tens or hundreds of MB while
    // retaining ample resolution for high-density phone and tablet displays.
    private const val MAX_DECODE_DIMENSION = 2048

    private fun calculateInSampleSize(
        width: Int,
        height: Int,
        maxDimension: Int = MAX_DECODE_DIMENSION,
    ): Int {
        if (width <= 0 || height <= 0) return 1
        var sampleSize = 1
        while (width / sampleSize > maxDimension || height / sampleSize > maxDimension) {
            sampleSize *= 2
        }
        return sampleSize
    }

    private fun decodeSampledBytes(imageBytes: ByteArray): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IOException("Image bytes do not contain a supported image.")
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight)
        }
        return BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            ?: throw IOException("Image could not be decoded using BitmapFactory.")
    }

    private fun decodeSampledUri(
        contentResolver: ContentResolver,
        imageUri: Uri,
    ): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(imageUri)?.use { inputStream ->
            BitmapFactory.decodeStream(inputStream, null, bounds)
        } ?: throw IOException("Input stream is null, the provider might have recently crashed.")
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IOException("URI does not contain a supported image.")
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight)
        }
        return contentResolver.openInputStream(imageUri)?.use { inputStream ->
            BitmapFactory.decodeStream(inputStream, null, options)
        } ?: throw IOException("The image could not be decoded using BitmapFactory.")
    }

    /**
     * Uses [ImageDecoder.decodeBitmap] on Android API 31 and newer, fallback to [BitmapFactory.decodeByteArray]
     * on older versions.
     *
     * @throws IOException if unsupported, or or cannot be decoded for any reason.
     * @see decodeBitmapFromUri
     * */
    @Throws(IOException::class)
    fun decodeBitmapFromBytes(imageBytes: ByteArray): Bitmap =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31 and above (use a newer API)
            val source = ImageDecoder.createSource(imageBytes)
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.setTargetSampleSize(
                    calculateInSampleSize(info.size.width, info.size.height),
                )
            }
        } else {
            // Backward compatibility with older versions
            decodeSampledBytes(imageBytes)
        }

    /**
     * Uses [ImageDecoder.decodeBitmap] on Android API 28 and newer, fallback to [BitmapFactory.decodeStream]
     * on older versions.
     *
     * @throws IOException if unsupported, or or cannot be decoded for any reason.
     * @see decodeBitmapFromBytes
     * */
    @Throws(IOException::class)
    fun decodeBitmapFromUri(
        contentResolver: ContentResolver,
        imageUri: Uri,
    ): Bitmap =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // API 28 and above (use a newer API)
            val source = ImageDecoder.createSource(contentResolver, imageUri)
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.setTargetSampleSize(
                    calculateInSampleSize(info.size.width, info.size.height),
                )
            }
        } else {
            // Backward compatibility with older versions
            decodeSampledUri(contentResolver, imageUri)
        }

    fun isValidImage(imageBytes: ByteArray): Boolean {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, bounds)
        return bounds.outWidth > 0 && bounds.outHeight > 0
    }
}
