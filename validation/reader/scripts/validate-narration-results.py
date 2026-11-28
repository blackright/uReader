"""Validate owner ratings; absent scores never become an implicit success."""
import argparse
import json
import hashlib
from pathlib import Path
import re
from datetime import date

DIMENSIONS=('pronunciation','punctuation','intonation','naturalness')


def expected(candidate):
    return {(candidate,f'P{i:02d}',take) for i in range(1,21)
            for take in ((1,2,3) if i in (1,5,10,15,20) else (1,))}


def blank(corpus,candidate,paragraph,take):
    return {'corpusSha256':corpus,'candidateId':candidate,'paragraphId':paragraph,
            'takeNumber':take,'takeId':f'{candidate}-{paragraph}-T{take:02d}',
            'audioSha256':None,'evaluator':None,'date':None,'conditions':None,
            'listened':False,'scores':dict.fromkeys(DIMENSIONS),'errors':[]}


def validate(data,candidate=None):
    corpus=data['corpusSha256']
    if not re.fullmatch('[a-f0-9]{64}',corpus):raise ValueError('Corpus hash')
    issues=data.get('openIssues',[])
    if not isinstance(issues,list):raise ValueError('Issue list required')
    unresolved=0
    for issue in issues:
        if not issue.get('description') or issue.get('status') not in ('open','pending_localization','resolved'):raise ValueError('Issue state')
        if issue['status']=='resolved' and not issue.get('resolution'):raise ValueError('Resolution evidence required')
        if issue['status']!='resolved' and (candidate is None or issue.get('candidateId') in (None,candidate)):unresolved+=1
    seen=set();counts={'accepted':0,'rejected':0,'pending':0}
    for row in data['ratings']:
        key=(row['candidateId'],row['paragraphId'],row['takeNumber'])
        if (not re.fullmatch('[A-Z]',key[0]) or type(key[2]) is not int
                or row.get('takeId')!=f'{key[0]}-{key[1]}-T{key[2]:02d}'):
            raise ValueError('Take identity')
        if key in seen or key not in expected(key[0]):raise ValueError('Take identity')
        if row['corpusSha256']!=corpus:raise ValueError('Different corpus')
        seen.add(key)
        if set(row['scores'])!=set(DIMENSIONS):raise ValueError('Four dimensions required')
        values=list(row['scores'].values())
        if any(v is not None and (type(v) is not int or not 1<=v<=5) for v in values):raise ValueError('Score range')
        if not isinstance(row['errors'],list):raise ValueError('Error list required')
        for error in row['errors']:
            if (not all(error.get(k) for k in ('category','expected','description','severity'))
                    or type(error.get('startUtf16')) is not int or type(error.get('endUtf16')) is not int
                    or not 0<=error['startUtf16']<error['endUtf16']
                    or type(error.get('resolved')) is not bool):
                raise ValueError('Localized error required')
        if row['listened'] is not True or any(v is None for v in values):state='pending'
        else:
            if not row.get('evaluator') or not row.get('date') or not row.get('conditions'):raise ValueError('Listening attribution')
            if not re.fullmatch('[a-f0-9]{64}',row.get('audioSha256') or ''):raise ValueError('Listened audio identity')
            if not re.fullmatch(r'\d{4}-\d{2}-\d{2}',row['date']):raise ValueError('Listening date')
            date.fromisoformat(row['date'])
            if not row['conditions'].get('device') or not row['conditions'].get('volume'):raise ValueError('Listening conditions')
            state='accepted' if min(values)>=4 and not any(e.get('resolved') is not True for e in row['errors']) else 'rejected'
        if candidate is None or key[0]==candidate:counts[state]+=1
    missing=len(expected(candidate)-seen) if candidate else None
    return {**counts,'missing':missing,'openIssues':unresolved,'candidateAccepted':bool(candidate and missing==0 and counts['accepted']==30 and unresolved==0 and data.get('ownerAcceptedCandidate')==candidate)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ratings',required=True,type=Path)
    parser.add_argument('--candidate')
    args=parser.parse_args()
    private=Path(__file__).resolve().parents[1]/'private'
    if not args.ratings.resolve().is_relative_to(private.resolve()):raise ValueError('Private ratings required')
    data=json.loads(args.ratings.read_text(encoding='utf-8'))
    for row in data['ratings']:
        path=row.get('audioPath')
        if path:
            audio=Path(path).resolve()
            if not audio.is_relative_to(private.resolve()):raise ValueError('Private audio required')
            if hashlib.sha256(audio.read_bytes()).hexdigest()!=row['audioSha256']:raise ValueError('Changed rated audio')
        elif row.get('listened') is True:raise ValueError('Listened audio path missing')
    print(json.dumps(validate(data,args.candidate)))


if __name__=='__main__':main()
