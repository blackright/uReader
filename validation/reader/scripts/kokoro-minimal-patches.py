"""Targeted diagnostic edits to recorded phonemes, not a general French frontend."""
import re

VERSION='kokoro-baseline-lexical-v1'
PATCHES=(
    ('gentleman','ʒɑ̃tlmˈɑ̃','ʤɛntləman'),
    ('authentiques','ɔːθəntˈiːks','otɑ̃tˈik'),
    ('enthousiastes','ɛnθˈWziˌasts','ɑ̃tuzjˈast'),
    ('rocking-chairs','ɹˈɒkɪŋʃˈɛʁ','ʁɔkiŋʃˈɛʁ'),
)


def patch(source,phonemes):
    edits=[]
    for word,old,new in PATCHES:
        count=len(re.findall(r'(?<!\w)'+re.escape(word)+r'(?!\w)',source,re.I))
        if not count:continue
        positions=[m.start() for m in re.finditer(re.escape(old),phonemes)]
        if len(positions)!=count:raise ValueError('Baseline lexical alignment differs; no guessed substitution')
        for pos in positions:edits.append({'word':word,'baselineStart':pos,'baselineEnd':pos+len(old),'original':old,'replacement':new})
    edits.sort(key=lambda x:x['baselineStart'])
    if any(a['baselineEnd']>b['baselineStart'] for a,b in zip(edits,edits[1:])):raise ValueError('Overlapping patches')
    result=phonemes
    for e in reversed(edits):result=result[:e['baselineStart']]+e['replacement']+result[e['baselineEnd']:]
    return {'phonemes':result,'changes':edits}
