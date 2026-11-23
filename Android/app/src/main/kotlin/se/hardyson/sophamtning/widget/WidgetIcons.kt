package se.hardyson.sophamtning.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorNode
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.core.graphics.createBitmap
import java.util.concurrent.ConcurrentHashMap

/**
 * Ikonerna i widgeten. Widgeten ritas som `RemoteViews` och kan inte rita appens `ImageVector`, så samma ikon ritas här
 * vit i en bild, som widgeten sedan färgar efter ljust och mörkt läge. Ikonerna finns alltså bara på ett ställe.
 */
internal object WidgetIcons {
    /** Bildens sida i pixlar. Skarp nog för 40 dp på de tätaste skärmarna. */
    private const val SIZE = 144

    private val cache = ConcurrentHashMap<String, Bitmap>()

    fun bitmap(vector: ImageVector): Bitmap = cache.getOrPut(vector.name) { render(vector) }

    private fun render(vector: ImageVector): Bitmap {
        val bitmap = createBitmap(SIZE, SIZE)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
        val scale = Matrix().apply { setScale(SIZE / vector.viewportWidth, SIZE / vector.viewportHeight) }
        fun draw(node: VectorNode) {
            when (node) {
                is VectorGroup -> node.forEach(::draw)
                is VectorPath -> {
                    val path = PathParser().addPathNodes(node.pathData).toPath().asAndroidPath()
                    path.fillType = if (node.pathFillType == PathFillType.EvenOdd) android.graphics.Path.FillType.EVEN_ODD else android.graphics.Path.FillType.WINDING
                    path.transform(scale)
                    canvas.drawPath(path, paint)
                }
            }
        }
        draw(vector.root)
        return bitmap
    }
}
