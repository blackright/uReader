/// Additive v3 reader tables. Legacy schema and voice registry stay unchanged.
abstract final class ReaderSchema {
  static const statements = [
    """CREATE TABLE book_bookmarks (
 bookmark_id TEXT PRIMARY KEY NOT NULL,
 book_id TEXT NOT NULL, projection_version INTEGER NOT NULL CHECK(projection_version>0),
 chapter_id TEXT NOT NULL, block_id TEXT NOT NULL, offset_utf16 INTEGER NOT NULL CHECK(offset_utf16>=0),
 created_at INTEGER NOT NULL,
 UNIQUE(book_id,projection_version,chapter_id,block_id,offset_utf16),
 FOREIGN KEY(book_id,projection_version) REFERENCES books(book_id,projection_version) ON DELETE CASCADE,
 FOREIGN KEY(book_id,chapter_id,block_id) REFERENCES book_blocks(book_id,chapter_id,block_id) ON DELETE CASCADE)""",
    'CREATE INDEX book_bookmarks_order ON book_bookmarks(book_id,created_at,bookmark_id)',
    """CREATE TABLE book_page_runs (
 run_id TEXT PRIMARY KEY NOT NULL, book_id TEXT NOT NULL,
 projection_version INTEGER NOT NULL CHECK(projection_version>0), fingerprint TEXT NOT NULL CHECK(length(fingerprint)=64 AND fingerprint NOT GLOB '*[^0-9a-f]*'),
 state TEXT NOT NULL CHECK(state IN ('calculating','ready','cancelled','error')),
 generation INTEGER NOT NULL CHECK(generation>0), prefix_pages INTEGER NOT NULL CHECK(prefix_pages>=0),
 checkpoint_json TEXT NOT NULL CHECK(length(checkpoint_json) BETWEEN 1 AND 16384),
 total INTEGER CHECK(total IS NULL OR total>=0), last_access_at INTEGER NOT NULL,
 UNIQUE(book_id,projection_version,fingerprint),
 CHECK((state='ready' AND total IS NOT NULL AND total=prefix_pages) OR (state!='ready' AND total IS NULL)),
 FOREIGN KEY(book_id,projection_version) REFERENCES books(book_id,projection_version) ON DELETE CASCADE)""",
    'CREATE INDEX book_page_runs_lru ON book_page_runs(book_id,last_access_at,run_id)',
    """CREATE TABLE book_page_boundaries (
 run_id TEXT NOT NULL, page_ordinal INTEGER NOT NULL CHECK(page_ordinal>=0),
 start_ordinal INTEGER NOT NULL CHECK(start_ordinal>=0), start_utf16 INTEGER NOT NULL CHECK(start_utf16>=0),
 end_ordinal INTEGER NOT NULL CHECK(end_ordinal>=start_ordinal), end_utf16 INTEGER NOT NULL CHECK(end_utf16>=0),
 CHECK(end_ordinal>start_ordinal OR end_utf16>start_utf16),
 PRIMARY KEY(run_id,page_ordinal), FOREIGN KEY(run_id) REFERENCES book_page_runs(run_id) ON DELETE CASCADE)""",
    """CREATE TABLE experience_preferences (
 preference_key TEXT PRIMARY KEY NOT NULL CHECK(preference_key IN ('reader_mode','line_height','margins','follow_enabled','audio_presentation')),
 value_json TEXT NOT NULL CHECK(length(value_json) BETWEEN 1 AND 16384),
 version INTEGER NOT NULL CHECK(version>0))""",
  ];
}
