"""Prepare a bounded private Android corpus run from frozen Dart source/mapping metadata."""
import argparse,hashlib,json,os,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def text_sha(text):return hashlib.sha256(text.encode('utf-8')).hexdigest()
def build(corpus,encode):
 cases=corpus['cases']
 if not 0<len(cases)<=256:raise ValueError('Occurrence budget')
 seen=set();unique={};occurrences=[]
 for case in cases:
  identifier=case['id'];source=case['source'];prepared=case['prepared'];digest=case['preparedSha256']
  if not re.fullmatch(r'p[0-9]+-s[0-9]+',identifier) or identifier in seen:raise ValueError('Invalid occurrence ID')
  seen.add(identifier)
  if not isinstance(source,str) or not isinstance(prepared,str) or not 0<len(prepared.encode('utf-16-le'))//2<=4096:raise ValueError('Text budget')
  if case['sourceSha256']!=text_sha(source) or digest!=text_sha(prepared):raise ValueError('Text hash mismatch')
  if digest not in unique:
   ids,offsets=encode(prepared)
   if not 0<len(ids)<=50 or len(ids)!=len(offsets):raise ValueError('Token budget')
   if any(not isinstance(i,int) or i<0 for i in ids):raise ValueError('Invalid token')
   if any(a<0 or b<a or b>len(prepared.encode('utf-16-le'))//2 for a,b in offsets):raise ValueError('Token coordinates')
   unique[digest]={'id':digest,'prepared':prepared,'preparedSha256':digest,'tokenIds':ids,'tokenOffsets':offsets,'seed':71+len(unique)}
  occurrences.append(dict(case,uniqueId=digest))
 if len(unique)>64:raise ValueError('Unique graph-run budget')
 return {'schemaVersion':1,'g1':'not_evaluated','annotationsFrozen':False,'spokenWordCountVerified':False,
  'uniqueCases':list(unique.values()),'occurrences':occurrences,'units':corpus['units'],'spokenWords':corpus['spokenWords'],
  'note':'Android inference runs once per unique prepared text. All occurrences retain separate source coordinates and future observations.'}
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run-id',required=True);parser.add_argument('--provision',action='store_true');args=parser.parse_args()
 if not re.fullmatch(r'corpus-[a-z0-9-]{1,48}',args.run_id):parser.error('Invalid run ID')
 from tokenizers import Tokenizer
 frozen=ROOT/'validation/reader/private/frozen-alignment-corpus-02/corpus.json'
 raw=frozen.read_bytes();corpus=json.loads(raw)
 for key,file in [('normalizerSourceSha256','french_text_normalizer.dart'),('preparationSourceSha256','prepared_text_map.dart'),('segmenterSourceSha256','speech_segmenter.dart')]:
  if corpus[key]!=hashlib.sha256((ROOT/'lib/features/listening'/file).read_bytes()).hexdigest():raise ValueError('Frozen code mismatch')
 manifest=json.loads((ROOT/'assets/models/manifest.json').read_text(encoding='utf-8'))
 tokenizer_path=ROOT/'validation/private/aligned-bundle-01/tokenizer.json'
 expected=next(e['sha256'] for e in manifest['files'] if e['relativePath']=='tokenizer.json')
 if hashlib.sha256(tokenizer_path.read_bytes()).hexdigest()!=expected:raise ValueError('Tokenizer mismatch')
 tokenizer=Tokenizer.from_file(str(tokenizer_path))
 def encode(text):
  encoded=tokenizer.encode(text,add_special_tokens=False);u16=lambda i:len(text[:i].encode('utf-16-le'))//2
  return encoded.ids,[(u16(a),u16(b)) for a,b in encoded.offsets]
 result=build(corpus,encode);result.update({'runId':args.run_id,'corpusSha256':hashlib.sha256(raw).hexdigest(),'normalizerVersion':corpus['normalizerVersion'],'preparedMapVersion':corpus['preparedMapVersion'],'tokenizerSha256':expected})
 trust=(ROOT/'validation/reader/private/attention-probe-03/bundle-trust.json').read_bytes()
 product={e['relativePath']:{'byteSize':e['byteSize'],'sha256':e['sha256']} for e in manifest['files']}
 trust_bytes=json.dumps({'baseline':product,'candidate':json.loads(trust)},separators=(',',':'),sort_keys=True).encode()
 result['modelTrustSha256']=hashlib.sha256(trust_bytes).hexdigest()
 encoded=json.dumps(result,ensure_ascii=False,separators=(',',':')).encode('utf-8')
 if len(encoded)>3*1024*1024:raise ValueError('Manifest size budget')
 directory=ROOT/'validation/reader/private'/args.run_id;directory.mkdir(exist_ok=False)
 (directory/'input.json').write_bytes(encoded);(directory/'experiment.json').write_bytes(trust_bytes)
 digest=hashlib.sha256(encoded).hexdigest()
 if args.provision:
  adb=[str(Path(os.environ['LOCALAPPDATA'])/'Android/sdk/platform-tools/adb.exe'),'-s','2291940c08037ece']
  target='files/ureader-alignment-corpus/'+args.run_id
  subprocess.run(adb+['shell',"run-as com.ureader.prototype sh -c 'test ! -e "+target+" && mkdir -p "+target+"'"],check=True)
  for name,data in [('input.json',encoded),('experiment.json',trust_bytes)]:
   remote=target+'/'+name
   subprocess.run(adb+['exec-in',"run-as com.ureader.prototype sh -c 'cat > "+remote+"'"],input=data,check=True,timeout=60)
   actual=subprocess.check_output(adb+['shell','run-as','com.ureader.prototype','sha256sum',remote],timeout=30).decode().split()[0]
   if actual!=hashlib.sha256(data).hexdigest():raise ValueError('USB transfer mismatch')
 summary={'runId':args.run_id,'inputSha256':digest,'occurrences':len(result['occurrences']),'uniquePrepared':len(result['uniqueCases']),'sourceUnits':len(result['units']),'preparedLexicalUnits':len(result['spokenWords']),'provisioned':args.provision,'g1':'not_evaluated'}
 (directory/'preparation.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8');print(json.dumps(summary))
if __name__=='__main__':main()
