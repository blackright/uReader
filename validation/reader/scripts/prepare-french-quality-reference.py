"""Private reference chunking experiment, with pinned local tokenizer and no downloads."""
import argparse,hashlib,json,os,re,socket
from pathlib import Path

os.environ['HF_HUB_OFFLINE']='1'
os.environ['HF_HUB_DISABLE_TELEMETRY']='1'
def offline(*args,**kwargs):raise RuntimeError('Network forbidden')
socket.socket.connect=socket.socket.connect_ex=socket.create_connection=socket.getaddrinfo=offline

from pocket_tts.models.text_chunking import prepare_text_prompt,split_into_best_sentences
from pocket_tts.modules.text_conditioner import JsonTokenizer
import importlib.metadata,yaml
import pocket_tts

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[3]
    private=(root/'validation/reader/private').resolve()
    if not args.input.resolve().is_relative_to(private) or not args.output.resolve().is_relative_to(private) or args.output.exists():raise ValueError('Fresh private paths required')
    if importlib.metadata.version('pocket-tts')!='3.3.0':raise ValueError('Pinned package required')
    data=json.loads(args.input.read_text(encoding='utf-8'))
    tokenfile=root/'validation/private/aligned-bundle-01/tokenizer.json'
    manifest=json.loads((root/'assets/models/manifest.json').read_text(encoding='utf-8'))
    assert hashlib.sha256(tokenfile.read_bytes()).hexdigest()==next(f['sha256'] for f in manifest['files'] if f['relativePath']=='tokenizer.json')
    tokenizer=JsonTokenizer(4000,str(tokenfile.resolve()))
    configfile=Path(pocket_tts.__file__).parent/'config/french.yaml'
    config=yaml.safe_load(configfile.read_text(encoding='utf-8'))
    for i,row in enumerate(data['cases']):row['seed']=71+i
    variants=[]
    for paragraph in data['paragraphs']:
        text=paragraph['normalizedText']
        chunks=split_into_best_sentences(tokenizer,text,50,False,True,replace_characters=config['replace_characters'])
        prepared=[prepare_text_prompt(c,False,True,replace_characters=config['replace_characters'])[0] for c in chunks]
        words=lambda s:re.findall(r"[^\W_]+(?:['\u2019-][^\W_]+)*",s.lower().replace('\u2019',"'"))
        assert words(text)==words(' '.join(prepared)),'Lexical content changed'
        ids=[]
        for i,(chunk,prompt) in enumerate(zip(chunks,prepared)):
            tokens=len(tokenizer.encode(prompt))
            if tokens>50:raise ValueError('Reference chunk exceeds native budget')
            id=paragraph['id']+'-reference-'+str(i+1);ids.append(id)
            data['cases'].append({'id':id,'parentId':paragraph['id'],'variant':'official-reference-chunking',
                'sourceText':chunk,'synthesisText':prompt,'tokens':tokens,'seed':71+i})
        variants.append({'id':paragraph['id'],'variant':'official-reference-chunking','caseIds':ids,
            'sourceWordsPreserved':True,'productionMappingValidated':False})
    data.update(referenceVariants=variants,referencePackage='pocket-tts 3.3.0',referenceConfigSha256=hashlib.sha256(configfile.read_bytes()).hexdigest(),candidateChangesProduction=False)
    args.output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'baselineSegments':sum(len(p['segments']) for p in data['paragraphs']),'referenceSegments':sum(len(v['caseIds']) for v in variants),'total':len(data['cases'])}))

if __name__=='__main__':main()
