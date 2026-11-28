"""Freeze twenty logical narrative paragraphs from a read-only private projection snapshot."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import unicodedata

ROOT=Path(__file__).resolve().parents[3]
PRIVATE=ROOT/'validation/reader/private'
SLICE=re.compile(r'^(c[0-9]+)-b([0-9]+)-s([0-9]+)$')
HEX=re.compile(r'^[a-f0-9]{64}$')

def lexical_words(text):
    # Match the reader's letter/mark/number policy, including decomposed accents.
    words=[];current=[]
    for i,char in enumerate(text):
        member=unicodedata.category(char)[0] in 'LMN'
        connector=char in "'\u2019\u2010\u2011-" and current and i+1<len(text) and unicodedata.category(text[i+1])[0] in 'LMN'
        if member or connector:current.append(char)
        elif current:words.append(''.join(current));current=[]
    if current:words.append(''.join(current))
    return words

class FreezeError(Exception):
    def __init__(self,code):self.code=code;super().__init__(code)

def sha(text):return hashlib.sha256(text.encode('utf-8')).hexdigest()
def units(text):return len(text.encode('utf-16-le'))//2
def require(ok,code):
    if not ok:raise FreezeError(code)

def logical_id(block,chapter):
    match=SLICE.fullmatch(block)
    if match:
        require(match[1]==chapter,'invalid_slices')
        return f'{match[1]}-b{match[2]}',int(match[3])
    require(not re.match(r'^c[0-9]+-b[0-9]+-s',block),'invalid_slices')
    require(bool(re.fullmatch(r'[a-z0-9-]{1,120}',block)),'invalid_slices')
    return block,0

def groups(rows,chapter):
    current=None;parts=[];seen=set();previous=None;count=0
    def finish():
        require([r[7] for r in parts]==list(range(len(parts))),'invalid_slices')
        require(len({(r[2],r[5]) for r in parts})==1,'invalid_slices')
        text=''.join(r[3] for r in parts)
        require(units(text)<=262144,'content_bounds')
        return current,parts[0][2],parts[0][5],text,list(parts)
    for row in rows:
        count+=1;require(count<=4096,'content_bounds')
        block,ordinal,kind,text,text_units,eligible=row
        require(isinstance(text,str) and isinstance(ordinal,int) and ordinal>=0,'invalid_projection')
        require(units(text)==text_units and text_units<=8192,'content_bounds')
        require(previous is None or ordinal==previous+1,'invalid_slices');previous=ordinal
        identity,index=logical_id(block,chapter)
        if current is not None and identity!=current:
            yield finish();seen.add(current);parts=[]
        require(identity not in seen,'invalid_slices')
        current=identity;parts.append((block,ordinal,kind,text,text_units,eligible,identity,index))
    if parts:yield finish()

def corpus_identity(corpus):
    identity={'edition':corpus['edition'],'chapterId':corpus['selection']['chapterId'],
        'startLogicalId':corpus['selection']['startLogicalId'],
        'paragraphs':[{k:r[k] for k in ['id','logicalId','sourceSha256','utf16Units','slices']} for r in corpus['paragraphs']]}
    return sha(json.dumps(identity,ensure_ascii=False,sort_keys=True,separators=(',',':')))

def build_corpus(database,book_query,chapter,start,expected_source,expected_projection,expected_first):
    require(len(book_query.strip())>=3,'invalid_selection')
    require(bool(re.fullmatch(r'c[0-9]+',chapter)),'invalid_selection')
    require(all(HEX.fullmatch(v) for v in [expected_source,expected_projection,expected_first]),'invalid_lock')
    database=Path(database).resolve()
    require(database.is_file() and database.stat().st_size<=67108864,'invalid_snapshot')
    connection=sqlite3.connect(database.as_uri()+'?mode=ro',uri=True)
    try:
        connection.execute('PRAGMA query_only=ON')
        connection.execute('PRAGMA trusted_schema=OFF')
        require(connection.execute('PRAGMA quick_check').fetchone()==('ok',),'invalid_snapshot')
        books=connection.execute("SELECT book_id,source_sha256,manifest_sha256,projection_version FROM books WHERE state='ready' AND instr(lower(title),lower(?))>0 LIMIT 2",(book_query,)).fetchall()
        require(len(books)==1,'ambiguous_book' if len(books)>1 else 'book_not_found')
        book,source,projection,version=books[0]
        require(isinstance(version,int) and version>=1,'invalid_projection')
        require(source==expected_source,'edition_mismatch')
        require(projection==expected_projection,'projection_mismatch')
        rows=connection.execute('SELECT block_id,ordinal,kind,source_text,text_units,speech_eligible FROM book_blocks WHERE book_id=? AND chapter_id=? ORDER BY ordinal',(book,chapter))
        selected=[];started=False;total=0
        for identity,kind,eligible,text,slices in groups(rows,chapter):
            if identity==start:started=True
            if not started:continue
            if kind!='paragraph' or eligible!=1 or not text.strip():continue
            if not selected:require(sha(text)==expected_first,'first_paragraph_mismatch')
            offset=0;references=[]
            for block,ordinal,_,part,size,_,_,_ in slices:
                references.append({'blockId':block,'ordinal':ordinal,'startUtf16':offset,
                    'endUtf16':offset+size,'sourceSha256':sha(part)})
                offset+=size
            total+=offset;require(total<=1048576,'content_bounds')
            selected.append({'id':f'P{len(selected)+1:02}','logicalId':identity,'chapterId':chapter,
                'sourceText':text,'sourceSha256':sha(text),'utf16Units':offset,
                'expectedSourceWords':lexical_words(text),'slices':references})
            if len(selected)==20:break
        require(started,'start_not_found')
        require(len(selected)==20,'insufficient_paragraphs')
        corpus={'schemaVersion':1,'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'edition':{'sourceSha256':source,'projectionSha256':projection,'projectionVersion':version},
            'selection':{'bookId':book,'chapterId':chapter,'startLogicalId':start,'count':20,
                'rule':'Twenty consecutive eligible narrative paragraphs from the pinned start; headings and front matter excluded.'},
            'paragraphs':selected,'confirmation':{'status':'pending','record':'corpus-confirmation.json'},
            'audioGenerated':False,'listening':'not_evaluated'}
        corpus['corpusSha256']=corpus_identity(corpus)
        return corpus
    finally:connection.close()

def verify_corpus(corpus,database,book_query):
    try:
        rows=corpus['paragraphs']
        require(corpus['schemaVersion']==1 and len(rows)==20,'invalid_manifest')
        require([r['id'] for r in rows]==[f'P{i:02}' for i in range(1,21)],'invalid_manifest')
        require(len({r['logicalId'] for r in rows})==20,'invalid_manifest')
        for row in rows:
            require(sha(row['sourceText'])==row['sourceSha256'] and units(row['sourceText'])==row['utf16Units'],'invalid_manifest')
            require(lexical_words(row['sourceText'])==row['expectedSourceWords'],'invalid_manifest')
        require(corpus_identity(corpus)==corpus['corpusSha256'],'invalid_manifest')
        selection=corpus['selection'];edition=corpus['edition']
        current=build_corpus(database,book_query,selection['chapterId'],selection['startLogicalId'],
            edition['sourceSha256'],edition['projectionSha256'],rows[0]['sourceSha256'])
        require(current['corpusSha256']==corpus['corpusSha256'],'corpus_changed')
    except (KeyError,TypeError,ValueError,IndexError) as error:
        raise FreezeError('invalid_manifest') from error

def write_corpus(corpus,output):
    output=Path(output).resolve()
    require(output.is_relative_to(PRIVATE.resolve()) and output!=PRIVATE.resolve(),'private_output_required')
    require(not output.exists(),'output_exists')
    output.mkdir(parents=True,exist_ok=False)
    (output/'corpus.json').write_text(json.dumps(corpus,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    preview=['# Corpus privé — paragraphes 1 à 20','',
        'Liste à confirmer par le porteur. Aucun audio ni avis de qualité n’a été produit.','',
        'Les titres et pages liminaires sont exclus. Chaque entrée est un paragraphe logique, même si le stockage utilise plusieurs tranches.','']
    for row in corpus['paragraphs']:preview.extend([f"## {row['id']}",'',row['sourceText'],''])
    (output/'corpus-preview.md').write_text('\n'.join(preview),encoding='utf-8',newline='\n')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='command',required=True)
    freeze=commands.add_parser('freeze');verify=commands.add_parser('verify')
    for command in [freeze,verify]:
        command.add_argument('--database',type=Path,required=True)
        command.add_argument('--book-query',required=True)
    for field in ['chapter','start','expected-source','expected-projection','expected-first']:
        freeze.add_argument('--'+field,required=True)
    freeze.add_argument('--output',type=Path,required=True)
    verify.add_argument('--manifest',type=Path,required=True)
    args=parser.parse_args()
    try:
        if args.command=='freeze':
            corpus=build_corpus(args.database,args.book_query,args.chapter,args.start,args.expected_source,args.expected_projection,args.expected_first)
            write_corpus(corpus,args.output)
            print(json.dumps({'status':'frozen_pending_confirmation','paragraphs':20,'corpusSha256':corpus['corpusSha256']}))
        else:
            require(args.manifest.stat().st_size<=16777216,'invalid_manifest')
            corpus=json.loads(args.manifest.read_text(encoding='utf-8'))
            verify_corpus(corpus,args.database,args.book_query)
            print(json.dumps({'status':'verified','paragraphs':20,'corpusSha256':corpus['corpusSha256']}))
    except FreezeError as error:
        print(json.dumps({'status':'failed','code':error.code}));return 1
    except (OSError,sqlite3.Error,UnicodeError,ValueError):
        print(json.dumps({'status':'failed','code':'invalid_snapshot_or_manifest'}));return 1
    return 0

if __name__=='__main__':raise SystemExit(main())
