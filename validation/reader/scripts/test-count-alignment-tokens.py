"""Regression: accented UTF-8 text must not acquire extra tokens on Windows pipes."""
import json,os,subprocess,sys,unittest
from pathlib import Path
from tokenizers import Tokenizer

ROOT=Path(__file__).resolve().parents[3]

class TokenPipeTest(unittest.TestCase):
    def test_utf8_input_under_legacy_pipe_encoding(self):
        texts=["L'\u00e9trange voyage\u00a0!",'\u00c0 No\u00ebl, \u00c9milie pr\u00e9pare une cr\u00e8me br\u00fbl\u00e9e.',
               'Ars\u00e8ne Lupin observe l\u2019\u00eele.', 'vingt-et-un pommes']
        tokenizer=Tokenizer.from_file(str(ROOT/'validation/private/aligned-bundle-01/tokenizer.json'))
        env={**os.environ,'PYTHONUTF8':'0','PYTHONIOENCODING':'cp1252'}
        result=subprocess.run([sys.executable,str(Path(__file__).with_name('count-alignment-tokens.py'))],
            input=('\n'.join(json.dumps(t,ensure_ascii=False) for t in texts)+'\n').encode('utf-8'),
            capture_output=True,check=True,cwd=ROOT,env=env,timeout=30)
        counts=[json.loads(row)['count'] for row in result.stdout.splitlines()]
        self.assertEqual(counts,[len(tokenizer.encode(t,add_special_tokens=False).ids) for t in texts])

if __name__=='__main__':unittest.main()
