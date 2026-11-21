import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';

import 'epub_management_harness.dart';
import 'feasibility_bootstrap.dart';

void registerLibraryManagementTests(
  IntegrationTestWidgetsFlutterBinding binding,
) {
  testWidgets(
    'US4 five queries and five deletion decisions with persistent recovery',
    (tester) async {
      await waitForNative(tester);
      var h = EpubManagementHarness();
      await h.open();
      final imported = [for (var i = 0; i < 4; i++) await h.importAt(i)];
      final originals = <String, String>{};
      for (final book in imported) {
        originals[book.key.id] = sha256
            .convert(
              await File('${h.root.path}/originals/${book.key.id}.epub')
                  .readAsBytes(),
            )
            .toString();
      }
      final queryResults = <String>[];
      final title = await h.normalizer.normalize(
        imported.first.title.toUpperCase(),
      );
      expect(
        (await h.books.readyPage(search: title))
            .any((b) => b.key == imported.first.key),
        true,
      );
      queryResults.add('uppercase-title');
      final author = await h.normalizer.normalize(
        imported.first.authors.first.toUpperCase(),
      );
      expect(await h.books.readyPage(search: author), isNotEmpty);
      queryResults.add('accented-author');
      expect(await h.books.readyPage(search: '%_'), isEmpty);
      queryResults.add('literal-wildcards');
      expect(
        (await h.books.readyPage(sort: BookSort.recent)).first.key,
        imported.last.key,
      );
      queryResults.add('recent');
      final sorted = await h.books.readyPage(sort: BookSort.author);
      expect(sorted.map((b) => b.key.id).toSet().length, 4);
      queryResults.add('author-stable');
      expect(await h.removal.remove(imported[0].key, confirmed: false), false);
      expect(await h.removal.remove(imported[1].key, confirmed: false), false);
      expect(await h.books.readyPage(), hasLength(4));
      expect(await h.removal.remove(imported[0].key, confirmed: true), true);
      await h.db.customStatement(
        "CREATE TRIGGER interrupted_delete BEFORE DELETE ON books WHEN OLD.book_id='epub-02' BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await expectLater(
        h.removal.remove(imported[1].key, confirmed: true),
        throwsA(anything),
      );
      expect(await h.recovery.recover(), hasLength(1));
      // Remove the artificial fault before reopening: schema verification must
      // keep rejecting unexpected triggers. The deletion journal remains durable.
      await h.db.customStatement('DROP TRIGGER interrupted_delete');
      final root = h.root;
      await h.close();
      h = EpubManagementHarness();
      await h.open(existing: root);
      expect(await h.recovery.recover(), isEmpty);
      expect(await h.removal.remove(imported[2].key, confirmed: true), true);
      expect((await h.books.readyPage()).single.key, imported[3].key);
      expect(await h.journal.pending(), isEmpty);
      for (final entry in originals.entries) {
        expect(
          sha256
              .convert(
                await File('${root.path}/originals/${entry.key}.epub')
                    .readAsBytes(),
              )
              .toString(),
          entry.value,
        );
      }
      binding.reportData = {
        ...?binding.reportData,
        'management': {
          'queries': queryResults,
          'decisions': 5,
          'cancelled': 2,
          'interruptedRecovered': 1,
          'readyBooksRemaining': 1,
          'originalsUnchanged': 4,
          'databaseReopened': true,
          'processKilled': false,
          'productDatabaseOpened': false,
        },
      };
      await h.close();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

void main() => registerLibraryManagementTests(
  IntegrationTestWidgetsFlutterBinding.ensureInitialized(),
);
