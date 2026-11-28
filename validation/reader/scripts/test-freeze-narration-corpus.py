"""Corpus integrity tests; synthetic fixtures only, no user text or device required."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

SCRIPT=Path(__file__).with_name('freeze-narration-corpus.py')
SOURCE='a'*64
PROJECTION='b'*64

def digest(text):return hashlib.sha256(text.encode('utf-8')).hexdigest()

class FreezeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('freeze_corpus',SCRIPT)
        cls.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(cls.module)

    def setUp(self):
        private=SCRIPT.resolve().parents[1]/'private'
        private.mkdir(exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(prefix='narration-unit-',dir=private)
        self.addCleanup(self.temp.cleanup)
        self.db=Path(self.temp.name)/'source.sqlite'
        c=sqlite3.connect(self.db)
        c.executescript('''
          CREATE TABLE books(book_id TEXT,title TEXT,state TEXT,projection_version INTEGER,source_sha256 TEXT,manifest_sha256 TEXT);
          CREATE TABLE book_blocks(book_id TEXT,block_id TEXT,chapter_id TEXT,ordinal INTEGER,kind TEXT,source_text TEXT,text_units INTEGER,speech_eligible INTEGER);
          CREATE TABLE book_page_boundaries(page INTEGER);
        ''')
        c.execute('INSERT INTO books VALUES(?,?,?,?,?,?)',('book','Chosen narrative','ready',1,SOURCE,PROJECTION))
        self.texts=['\u00c9milie lit le paragraphe '+str(i)+'.' for i in range(1,21)]
        for i,text in enumerate(['Title']+self.texts):
            c.execute('INSERT INTO book_blocks VALUES(?,?,?,?,?,?,?,?)',('book',f'c2-b{i}-s0','c2',i,'paragraph',text,len(text.encode('utf-16-le'))//2,1))
        c.commit();c.close()

    def build(self,**overrides):
        args=dict(database=self.db,book_query='Chosen',chapter='c2',start='c2-b1',expected_source=SOURCE,
                  expected_projection=PROJECTION,expected_first=digest(self.texts[0]))
        return self.module.build_corpus(**{**args,**overrides})

    def change(self,sql,args=()):
        c=sqlite3.connect(self.db);c.execute(sql,args);c.commit();c.close()

    def error(self,code,action):
        with self.assertRaises(self.module.FreezeError) as caught:action()
        self.assertEqual(caught.exception.code,code)

    def test_exact_twenty_and_original_unchanged(self):
        before=self.db.read_bytes();corpus=self.build()
        self.assertEqual([r['id'] for r in corpus['paragraphs']],[f'P{i:02}' for i in range(1,21)])
        self.assertEqual([r['sourceText'] for r in corpus['paragraphs']],self.texts)
        self.assertEqual(corpus['paragraphs'][0]['logicalId'],'c2-b1')
        self.assertEqual(corpus['paragraphs'][-1]['logicalId'],'c2-b20')
        self.assertEqual(self.db.read_bytes(),before)
        self.assertEqual(corpus['confirmation']['status'],'pending')

    def test_slices_are_joined_without_inserted_space_or_lost_unicode(self):
        first='\u00c9milie\u00a0';second='lit e\u0301cole \U0001f4d6.'
        self.change('UPDATE book_blocks SET ordinal=ordinal+1 WHERE ordinal>1')
        self.change("UPDATE book_blocks SET source_text=?,text_units=? WHERE block_id='c2-b1-s0'",(first,len(first.encode('utf-16-le'))//2))
        self.change('INSERT INTO book_blocks VALUES(?,?,?,?,?,?,?,?)',('book','c2-b1-s1','c2',2,'paragraph',second,len(second.encode('utf-16-le'))//2,1))
        result=self.build(expected_first=digest(first+second))['paragraphs'][0]
        self.assertEqual(result['sourceText'],first+second)
        self.assertEqual(result['utf16Units'],len((first+second).encode('utf-16-le'))//2)
        self.assertEqual(result['slices'][1]['startUtf16'],len(first.encode('utf-16-le'))//2)
        self.assertIn('e\u0301cole',result['expectedSourceWords'])

    def test_duplicate_book_selection_is_refused(self):
        self.change('INSERT INTO books SELECT ?,title,state,projection_version,source_sha256,manifest_sha256 FROM books',('duplicate',))
        self.error('ambiguous_book',self.build)

    def test_changed_edition_and_projection_are_refused(self):
        self.error('edition_mismatch',lambda:self.build(expected_source='c'*64))
        self.error('projection_mismatch',lambda:self.build(expected_projection='c'*64))

    def test_missing_slice_is_refused(self):
        self.change("UPDATE book_blocks SET block_id='c2-b1-s1' WHERE block_id='c2-b1-s0'")
        self.error('invalid_slices',self.build)

    def test_missing_projection_ordinal_is_refused(self):
        self.change('UPDATE book_blocks SET ordinal=ordinal+1 WHERE ordinal>=2')
        self.error('invalid_slices',self.build)

    def test_source_word_inventory_keeps_accents_and_hyphenated_words(self):
        self.assertEqual(self.module.lexical_words("L'e\u0301cole, vingt-et-un mots."),["L'e\u0301cole",'vingt-et-un','mots'])

    def test_missing_paragraph_and_title_start_are_refused(self):
        self.error('start_not_found',lambda:self.build(start='c2-b99'))
        self.error('first_paragraph_mismatch',lambda:self.build(start='c2-b0'))

    def test_duplicate_paragraph_id_is_refused(self):
        self.change("UPDATE book_blocks SET block_id='c2-b1-s0' WHERE block_id='c2-b2-s0'")
        self.error('invalid_slices',self.build)

    def test_too_few_paragraphs_and_oversized_input_are_refused(self):
        self.change("DELETE FROM book_blocks WHERE ordinal=20")
        self.error('insufficient_paragraphs',self.build)
        self.change("UPDATE book_blocks SET source_text=?,text_units=? WHERE ordinal=1",('x'*8193,8193))
        self.error('content_bounds',self.build)

    def test_pagination_does_not_change_corpus_identity(self):
        before=self.build()['corpusSha256']
        self.change('INSERT INTO book_page_boundaries VALUES(7)')
        self.assertEqual(self.build()['corpusSha256'],before)

    def test_changed_content_and_duplicate_manifest_entries_fail_verification(self):
        original=self.build()
        self.change("UPDATE book_blocks SET source_text=?,text_units=? WHERE ordinal=2",('Different.',10))
        self.error('corpus_changed',lambda:self.module.verify_corpus(original,self.db,'Chosen'))
        malformed=json.loads(json.dumps(original));malformed['paragraphs'][1]=malformed['paragraphs'][0]
        self.error('invalid_manifest',lambda:self.module.verify_corpus(malformed,self.db,'Chosen'))

    def test_equal_text_in_distinct_paragraphs_is_not_deduplicated(self):
        self.change('UPDATE book_blocks SET source_text=?,text_units=? WHERE ordinal=2',(self.texts[0],len(self.texts[0])))
        corpus=self.build()
        self.assertEqual(len(corpus['paragraphs']),20)
        self.assertNotEqual(corpus['paragraphs'][0]['logicalId'],corpus['paragraphs'][1]['logicalId'])

    def test_output_requires_fresh_private_directory(self):
        outside=SCRIPT.resolve().parents[1]/'reports'/Path(self.temp.name).name
        self.error('private_output_required',lambda:self.module.write_corpus(self.build(),outside))
        self.error('output_exists',lambda:self.module.write_corpus(self.build(),Path(self.temp.name)))

    def test_cli_failure_does_not_leak_input_paths_or_book_query(self):
        result=subprocess.run([sys.executable,str(SCRIPT),'freeze','--database',str(self.db),
            '--book-query','PRIVATE_TITLE_SENTINEL','--chapter','c2','--start','c2-b1',
            '--expected-source',SOURCE,'--expected-projection',PROJECTION,
            '--expected-first',digest(self.texts[0]),'--output',str(Path(self.temp.name)/'out')],capture_output=True,timeout=20)
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn(b'PRIVATE_TITLE_SENTINEL',result.stdout+result.stderr)
        self.assertNotIn(str(self.db).encode(),result.stdout+result.stderr)

if __name__=='__main__':unittest.main()
