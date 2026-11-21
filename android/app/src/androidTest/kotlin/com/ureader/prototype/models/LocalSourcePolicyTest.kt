package com.ureader.prototype.models

import android.net.Uri
import org.junit.Assert.*
import org.junit.Test

class LocalSourcePolicyTest {
    @Test fun onlyLocalDocumentTreesAreAccepted() {
        assertTrue(LocalSourcePolicy.accepts(Uri.parse("content://com.android.externalstorage.documents/tree/primary%3ADownload%2FuReader")))
        assertTrue(LocalSourcePolicy.accepts(Uri.parse("content://com.android.providers.downloads.documents/tree/downloads")))
        assertFalse(LocalSourcePolicy.accepts(Uri.parse("content://cloud.example/tree/resources")))
        assertFalse(LocalSourcePolicy.accepts(Uri.parse("file:///sdcard/Download/uReader")))
        assertFalse(LocalSourcePolicy.accepts(Uri.parse("https://example.invalid/models")))
        assertFalse(LocalSourcePolicy.accepts(Uri.parse("content://com.android.externalstorage.documents/document/primary%3Asecret")))
        assertFalse(LocalSourcePolicy.accepts(null))
    }
}
