package com.ureader.prototype.speech

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class KokoroInputsTest {
    @Test fun preservesTokensAndBoundaries() {
        assertArrayEquals(longArrayOf(0, 2, 3, 2, 0), KokoroInputs.ids("aba", mapOf("a" to 2, "b" to 3)))
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsUnknownPhoneme() {
        KokoroInputs.ids("ax", mapOf("a" to 2))
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsContextOverflow() {
        KokoroInputs.ids("a".repeat(511), mapOf("a" to 2))
    }
    @Test fun styleUsesOriginalLength() {
        assertEquals(512, KokoroInputs.styleOffset("abc"))
    }
    @Test fun countsUnicodeSymbolsRatherThanSurrogateHalves() {
        assertArrayEquals(longArrayOf(0, 4, 0), KokoroInputs.ids("\uD835\uDC00", mapOf("\uD835\uDC00" to 4)))
    }
}
