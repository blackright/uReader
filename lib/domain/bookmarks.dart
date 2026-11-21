import 'books.dart';

class Bookmark {
  Bookmark({required this.id, required this.locator, required this.createdAt});
  final String id;
  final BookLocator locator;
  final int createdAt;
}

class BookmarkCursor {
  const BookmarkCursor(this.key, this.createdAt, this.id);
  final ContentKey key;
  final int createdAt;
  final String id;
}

class BookmarkPage {
  BookmarkPage(List<Bookmark> items, {this.next})
    : items = List.unmodifiable(items);
  final List<Bookmark> items;
  final BookmarkCursor? next;
}

class BookmarkAdded {
  const BookmarkAdded(this.bookmark, {required this.created});
  final Bookmark bookmark;
  final bool created;
}

enum BookmarkAvailability { exact, invalid, unavailable }

class BookmarkResolution {
  const BookmarkResolution(this.availability, {this.locator, this.chapterId});
  final BookmarkAvailability availability;
  final BookLocator? locator;
  final String? chapterId;
}

abstract interface class BookmarkStore {
  Future<BookmarkAdded> add(BookLocator locator);
  Future<BookmarkPage> list(
    ContentKey key, {
    BookmarkCursor? after,
    int limit = 50,
  });
  Future<void> remove(String id, ContentKey key);
  Future<BookmarkResolution> resolve(Bookmark bookmark);
  Future<void> flush();
}
