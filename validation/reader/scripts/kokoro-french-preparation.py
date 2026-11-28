"""Versioned laboratory French lexicon and source-preserving Kokoro chunking."""
import re

VERSION='kokoro-fr-diagnostic-v2.1'
# Proposed French readings; owner listening remains the acceptance criterion.
# Kokoro's single-character affricate ʤ represents IPA dʒ.
LEXICON={
    'gentleman':'ʤɛntləman', 'gentlemen':'ʤɛntləman',
    'authentique':'otɑ̃tˈik', 'authentiques':'otɑ̃tˈik',
    'enthousiaste':'ɑ̃tuzjˈast', 'enthousiastes':'ɑ̃tuzjˈast',
    'fervent':'fɛʁvˈɑ̃', 'fervents':'fɛʁvˈɑ̃',
    'rocking-chair':'ʁɔkiŋʃˈɛʁ', 'rocking-chairs':'ʁɔkiŋʃˈɛʁ',
    'bookmaker':'bukmɛkˈœʁ', 'bookmakers':'bukmɛkˈœʁ', 'nelly':'nˈɛli',
}
WORDS=re.compile(r'(?<!\w)(?:'+ '|'.join(re.escape(w) for w in sorted(LEXICON,key=len,reverse=True))+r')(?!\w)',re.I)
# Limited liaison support at explicit dictionary boundaries, not a full French grammar.
LIAISONS={**dict.fromkeys(('les','des','mes','tes','ses','nos','vos','ces','aux'),'z'),
          **dict.fromkeys(('un','en','mon','ton','son'),'n'),
          **dict.fromkeys(('seront','sont','ont'),'t')}


def units(text):return len(text.encode('utf-16-le'))//2


def phonemize(source,g2p):
    if not source or units(source)>8192:raise ValueError('Source bounds')
    pieces=[];overrides=[];at=0
    def native(text):
        if not text.strip():return ''
        phones=g2p(text)
        # Misaki can place ties inside the language flags themselves.
        if re.search(r'\([a-z]{2,}(?:-[a-z]+)?\)',phones.replace('^','')):
            raise ValueError('Language switch outside explicit French lexicon')
        # Quotes delimit speech; they are not spoken words. Keep source intact.
        return re.sub(r'\s+',' ',phones.translate(str.maketrans('','','«»“”„"'))).strip()
    for match in WORDS.finditer(source):
        prefix=source[at:match.start()]
        before=native(prefix)
        replacement=LEXICON[match.group().casefold()]
        liaison=None
        previous=re.search(r'([^\W\d_]+)\s+$',source[:match.start()])
        if previous and replacement[0] in 'aɑɛeioɔuœəy':
            liaison=LIAISONS.get(previous.group(1).casefold())
            if liaison and before and not before.endswith(liaison):before+=liaison
        if before:pieces.append(before)
        pieces.append(replacement)
        overrides.append({'word':match.group(),'startUtf16':units(source[:match.start()]),
                          'endUtf16':units(source[:match.end()]),'phonemes':replacement,
                          'liaison':liaison,'status':'proposed_listening_pending'})
        at=match.end()
    tail=native(source[at:])
    if tail:pieces.append(tail)
    phones=' '.join(pieces)
    if not phones:raise ValueError('Empty phonemes')
    return {'source':source,'phonemes':phones,'overrides':overrides}


def chunks(source,prepare,limit=510):
    if not source or units(source)>8192 or not 1<=limit<=510:raise ValueError('Preparation bounds')
    word_ends=[m.end() for m in re.finditer(r'\S+\s*',source)]
    sentence_ends={m.end() for m in re.finditer(r'[.!?…]+[\s»”"\u0027’\]\)]*(?=\S|$)',source)}
    clause_ends={m.end() for m in re.finditer(r'[,;:][\s»”"\u0027’\]\)]*(?=\S|$)',source)}
    all_ends=sorted(set(word_ends)|sentence_ends|clause_ends|{len(source)})
    result=[];start=0
    while start<len(source):
        candidates=[end for end in all_ends if end>start]
        cache={}
        def fitting(end):
            if end not in cache:
                text=source[start:end]
                cache[end]=prepare(text) if units(text)<=4096 else None
            row=cache[end]
            return row is not None and 0<len(row['phonemes'])<=limit
        # Evaluate candidates in order: no monotonic token-count assumption.
        fits=[end for end in candidates if fitting(end)]
        if not fits:raise ValueError('No complete word fits Kokoro context')
        if len(source) in fits:end=len(source)
        else:
            sentences=[e for e in fits if e in sentence_ends]
            clauses=[e for e in fits if e in clause_ends]
            end=max(sentences or clauses or fits)
        row=cache[end]
        result.append({**row,'source':source[start:end],
                       'startUtf16':units(source[:start]),'endUtf16':units(source[:end])})
        start=end
    if ''.join(row['source'] for row in result)!=source:raise ValueError('Source coverage')
    return result
