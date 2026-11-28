package com.ureader.prototype.speech

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipInputStream

/** Derived private data only; the trusted archive hash selects the directory. */
internal object KokoroFrontendData {
    private const val MAX_ARCHIVE = 32L * 1024 * 1024
    private const val MAX_EXPANDED = 64L * 1024 * 1024
    private const val MAX_FILES = 2048
    private val required = setOf("espeak-ng-data/phontab", "espeak-ng-data/phondata",
        "espeak-ng-data/phonindex", "espeak-ng-data/fr_dict", "espeak-ng-data/lang/roa/fr")

    fun prepare(archive: File, parent: File, expectedSha256: String): File {
        require(Regex("[a-f0-9]{64}").matches(expectedSha256))
        require(parent.isDirectory && parent.canonicalFile == parent.absoluteFile)
        require(archive.isFile && archive.canonicalFile == archive.absoluteFile && archive.length() in 1..MAX_ARCHIVE)
        require(sha(archive) == expectedSha256) { "Frontend archive integrity" }
        val ready = File(parent, "kokoro-frontend-$expectedSha256")
        require(ready.canonicalFile == ready.absoluteFile)
        if (ready.exists()) {
            require(ready.isDirectory)
            verify(archive, ready)
            return ready
        }
        val pending = File(parent, "kokoro-frontend-${UUID.randomUUID()}.part")
        check(pending.mkdir())
        try {
            entries(archive) { name, stream ->
                val target = File(pending, name)
                require(target.canonicalFile == target.absoluteFile && target.toPath().startsWith(pending.toPath()))
                check(target.parentFile.isDirectory || target.parentFile.mkdirs())
                check(target.createNewFile())
                target.outputStream().use { output ->
                    val buffer = ByteArray(65536)
                    while (true) { val size = stream.read(buffer); if (size < 0) break; output.write(buffer, 0, size) }
                    output.fd.sync()
                }
            }
            check(!ready.exists() && pending.renameTo(ready))
            return ready
        } finally {
            // Only this invocation's newly created staging tree is removable.
            if (pending.exists()) {
                removeOwnedTree(pending, parent)
            }
        }
    }

    fun release(root: File, parent: File, digest: String) {
        require(Regex("[a-f0-9]{64}").matches(digest))
        require(root == File(parent, "kokoro-frontend-$digest"))
        if (root.exists()) removeOwnedTree(root, parent)
    }

    private fun removeOwnedTree(root: File, parent: File) {
        require(root.canonicalFile == root.absoluteFile && root.parentFile == parent && parent.canonicalFile == parent.absoluteFile)
        // Files.walk does not follow links. Never recurse into an unexpected link.
        Files.walk(root.toPath()).use { paths ->
            paths.sorted(Comparator.reverseOrder()).forEach { path ->
                require(!Files.isSymbolicLink(path))
                Files.delete(path)
            }
        }
    }

    private fun verify(archive: File, ready: File) {
        val expected = HashSet<String>()
        entries(archive) { name, input ->
            expected.add(name)
            val target = File(ready, name)
            require(target.canonicalFile == target.absoluteFile && target.isFile)
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(65536)
            var length = 0L
            while (true) { val size = input.read(buffer); if (size < 0) break; digest.update(buffer, 0, size); length += size }
            require(target.length() == length && sha(target) == hex(digest.digest())) { "Changed frontend data" }
        }
        for (file in ready.walkTopDown()) {
            require(!Files.isSymbolicLink(file.toPath()))
            if (file.isFile()) require(file.relativeTo(ready).invariantSeparatorsPath in expected)
        }
    }

    /** Every consumer reads through the same global expanded-byte limit. */
    private fun entries(archive: File, consume: (String, java.io.InputStream) -> Unit) {
        val names = HashSet<String>()
        var expanded = 0L
        ZipInputStream(archive.inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = entry.name
                require(!entry.isDirectory && name.startsWith("espeak-ng-data/"))
                require(Regex("[-A-Za-z0-9_+.!()/ ]+").matches(name))
                require(name.split('/').all { it.isNotEmpty() && it != "." && it != ".." })
                require(names.add(name) && names.size <= MAX_FILES) { "Duplicate or excessive frontend files" }
                val bounded = object : java.io.InputStream() {
                    override fun read(): Int {
                        val value = zip.read()
                        if (value >= 0) { expanded++; require(expanded <= MAX_EXPANDED) }
                        return value
                    }
                    override fun read(buffer: ByteArray, offset: Int, count: Int): Int {
                        val size = zip.read(buffer, offset, count)
                        if (size > 0) { expanded += size; require(expanded <= MAX_EXPANDED) }
                        return size
                    }
                }
                consume(name, bounded)
                // Drain through the bound even if a consumer did not read the entry fully.
                val buffer = ByteArray(65536)
                while (bounded.read(buffer) >= 0) { }
                zip.closeEntry()
            }
        }
        require(names.containsAll(required)) { "French frontend data missing" }
    }

    private fun sha(file: File): String = file.inputStream().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(65536)
        while (true) { val size = input.read(buffer); if (size < 0) break; digest.update(buffer, 0, size) }
        hex(digest.digest())
    }
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
}
