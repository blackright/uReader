package com.ureader.prototype.epub

import android.icu.lang.UCharacter
import android.icu.text.Normalizer2

internal object SearchKeyNormalizer {
 const val VERSION=1
 fun normalize(text:String):String {
  if(text.length>16384)throw EpubZipFailure("limitExceeded")
  val decomposed=Normalizer2.getNFKDInstance().normalize(text)
  val output=StringBuilder()
  var offset=0
  while(offset<decomposed.length){
   val cp=decomposed.codePointAt(offset);offset+=Character.charCount(cp)
   if(Character.getType(cp) !in setOf(Character.NON_SPACING_MARK.toInt(),Character.COMBINING_SPACING_MARK.toInt(),Character.ENCLOSING_MARK.toInt()))output.appendCodePoint(cp)
  }
  return UCharacter.foldCase(output.toString(),true)
 }
}
