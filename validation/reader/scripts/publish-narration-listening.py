"""Publish a fresh private listening packet; never infer or overwrite ratings."""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re


def quoted_source(text):
    """Book text must not become active Markdown, HTML or remote images."""
    fence='`'*(max((len(m.group()) for m in re.finditer('`+',text)),default=0)+3)
    return fence+'text\n'+text+'\n'+fence


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    private=Path(__file__).resolve().parents[1]/'private'
    for p in (args.campaign,args.output):
        if not p.resolve().is_relative_to(private.resolve()):raise ValueError('Private paths')
    spec=importlib.util.spec_from_file_location('ratings',Path(__file__).with_name('validate-narration-results.py'))
    rating=importlib.util.module_from_spec(spec);spec.loader.exec_module(rating)
    plan=json.loads((args.campaign/'plan.json').read_text(encoding='utf-8'))
    identities={'A':('Rendu Android actuel','android-listening'),
                'B':('Référence officielle PC','official-reference-T01'),
                'C':('Pocket TTS français 24 couches','pocket24-estelle-T01'),
                'D':('Kokoro français SIWIS','kokoro-siwis-T01')}
    args.output.mkdir(exist_ok=False)
    rows=[];indexes={}
    for alias,(label,directory) in identities.items():
        index=args.campaign/directory/'index.json'
        if index.exists():
            data=json.loads(index.read_text(encoding='utf-8'))
            if data['corpusSha256']!=plan['corpusSha256']:raise ValueError('Different corpus')
            indexes[alias]={p['paragraphId']:p for p in data['paragraphs']}
        else:indexes[alias]={}
    for n,p in enumerate(plan['paragraphs'],1):
        for alias,(label,directory) in identities.items():
            row=rating.blank(plan['corpusSha256'],alias,f'P{n:02d}',1)
            entry=indexes[alias].get(row['paragraphId'])
            if entry:
                wav=(args.campaign/directory/entry['wav']).resolve()
                if wav.parent!=(args.campaign/directory).resolve():raise ValueError('Audio path')
                if hashlib.sha256(wav.read_bytes()).hexdigest()!=entry['sha256']:raise ValueError('Audio integrity')
                row.update(audioSha256=entry['sha256'],audioPath=wav.as_posix())
            else:row['audioPath']=None
            rows.append(row)
    rating.validate({'corpusSha256':plan['corpusSha256'],'ratings':rows})
    (args.output/'ratings.json').write_text(json.dumps({'corpusSha256':plan['corpusSha256'],
        'ownerAcceptedCandidate':None,'ratings':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with (args.output/'ratings.csv').open('x',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f);writer.writerow(['prise','prononciation','ponctuation','intonation','naturel','erreurs','audio'])
        for row in rows:writer.writerow([row['takeId'],'','','','','',row['audioPath'] or 'Indisponible'])
    index=['# Écoute comparative P01–P20','',
           'Comparaison non aveugle : A = Android actuel, B = référence PC, C = Pocket TTS 24 couches, D = Kokoro.',
           'Les rendus absents restent indisponibles. Aucune note ni préférence présumée.',
           'Avant écoute, noter casque/haut-parleur, volume et date ; conserver ces conditions.',
           'Quatre notes par prise (1–5) : prononciation, ponctuation, intonation, naturel.',
           '1 inutilisable ; 2 très défectueux ; 3 mécanique ; 4 naturel ; 5 très expressif.',
           'Signaler les erreurs et leur passage. Une moyenne ne masque aucun défaut.',
           'Les noms étrangers admettent une lecture francisée ou une lecture d’origine intelligible ;',
           'toute variante ambiguë sera explicitement convenue avant notation du mot concerné.',
           'La ponctuation ne doit pas être lue comme des symboles ; dialogues et incises gardent leur sens.','']
    for start in range(0,20,5):
        file=f'lot-{start//5+1:02d}.md'
        index.append(f'- [P{start+1:02d}–P{start+5:02d}]({file})')
        text=[f'# Lot P{start+1:02d}–P{start+5:02d}','','Notes à consigner dans ratings.csv ou à communiquer au porteur du banc.','']
        for n in range(start+1,start+6):
            text.extend([f'## P{n:02d}','','Texte attendu :','',quoted_source(plan['paragraphs'][n-1]['source']),''])
            for row in [r for r in rows if r['paragraphId']==f'P{n:02d}']:
                text.append(f"- [{row['takeId']}]({row['audioPath']})" if row['audioPath'] else f"- {row['takeId']} : indisponible, ne pas noter.")
            text.append('')
        (args.output/file).write_text('\n'.join(text)+'\n',encoding='utf-8')
    (args.output/'index.md').write_text('\n'.join(index)+'\n',encoding='utf-8')
    print(json.dumps({'ratings':len(rows),'availableAudio':sum(r['audioPath'] is not None for r in rows),'scores':'not_evaluated'}))


if __name__=='__main__':main()
