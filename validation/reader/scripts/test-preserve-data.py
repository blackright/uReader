"""Adversarial archive and logical comparison checks; synthetic local data only."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import tarfile
import tempfile
import unittest

path=Path(__file__).with_name('preserve-data.py')
spec=importlib.util.spec_from_file_location('preserve',path)
preserve=importlib.util.module_from_spec(spec);spec.loader.exec_module(preserve)

class SnapshotSafety(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=path.parents[1]/'private')
        self.root=Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def archive(self,entries):
        archive=self.root/'test.tar'
        with tarfile.open(archive,'w') as tar:
            for name,data,kind in entries:
                m=tarfile.TarInfo(name);m.type=kind
                if kind==tarfile.REGTYPE: m.size=len(data);tar.addfile(m,io.BytesIO(data))
                else: m.linkname='outside';tar.addfile(m)
        return archive
    def inspect(self,entries):
        destination=self.root/'read';destination.mkdir(exist_ok=True)
        return preserve.inspect_archive(self.archive(entries),destination)
    def test_parent_traversal_refused(self):
        with self.assertRaises(ValueError): self.inspect([('ureader-prototype/../outside',b'no',tarfile.REGTYPE)])
        self.assertFalse((self.root/'outside').exists())
    def test_absolute_path_refused(self):
        with self.assertRaises(ValueError): self.inspect([('/outside',b'no',tarfile.REGTYPE)])
    def test_symlink_refused(self):
        with self.assertRaises(ValueError): self.inspect([('ureader-prototype/link',b'',tarfile.SYMTYPE)])
    def test_duplicate_path_refused(self):
        with self.assertRaises(ValueError): self.inspect([('ureader-prototype/x',b'1',tarfile.REGTYPE),('ureader-prototype/x',b'2',tarfile.REGTYPE)])
    def test_missing_or_corrupt_database_refused(self):
        with self.assertRaises(ValueError): self.inspect([('ureader-prototype/x',b'1',tarfile.REGTYPE)])
        with self.assertRaises(sqlite3.Error): self.inspect([('ureader-prototype/prototype.sqlite',b'invalid',tarfile.REGTYPE)])
    def test_logical_snapshot_detects_table_change(self):
        dbfile=self.root/'source.sqlite';db=sqlite3.connect(dbfile)
        db.execute('create table positions(id integer primary key, value text)')
        db.execute("insert into positions values(1,'synthetic')");db.commit();db.close()
        first=self.inspect([('ureader-prototype/prototype.sqlite',dbfile.read_bytes(),tarfile.REGTYPE)])
        destination=self.root/'second';destination.mkdir()
        db=sqlite3.connect(dbfile);db.execute("update positions set value='changed'");db.commit();db.close()
        archive=self.archive([('ureader-prototype/prototype.sqlite',dbfile.read_bytes(),tarfile.REGTYPE)])
        second=preserve.inspect_archive(archive,destination)
        self.assertNotEqual(first['tables']['positions']['sha256'],second['tables']['positions']['sha256'])
        old=preserve.PRIVATE;preserve.PRIVATE=self.root
        try:
            for name,value in [('before',first),('same',first),('after',second)]:
                folder=self.root/name;folder.mkdir();(folder/'manifest.json').write_text(json.dumps(value),encoding='utf-8')
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(preserve.compare('before','same'),0)
                self.assertEqual(preserve.compare('before','after'),1)
        finally: preserve.PRIVATE=old
    def test_existing_snapshot_never_overwritten(self):
        destination=self.root/'existing';destination.mkdir()
        sentinel=destination/'manifest.json';sentinel.write_text('preserve',encoding='utf-8')
        old=preserve.PRIVATE;preserve.PRIVATE=self.root
        try:
            with self.assertRaises(FileExistsError): preserve.snapshot('existing',False)
            self.assertEqual(sentinel.read_text(encoding='utf-8'),'preserve')
        finally: preserve.PRIVATE=old
    def test_invalid_id_refused_before_creation(self):
        with self.assertRaises(ValueError): preserve.snapshot('../escape',False)

if __name__=='__main__': unittest.main(verbosity=2)
