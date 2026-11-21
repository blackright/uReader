package com.ureader.prototype.epub

import android.net.Uri
import java.net.URI

/** Destination only: no document text, credentials or implicit activation. */
internal object BookExternalLink {
 fun parse(url:String,userConfirmed:Boolean):Uri {
  if(!userConfirmed)throw EpubZipFailure("invalidRequest")
  if(url.isEmpty()||url.length>16384||url.any{it.code<=32||it.code==127||it=='\\'}||Regex("%(?:0[0-9a-f]|1[0-9a-f]|7f|5c)",RegexOption.IGNORE_CASE).containsMatchIn(url))throw EpubZipFailure("unsafeLink")
  val value=try{URI(url)}catch(_:Exception){throw EpubZipFailure("unsafeLink")}
  if(!value.scheme.equals("https",true)||value.host.isNullOrEmpty()||value.rawUserInfo!=null||value.port>65535)throw EpubZipFailure("unsafeLink")
  return Uri.parse(url)
 }
}
