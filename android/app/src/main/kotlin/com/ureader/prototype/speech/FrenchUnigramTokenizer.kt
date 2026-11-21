package com.ureader.prototype.speech

import org.json.JSONObject

/** Limited to the audited French Unigram JSON; no ICU/NFKC or hidden text preprocessing.
 * Bundle integrity must be checked by the owner before construction. No file/network access.
 */
class FrenchUnigramTokenizer(json: String) {
    private class Node {
        val children = HashMap<Int, Node>()
        var id = -1
        var score = 0.0
    }
    private val root = Node()
    private val byteIds = IntArray(256)
    private val special = listOf("<unk>", "<s>", "</s>", "<pad>")
    private val unknownScore: Double

    init {
        require(json.length <= 300000) { "Tokenizer size limit" }
        val config = JSONObject(json)
        require(config.getString("version") == "1.0")
        for (key in listOf("truncation", "padding", "post_processor")) require(config.isNull(key))
        val normalizer = config.getJSONObject("normalizer")
        require(normalizer.getString("type") == "Sequence")
        val normalizers = normalizer.getJSONArray("normalizers")
        require(normalizers.length() == 1)
        require(normalizers.getJSONObject(0).getString("type") == "Prepend")
        require(normalizers.getJSONObject(0).getString("prepend") == "▁")
        val pre = config.getJSONObject("pre_tokenizer")
        require(pre.getString("type") == "Metaspace" && pre.getString("replacement") == "▁")
        require(pre.getString("prepend_scheme") == "always" && pre.getBoolean("split"))
        val added = config.getJSONArray("added_tokens")
        require(added.length() == special.size)
        for (i in special.indices) {
            val entry = added.getJSONObject(i)
            require(entry.getInt("id") == i && entry.getString("content") == special[i])
            require(entry.getBoolean("special") && !entry.getBoolean("normalized"))
            for (key in listOf("single_word", "lstrip", "rstrip")) require(!entry.getBoolean(key))
        }
        val model = config.getJSONObject("model")
        require(model.getString("type") == "Unigram" && model.getInt("unk_id") == 0)
        require(model.getBoolean("byte_fallback"))
        val vocab = model.getJSONArray("vocab")
        require(vocab.length() == 4000)
        var minimum = 0.0
        val pieces = HashSet<String>()
        for (id in 0 until vocab.length()) {
            val entry = vocab.getJSONArray(id)
            require(entry.length() == 2)
            val piece = entry.getString(0)
            val score = entry.getDouble(1)
            require(piece.isNotEmpty() && pieces.add(piece) && score.isFinite())
            minimum = minOf(minimum, score)
            if (id < 4) require(piece == special[id])
            if (id in 4..259) {
                require(piece == "<0x%02X>".format(id - 4))
                byteIds[id - 4] = id
            }
            var node = root
            for (codepoint in piece.codePoints().toArray()) {
                node = node.children.getOrPut(codepoint) { Node() }
            }
            node.id = id
            node.score = score
        }
        unknownScore = minimum - 10.0
    }

    data class Encoded(val ids: IntArray, val offsets: List<Pair<Int, Int>>)
    fun encode(text: String): IntArray = encodeDetailed(text).ids
    fun encodeDetailed(text: String): Encoded {
        require(text.length <= 4096) { "Tokenizer input limit" }
        // Control IDs must never be injected through corpus content.
        require(special.none { text.contains(it) }) { "Reserved tokenizer marker" }
        var index = 0
        while (index < text.length) {
            val char = text[index++]
            if (Character.isHighSurrogate(char)) {
                require(index < text.length && Character.isLowSurrogate(text[index++]))
            } else require(!Character.isLowSurrogate(char))
        }
        if (text.isEmpty()) return Encoded(IntArray(0), emptyList())
        val points = ("▁" + text.replace(' ', '▁')).codePoints().toArray()
        val result = ArrayList<Int>()
        val ranges = ArrayList<Pair<Int, Int>>()
        val utf16 = IntArray(points.size + 1)
        for (i in points.indices) utf16[i + 1] = utf16[i] + Character.charCount(points[i])
        var start = 0
        // Metaspace splitting prevents vocabulary pieces from spanning word boundaries.
        for (end in 1..points.size) {
            if (end == points.size || points[end] == 0x2581) {
                encodePiece(points, start, end, result, ranges, utf16)
                start = end
            }
        }
        return Encoded(result.toIntArray(), ranges.toList())
    }

    private fun encodePiece(points: IntArray, start: Int, end: Int, output: MutableList<Int>, ranges: MutableList<Pair<Int, Int>>, utf16: IntArray) {
        val length = end - start
        val scores = DoubleArray(length + 1) { Double.NEGATIVE_INFINITY }
        val previous = IntArray(length + 1) { -1 }
        val ids = IntArray(length + 1) { -1 }
        scores[0] = 0.0
        for (offset in 0 until length) {
            var node = root
            var singleKnown = false
            for (position in offset until length) {
                node = node.children[points[start + position]] ?: break
                if (node.id >= 0) {
                    if (position == offset) singleKnown = true
                    val score = scores[offset] + node.score
                    if (score > scores[position + 1]) {
                        scores[position + 1] = score
                        previous[position + 1] = offset
                        ids[position + 1] = node.id
                    }
                }
            }
            if (!singleKnown && scores[offset] + unknownScore > scores[offset + 1]) {
                scores[offset + 1] = scores[offset] + unknownScore
                previous[offset + 1] = offset
                ids[offset + 1] = 0
            }
        }
        val reverse = ArrayList<Pair<Int, Int>>()
        var cursor = length
        while (cursor > 0) {
            check(previous[cursor] >= 0)
            reverse.add(ids[cursor] to (start + previous[cursor]))
            cursor = previous[cursor]
        }
        val ordered = reverse.asReversed()
        for ((i, entry) in ordered.withIndex()) {
            val (id, position) = entry
            val stop = if (i + 1 < ordered.size) ordered[i + 1].second else end
            val range = maxOf(0, utf16[position] - 1) to maxOf(0, utf16[stop] - 1)
            if (id == 0) {
                val bytes = String(Character.toChars(points[position])).toByteArray(Charsets.UTF_8)
                for (byte in bytes) { output.add(byteIds[byte.toInt() and 255]); ranges.add(range) }
            } else { output.add(id); ranges.add(range) }
        }
    }
}
