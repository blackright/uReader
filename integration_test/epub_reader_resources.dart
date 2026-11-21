// Authorized CC0 corpus; test-only.
const readerCorpusJson = r'''{
  "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
  "books": [
    {
      "id": "epub-01",
      "sourceSha": "227a224b10f482f555dc5c3a3e5a958ca992e058406ba58b9a4e5b5fabe3f806",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjIuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZToxPC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDE8L2RjOnRpdGxlPjxkYzpjcmVhdG9yPkF1dGV1ciBzeW50aMOpdGlxdWUgdVJlYWRlcjwvZGM6Y3JlYXRvcj48ZGM6bGFuZ3VhZ2U+ZnI8L2RjOmxhbmd1YWdlPjxtZXRhIG5hbWU9ImNvdmVyIiBjb250ZW50PSJjb3ZlciIvPjwvbWV0YWRhdGE+PG1hbmlmZXN0PjxpdGVtIGlkPSJjMCIgaHJlZj0iY2hhcHRlcjEueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMSIgaHJlZj0iY2hhcHRlcjIueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMiIgaHJlZj0iY2hhcHRlcjMueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjc3MiIGhyZWY9InN0eWxlLmNzcyIgbWVkaWEtdHlwZT0idGV4dC9jc3MiLz48aXRlbSBpZD0iY292ZXIiIGhyZWY9ImNvdmVyLnBuZyIgbWVkaWEtdHlwZT0iaW1hZ2UvcG5nIi8+PGl0ZW0gaWQ9Im5jeCIgaHJlZj0idG9jLm5jeCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veC1kdGJuY3greG1sIi8+PC9tYW5pZmVzdD48c3BpbmUgdG9jPSJuY3giPjxpdGVtcmVmIGlkcmVmPSJjMCIvPjxpdGVtcmVmIGlkcmVmPSJjMSIvPjxpdGVtcmVmIGlkcmVmPSJjMiIvPjwvc3BpbmU+PC9wYWNrYWdlPg==",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48cD48aW1nIHNyYz0iY292ZXIucG5nIiBhbHQ9IkNhcnLDqSBibGV1IGRlIHLDqWbDqXJlbmNlIi8+PC9wPjwvYm9keT48L2h0bWw+",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/toc.ncx": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PG5jeCB4bWxucz0iaHR0cDovL3d3dy5kYWlzeS5vcmcvejM5ODYvMjAwNS9uY3gvIiB2ZXJzaW9uPSIyMDA1LTEiPjxoZWFkPjxtZXRhIG5hbWU9ImR0Yjp1aWQiIGNvbnRlbnQ9InVybjp1cmVhZGVyOmZpeHR1cmU6MSIvPjxtZXRhIG5hbWU9ImR0YjpkZXB0aCIgY29udGVudD0iMSIvPjxtZXRhIG5hbWU9ImR0Yjp0b3RhbFBhZ2VDb3VudCIgY29udGVudD0iMCIvPjxtZXRhIG5hbWU9ImR0YjptYXhQYWdlTnVtYmVyIiBjb250ZW50PSIwIi8+PC9oZWFkPjxkb2NUaXRsZT48dGV4dD5GaXh0dXJlIEVQVUIgMDE8L3RleHQ+PC9kb2NUaXRsZT48bmF2TWFwPjxuYXZQb2ludCBpZD0ibjAiIHBsYXlPcmRlcj0iMSI+PG5hdkxhYmVsPjx0ZXh0PkNoYXBpdHJlIDE8L3RleHQ+PC9uYXZMYWJlbD48Y29udGVudCBzcmM9ImNoYXB0ZXIxLnhodG1sI3N0YXJ0Ii8+PC9uYXZQb2ludD48bmF2UG9pbnQgaWQ9Im4xIiBwbGF5T3JkZXI9IjIiPjxuYXZMYWJlbD48dGV4dD5DaGFwaXRyZSAyPC90ZXh0PjwvbmF2TGFiZWw+PGNvbnRlbnQgc3JjPSJjaGFwdGVyMi54aHRtbCNzdGFydCIvPjwvbmF2UG9pbnQ+PG5hdlBvaW50IGlkPSJuMiIgcGxheU9yZGVyPSIzIj48bmF2TGFiZWw+PHRleHQ+Q2hhcGl0cmUgMzwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iY2hhcHRlcjMueGh0bWwjc3RhcnQiLz48L25hdlBvaW50PjwvbmF2TWFwPjwvbmN4Pg==",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-01",
        "epubVersion": 2,
        "language": "fr",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-01.epub",
        "bytes": 2695,
        "sha256": "227a224b10f482f555dc5c3a3e5a958ca992e058406ba58b9a4e5b5fabe3f806",
        "referenceSha256": "1b4f994e936473f839cadc47d965dee1552f5c2fd051444d77bbaf5baee0cf81"
      },
      "source": "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"
    },
    {
      "id": "epub-02",
      "sourceSha": "557098f617651d5945b37b95384e6d8540a054fe5c4d9c35db619bb0c7753417",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjIuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZToyPC9kYzppZGVudGlmaWVyPjxkYzpsYW5ndWFnZT5mcjwvZGM6bGFuZ3VhZ2U+PC9tZXRhZGF0YT48bWFuaWZlc3Q+PGl0ZW0gaWQ9ImMwIiBocmVmPSJjaGFwdGVyMS54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+PGl0ZW0gaWQ9ImMxIiBocmVmPSJjaGFwdGVyMi54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+PGl0ZW0gaWQ9ImMyIiBocmVmPSJjaGFwdGVyMy54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+PGl0ZW0gaWQ9ImNzcyIgaHJlZj0ic3R5bGUuY3NzIiBtZWRpYS10eXBlPSJ0ZXh0L2NzcyIvPjxpdGVtIGlkPSJuY3giIGhyZWY9InRvYy5uY3giIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3gtZHRibmN4K3htbCIvPjwvbWFuaWZlc3Q+PHNwaW5lIHRvYz0ibmN4Ij48aXRlbXJlZiBpZHJlZj0iYzAiLz48aXRlbXJlZiBpZHJlZj0iYzEiLz48aXRlbXJlZiBpZHJlZj0iYzIiLz48L3NwaW5lPjwvcGFja2FnZT4=",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/toc.ncx": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PG5jeCB4bWxucz0iaHR0cDovL3d3dy5kYWlzeS5vcmcvejM5ODYvMjAwNS9uY3gvIiB2ZXJzaW9uPSIyMDA1LTEiPjxoZWFkPjxtZXRhIG5hbWU9ImR0Yjp1aWQiIGNvbnRlbnQ9InVybjp1cmVhZGVyOmZpeHR1cmU6MiIvPjxtZXRhIG5hbWU9ImR0YjpkZXB0aCIgY29udGVudD0iMSIvPjxtZXRhIG5hbWU9ImR0Yjp0b3RhbFBhZ2VDb3VudCIgY29udGVudD0iMCIvPjxtZXRhIG5hbWU9ImR0YjptYXhQYWdlTnVtYmVyIiBjb250ZW50PSIwIi8+PC9oZWFkPjxkb2NUaXRsZT48dGV4dD5GaXh0dXJlIEVQVUIgMDI8L3RleHQ+PC9kb2NUaXRsZT48bmF2TWFwPjxuYXZQb2ludCBpZD0ibjAiIHBsYXlPcmRlcj0iMSI+PG5hdkxhYmVsPjx0ZXh0PkNoYXBpdHJlIDE8L3RleHQ+PC9uYXZMYWJlbD48Y29udGVudCBzcmM9ImNoYXB0ZXIxLnhodG1sI3N0YXJ0Ii8+PC9uYXZQb2ludD48bmF2UG9pbnQgaWQ9Im4xIiBwbGF5T3JkZXI9IjIiPjxuYXZMYWJlbD48dGV4dD5DaGFwaXRyZSAyPC90ZXh0PjwvbmF2TGFiZWw+PGNvbnRlbnQgc3JjPSJjaGFwdGVyMi54aHRtbCNzdGFydCIvPjwvbmF2UG9pbnQ+PG5hdlBvaW50IGlkPSJuMiIgcGxheU9yZGVyPSIzIj48bmF2TGFiZWw+PHRleHQ+Q2hhcGl0cmUgMzwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iY2hhcHRlcjMueGh0bWwjc3RhcnQiLz48L25hdlBvaW50PjwvbmF2TWFwPjwvbmN4Pg=="
      },
      "reference": {
        "id": "epub-02",
        "epubVersion": 2,
        "language": "fr",
        "titleAbsent": true,
        "authorAbsent": true,
        "coverAbsent": true,
        "features": [],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready_with_metadata_fallback",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-02.epub",
        "bytes": 2390,
        "sha256": "557098f617651d5945b37b95384e6d8540a054fe5c4d9c35db619bb0c7753417",
        "referenceSha256": "1b4f994e936473f839cadc47d965dee1552f5c2fd051444d77bbaf5baee0cf81"
      },
      "source": "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"
    },
    {
      "id": "epub-03",
      "sourceSha": "2221b4f77abb2e2da37d03bbf3b1cd7421f4215a75f7287cda5a283ddc535fae",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjIuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZTozPC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDM8L2RjOnRpdGxlPjxkYzpjcmVhdG9yPkF1dGV1ciBzeW50aMOpdGlxdWUgdVJlYWRlcjwvZGM6Y3JlYXRvcj48ZGM6bGFuZ3VhZ2U+ZnI8L2RjOmxhbmd1YWdlPjxtZXRhIG5hbWU9ImNvdmVyIiBjb250ZW50PSJjb3ZlciIvPjwvbWV0YWRhdGE+PG1hbmlmZXN0PjxpdGVtIGlkPSJjMCIgaHJlZj0iY2hhcHRlcjEueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMSIgaHJlZj0iY2hhcHRlcjIueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMiIgaHJlZj0iY2hhcHRlcjMueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjc3MiIGhyZWY9InN0eWxlLmNzcyIgbWVkaWEtdHlwZT0idGV4dC9jc3MiLz48aXRlbSBpZD0iY292ZXIiIGhyZWY9ImNvdmVyLnBuZyIgbWVkaWEtdHlwZT0iaW1hZ2UvcG5nIi8+PGl0ZW0gaWQ9Im5jeCIgaHJlZj0idG9jLm5jeCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veC1kdGJuY3greG1sIi8+PC9tYW5pZmVzdD48c3BpbmUgdG9jPSJuY3giPjxpdGVtcmVmIGlkcmVmPSJjMCIvPjxpdGVtcmVmIGlkcmVmPSJjMSIvPjxpdGVtcmVmIGlkcmVmPSJjMiIvPjwvc3BpbmU+PC9wYWNrYWdlPg==",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48cCBpZD0idW5pY29kZSI+Qm9uPGVtPmpvdXI8L2VtPiBMw6lhPGJyLz5BJiMxNjA7IEIgJmFtcDsgQyA6IMOpIGUmI3gzMDE7IPCfmIAuPC9wPjxwcmU+IEEgIEIKQyA8L3ByZT48cD48aW1nIHNyYz0iY292ZXIucG5nIiBhbHQ9IkNhcnLDqSBibGV1IGRlIHLDqWbDqXJlbmNlIi8+PC9wPjwvYm9keT48L2h0bWw+",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/toc.ncx": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PG5jeCB4bWxucz0iaHR0cDovL3d3dy5kYWlzeS5vcmcvejM5ODYvMjAwNS9uY3gvIiB2ZXJzaW9uPSIyMDA1LTEiPjxoZWFkPjxtZXRhIG5hbWU9ImR0Yjp1aWQiIGNvbnRlbnQ9InVybjp1cmVhZGVyOmZpeHR1cmU6MyIvPjxtZXRhIG5hbWU9ImR0YjpkZXB0aCIgY29udGVudD0iMSIvPjxtZXRhIG5hbWU9ImR0Yjp0b3RhbFBhZ2VDb3VudCIgY29udGVudD0iMCIvPjxtZXRhIG5hbWU9ImR0YjptYXhQYWdlTnVtYmVyIiBjb250ZW50PSIwIi8+PC9oZWFkPjxkb2NUaXRsZT48dGV4dD5GaXh0dXJlIEVQVUIgMDM8L3RleHQ+PC9kb2NUaXRsZT48bmF2TWFwPjxuYXZQb2ludCBpZD0ibjAiIHBsYXlPcmRlcj0iMSI+PG5hdkxhYmVsPjx0ZXh0PkNoYXBpdHJlIDE8L3RleHQ+PC9uYXZMYWJlbD48Y29udGVudCBzcmM9ImNoYXB0ZXIxLnhodG1sI3N0YXJ0Ii8+PC9uYXZQb2ludD48bmF2UG9pbnQgaWQ9Im4xIiBwbGF5T3JkZXI9IjIiPjxuYXZMYWJlbD48dGV4dD5DaGFwaXRyZSAyPC90ZXh0PjwvbmF2TGFiZWw+PGNvbnRlbnQgc3JjPSJjaGFwdGVyMi54aHRtbCNzdGFydCIvPjwvbmF2UG9pbnQ+PG5hdlBvaW50IGlkPSJuMiIgcGxheU9yZGVyPSIzIj48bmF2TGFiZWw+PHRleHQ+Q2hhcGl0cmUgMzwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iY2hhcHRlcjMueGh0bWwjc3RhcnQiLz48L25hdlBvaW50PjwvbmF2TWFwPjwvbmN4Pg==",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-03",
        "epubVersion": 2,
        "language": "fr",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [
          "inline",
          "br",
          "entities",
          "combining_unicode",
          "surrogate_pair",
          "preformatted"
        ],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [
              "Bonjour Léa\nA  B & C : é é; 😀.",
              " A  B\nC "
            ],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": " A  B\nC "
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-03.epub",
        "bytes": 2772,
        "sha256": "2221b4f77abb2e2da37d03bbf3b1cd7421f4215a75f7287cda5a283ddc535fae",
        "referenceSha256": "e487a72a82b445bd51d196f637ca83b8c8342ebfe002cd43f25cbee5171a8082"
      },
      "source": "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"
    },
    {
      "id": "epub-04",
      "sourceSha": "fc8fa31eb1b0f2ed5829f172297e0c0053ab9c12ebcd2fd83fec1cf35b9702f1",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjIuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZTo0PC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDQ8L2RjOnRpdGxlPjxkYzpjcmVhdG9yPkF1dGV1ciBzeW50aMOpdGlxdWUgdVJlYWRlcjwvZGM6Y3JlYXRvcj48ZGM6bGFuZ3VhZ2U+ZnI8L2RjOmxhbmd1YWdlPjxtZXRhIG5hbWU9ImNvdmVyIiBjb250ZW50PSJjb3ZlciIvPjwvbWV0YWRhdGE+PG1hbmlmZXN0PjxpdGVtIGlkPSJjMCIgaHJlZj0iY2hhcHRlcjEueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMSIgaHJlZj0iY2hhcHRlcjIueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMiIgaHJlZj0iY2hhcHRlcjMueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjc3MiIGhyZWY9InN0eWxlLmNzcyIgbWVkaWEtdHlwZT0idGV4dC9jc3MiLz48aXRlbSBpZD0iY292ZXIiIGhyZWY9ImNvdmVyLnBuZyIgbWVkaWEtdHlwZT0iaW1hZ2UvcG5nIi8+PGl0ZW0gaWQ9Im5jeCIgaHJlZj0idG9jLm5jeCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veC1kdGJuY3greG1sIi8+PC9tYW5pZmVzdD48c3BpbmUgdG9jPSJuY3giPjxpdGVtcmVmIGlkcmVmPSJjMCIvPjxpdGVtcmVmIGlkcmVmPSJjMSIvPjxpdGVtcmVmIGlkcmVmPSJjMiIvPjwvc3BpbmU+PC9wYWNrYWdlPg==",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48cCBjbGFzcz0iaGlkZGVuIj5ORSBQQVMgQUZGSUNIRVIgTkkgTElSRS48L3A+PHAgaGlkZGVuPSJoaWRkZW4iPk1BU1FVw4kuPC9wPjxwIHN0eWxlPSJ2aXNpYmlsaXR5OmhpZGRlbiI+TUFTUVXDiSBBVVNTSS48L3A+PHA+PGltZyBzcmM9ImNvdmVyLnBuZyIgYWx0PSJDYXJyw6kgYmxldSBkZSByw6lmw6lyZW5jZSIvPjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/toc.ncx": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PG5jeCB4bWxucz0iaHR0cDovL3d3dy5kYWlzeS5vcmcvejM5ODYvMjAwNS9uY3gvIiB2ZXJzaW9uPSIyMDA1LTEiPjxoZWFkPjxtZXRhIG5hbWU9ImR0Yjp1aWQiIGNvbnRlbnQ9InVybjp1cmVhZGVyOmZpeHR1cmU6NCIvPjxtZXRhIG5hbWU9ImR0YjpkZXB0aCIgY29udGVudD0iMSIvPjxtZXRhIG5hbWU9ImR0Yjp0b3RhbFBhZ2VDb3VudCIgY29udGVudD0iMCIvPjxtZXRhIG5hbWU9ImR0YjptYXhQYWdlTnVtYmVyIiBjb250ZW50PSIwIi8+PC9oZWFkPjxkb2NUaXRsZT48dGV4dD5GaXh0dXJlIEVQVUIgMDQ8L3RleHQ+PC9kb2NUaXRsZT48bmF2TWFwPjxuYXZQb2ludCBpZD0ibjAiIHBsYXlPcmRlcj0iMSI+PG5hdkxhYmVsPjx0ZXh0PkNoYXBpdHJlIDE8L3RleHQ+PC9uYXZMYWJlbD48Y29udGVudCBzcmM9ImNoYXB0ZXIxLnhodG1sI3N0YXJ0Ii8+PC9uYXZQb2ludD48bmF2UG9pbnQgaWQ9Im4xIiBwbGF5T3JkZXI9IjIiPjxuYXZMYWJlbD48dGV4dD5DaGFwaXRyZSAyPC90ZXh0PjwvbmF2TGFiZWw+PGNvbnRlbnQgc3JjPSJjaGFwdGVyMi54aHRtbCNzdGFydCIvPjwvbmF2UG9pbnQ+PG5hdlBvaW50IGlkPSJuMiIgcGxheU9yZGVyPSIzIj48bmF2TGFiZWw+PHRleHQ+Q2hhcGl0cmUgMzwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iY2hhcHRlcjMueGh0bWwjc3RhcnQiLz48L25hdlBvaW50PjwvbmF2TWFwPjwvbmN4Pg==",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-04",
        "epubVersion": 2,
        "language": "fr",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [
          "css_visibility",
          "hidden_attribute"
        ],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-04.epub",
        "bytes": 2769,
        "sha256": "fc8fa31eb1b0f2ed5829f172297e0c0053ab9c12ebcd2fd83fec1cf35b9702f1",
        "referenceSha256": "1b4f994e936473f839cadc47d965dee1552f5c2fd051444d77bbaf5baee0cf81"
      },
      "source": "UEsDBBQAAAAAAAAAbl1vYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAACAAAAG5d2DW9ZZkAAADdAAAAFgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWxVjkEOwiAQRa/SsDUtuiWAiYlrTTzBSKdKhBkC1OjtRRdVd5P8/94fvX3E0N0xF89kxGZYi63VjqmCJ8xdS6kYMWdSDMUXRRCxqOoUJ6SR3RyRqvrU1IKJf6PVmblOPmD5nt00h9AnqFcjDvvd8STfeJMNnCbRRRw99PWZ0AhIKXgHtQkl4zmVhrkbXHDVdoW0Wv745fKFfQFQSwMEFAAAAAgAAABuXYojnlyPAQAAiwMAABEAAABPRUJQUy9jb250ZW50Lm9wZp2TX26cMBDGr2LxWi0GUqkSYolaqX2OIvUAjj0sVsB27XGWPVLP0Yt1sEPYjdqXPOH58/1m/Fl098s8sRfwQVtzLOqyKu77zgn5LE7AqGbCsRgRXcv5+XwutXJDaf2JN1X1hVs3FLu4ITGLRv+KcNAKDOpBgz8WT9Y+a1X03QwolECRua2Sb2gX/ZSwSnKYYCZx4HVZc1Ip2e40ptUOjN600YNQ4NtBL0jn9nPHbwRJjxon6H/kFvb94ec3VuXGXFl7JIHQ+v5rRIiehYvB8c9vXG/D4mMakhRb36qZhDlFMqofcu0tTldlRsxwLKQlhwomrUFaaot53/HND2oXRg8QsO80wpwuKcnM0cNAp1E4BF+Xy4jzVLAZlBYHvDiCC+cmLQXSA/BU/kTervCdU7/jNB/kNO84dx/khLCBAl4mKFPimoGwIF+zN7Ls4usGa1A6c7oV6pm852v6WmnksunQyjKF/135oPCJOrat+f4wwWkDjAiZmAcQlWbknapt6nWy/leySegEpO/rz9b/BVBLAwQUAAAACAAAAG5diC6RhzAAAAAzAAAADwAAAE9FQlBTL3N0eWxlLmNzc0vKT6lUqFZIzs/JL7JSUDYyAEFrhVoFvYzMlJTUPKBcSmZxQU5ipZVCXn5eKlAKAFBLAwQUAAAACAAAAG5diDShcE0BAADwAQAAFAAAAE9FQlBTL2NoYXB0ZXIxLnhodG1sXdFdbsIwDADgq1h+X7NqLwOlQQhRDYmhDcYBQmvabKGtEpefI+wonIOLLaWwSXtL4s+ObMvRcWdhT86bukowjh4RqMrq3FRFguuP9OEZR0qWHFSQlU+wZG6GQhwOh+jwFNWuEPFgMBDHzmCHhlZ3yVuHIZF0riQbtqRSc+TWkRT9VVpTfYEjm6DnkyVfEjECnxpKkOnIIvMeoXS0vYmoexBKir7qps5P4YcYTN4B7RjVpNSNYUcQBxUr2VyDjfZeF4RqfjlrqNt9AJYg+8VADL413L/SzlSQt/CpXZhDJEXTFcpsqBLaN3lOFarFFN7GKxin6WzyMl3CYgbz2XJ61z3746/j1fv68n0PX/tJcG+82Rhr+DT8B2G8Xq1mN66k2RXgXZZgVodlRU1VIGjLCU60c5czbCy1kBOE8/ZydmGFdJ1USBX9nES3H/UDUEsDBBQAAAAIAAAAbl3jvWml3gAAADYBAAAUAAAAT0VCUFMvY2hhcHRlcjIueGh0bWw90MFSxCAMBuBXyeRuse7F7gB7cGZPHtcHwJJtUZYykG7bR/I5fDHBOh4JX/JPIk/rzcOdUnZTUNg2jwgU+sm6MCh8u5wfnvGk5chFFRmywpE5HoVYlqVZDs2UBtF2XSfWarCioze1+ZqwNJKxWrJjT/rsVp4TSbE/pXfhExJ5hZk3T3kkYgTeIilkWln0OSOMia5/oqkFoaXYp75PdisJLThbgUmM+mU00XEieCqq1TL+fkaTsxkI9ev3l4FpvhfgCfp/DMSQZ8d7lW4ugJ3hw6Ryh0aKWDL3NFG31D9QSwMEFAAAAAgAAABuXSZLFsneAAAANgEAABQAAABPRUJQUy9jaGFwdGVyMy54aHRtbD3QwW7DIAwG4FexfF9Y1EtTAT1M6mnH7gFYcBM2ShA4TfJIe4692GCZdsR89i9bnte7hwel7KagsG2eESj0k3VhUPh2vTwd8azlyEUVGbLCkTmehFiWpVkOzZQG0XZdJ9ZqsKKTN7X5lrA0krFasmNP+uJWnhNJsT+ld+ETEnmFmTdPeSRiBN4iKWRaWfQ5I4yJbn+iqQWhpdinvk92KwktOFuBSYz6ZTTRcSI4FNVqGX8/o8nZDIT69fvLwDQ/CvAE/T8GYsiz471KdxfAzvBhUrlDI0UsmXuaqFvqH1BLAwQUAAAACAAAAG5dIZoCRCsBAADUAgAADQAAAE9FQlBTL3RvYy5uY3iNkstugzAQRX/FctfFPNKqRYZIjdpVH1m0H2DwNFgCG5khIf36GpI0j0aIla3xmTnXlvm8q0qyBtsooxMaeD6dp1znHXF13SS0QKxjxjabjSeFaraesSv2Ez0+3LPQ9++YQxk9DuhrtwFNeQFCprwCFESLChIqMYtbJSnJjUbQmNDW6ri1jgMbf6sO3T6eUfavS0KNxUlfcIVBg6JcihUsTKvxBPavwJXoevS9rTKwlyzbJZcm/1RYQsoROkxfdvnI8/LrifgzzoYqZ0dMi/WbqId1aZRGomRCtU9JXYrth3WX7JMP568ig3I/eFGIWqGbHPzNPBL7ZKSxeUJzRyLYwOsKrMqbBoXFIfDBeOkOztzhiDuc6A4nu8MzdzTijia6oxE3Ozx+/x3TX1BLAwQUAAAACAAAAG5dDcZF8EMAAABJAAAADwAAAE9FQlBTL2NvdmVyLnBuZ+sM8HPn5ZLiYmBg4PX0cAkC0kwgzAEi/16ZVQykBDxdHEMq5iQHeEQwuPAIcDHI9rE0Or6fHgeUY/B09XNZ55TQBABQSwECFAMUAAAAAAAAAG5db2GrLBQAAAAUAAAACAAAAAAAAAAAAAAAgIEAAAAAbWltZXR5cGVQSwECFAMUAAAACAAAAG5d2DW9ZZkAAADdAAAAFgAAAAAAAAAAAAAAgIE6AAAATUVUQS1JTkYvY29udGFpbmVyLnhtbFBLAQIUAxQAAAAIAAAAbl2KI55cjwEAAIsDAAARAAAAAAAAAAAAAACAgQcBAABPRUJQUy9jb250ZW50Lm9wZlBLAQIUAxQAAAAIAAAAbl2ILpGHMAAAADMAAAAPAAAAAAAAAAAAAACAgcUCAABPRUJQUy9zdHlsZS5jc3NQSwECFAMUAAAACAAAAG5diDShcE0BAADwAQAAFAAAAAAAAAAAAAAAgIEiAwAAT0VCUFMvY2hhcHRlcjEueGh0bWxQSwECFAMUAAAACAAAAG5d471ppd4AAAA2AQAAFAAAAAAAAAAAAAAAgIGhBAAAT0VCUFMvY2hhcHRlcjIueGh0bWxQSwECFAMUAAAACAAAAG5dJksWyd4AAAA2AQAAFAAAAAAAAAAAAAAAgIGxBQAAT0VCUFMvY2hhcHRlcjMueGh0bWxQSwECFAMUAAAACAAAAG5dIZoCRCsBAADUAgAADQAAAAAAAAAAAAAAgIHBBgAAT0VCUFMvdG9jLm5jeFBLAQIUAxQAAAAIAAAAbl0NxkXwQwAAAEkAAAAPAAAAAAAAAAAAAACAgRcIAABPRUJQUy9jb3Zlci5wbmdQSwUGAAAAAAkACQA0AgAAhwgAAAAA"
    },
    {
      "id": "epub-05",
      "sourceSha": "d00f448dc43e6f283185c0310badca453cd5e758934d73922b48cf2935aa9f11",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjIuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZTo1PC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDU8L2RjOnRpdGxlPjxkYzpjcmVhdG9yPkF1dGV1ciBzeW50aMOpdGlxdWUgdVJlYWRlcjwvZGM6Y3JlYXRvcj48ZGM6bGFuZ3VhZ2U+ZW48L2RjOmxhbmd1YWdlPjxtZXRhIG5hbWU9ImNvdmVyIiBjb250ZW50PSJjb3ZlciIvPjwvbWV0YWRhdGE+PG1hbmlmZXN0PjxpdGVtIGlkPSJjMCIgaHJlZj0iY2hhcHRlcjEueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMSIgaHJlZj0iY2hhcHRlcjIueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMiIgaHJlZj0iY2hhcHRlcjMueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjc3MiIGhyZWY9InN0eWxlLmNzcyIgbWVkaWEtdHlwZT0idGV4dC9jc3MiLz48aXRlbSBpZD0iY292ZXIiIGhyZWY9ImNvdmVyLnBuZyIgbWVkaWEtdHlwZT0iaW1hZ2UvcG5nIi8+PGl0ZW0gaWQ9Im5jeCIgaHJlZj0idG9jLm5jeCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veC1kdGJuY3greG1sIi8+PC9tYW5pZmVzdD48c3BpbmUgdG9jPSJuY3giPjxpdGVtcmVmIGlkcmVmPSJjMCIvPjxpdGVtcmVmIGlkcmVmPSJjMSIvPjxpdGVtcmVmIGlkcmVmPSJjMiIvPjwvc3BpbmU+PC9wYWNrYWdlPg==",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImVuIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXB0ZXIgMTwvaDE+PHAgaWQ9InBhc3NhZ2UiPlRoZSByZWFkZXIgb3BlbnMgY2hhcHRlciAxIGFuZCBmb2xsb3dzIHRoZSBnYXJkZW4gcGF0aC48L3A+PHA+PGltZyBzcmM9ImNvdmVyLnBuZyIgYWx0PSJDYXJyw6kgYmxldSBkZSByw6lmw6lyZW5jZSIvPjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImVuIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXB0ZXIgMjwvaDE+PHAgaWQ9InBhc3NhZ2UiPlRoZSByZWFkZXIgb3BlbnMgY2hhcHRlciAyIGFuZCBmb2xsb3dzIHRoZSBnYXJkZW4gcGF0aC48L3A+PC9ib2R5PjwvaHRtbD4=",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImVuIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXB0ZXIgMzwvaDE+PHAgaWQ9InBhc3NhZ2UiPlRoZSByZWFkZXIgb3BlbnMgY2hhcHRlciAzIGFuZCBmb2xsb3dzIHRoZSBnYXJkZW4gcGF0aC48L3A+PC9ib2R5PjwvaHRtbD4=",
        "OEBPS/toc.ncx": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PG5jeCB4bWxucz0iaHR0cDovL3d3dy5kYWlzeS5vcmcvejM5ODYvMjAwNS9uY3gvIiB2ZXJzaW9uPSIyMDA1LTEiPjxoZWFkPjxtZXRhIG5hbWU9ImR0Yjp1aWQiIGNvbnRlbnQ9InVybjp1cmVhZGVyOmZpeHR1cmU6NSIvPjxtZXRhIG5hbWU9ImR0YjpkZXB0aCIgY29udGVudD0iMSIvPjxtZXRhIG5hbWU9ImR0Yjp0b3RhbFBhZ2VDb3VudCIgY29udGVudD0iMCIvPjxtZXRhIG5hbWU9ImR0YjptYXhQYWdlTnVtYmVyIiBjb250ZW50PSIwIi8+PC9oZWFkPjxkb2NUaXRsZT48dGV4dD5GaXh0dXJlIEVQVUIgMDU8L3RleHQ+PC9kb2NUaXRsZT48bmF2TWFwPjxuYXZQb2ludCBpZD0ibjAiIHBsYXlPcmRlcj0iMSI+PG5hdkxhYmVsPjx0ZXh0PkNoYXB0ZXIgMTwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iY2hhcHRlcjEueGh0bWwjc3RhcnQiLz48L25hdlBvaW50PjxuYXZQb2ludCBpZD0ibjEiIHBsYXlPcmRlcj0iMiI+PG5hdkxhYmVsPjx0ZXh0PkNoYXB0ZXIgMjwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iY2hhcHRlcjIueGh0bWwjc3RhcnQiLz48L25hdlBvaW50PjxuYXZQb2ludCBpZD0ibjIiIHBsYXlPcmRlcj0iMyI+PG5hdkxhYmVsPjx0ZXh0PkNoYXB0ZXIgMzwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iY2hhcHRlcjMueGh0bWwjc3RhcnQiLz48L25hdlBvaW50PjwvbmF2TWFwPjwvbmN4Pg==",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-05",
        "epubVersion": 2,
        "language": "en",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapter 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapter 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "The reader opens chapter 1 and follows the garden path."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "The reader opens chapter 1 and follows the garden path."
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapter 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapter 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "The reader opens chapter 2 and follows the garden path."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "The reader opens chapter 2 and follows the garden path."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapter 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapter 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "The reader opens chapter 3 and follows the garden path."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "The reader opens chapter 3 and follows the garden path."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-05.epub",
        "bytes": 2686,
        "sha256": "d00f448dc43e6f283185c0310badca453cd5e758934d73922b48cf2935aa9f11",
        "referenceSha256": "62d7e1946dd55025e4a31613342b4e530a75e737e3a5b80d3f91fc8f67acf623"
      },
      "source": "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"
    },
    {
      "id": "epub-06",
      "sourceSha": "098693857e2325ce50ea5d6b724c9cf6b91332f887a1d6935427ff83e11aff43",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjMuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZTo2PC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDY8L2RjOnRpdGxlPjxkYzpjcmVhdG9yPkF1dGV1ciBzeW50aMOpdGlxdWUgdVJlYWRlcjwvZGM6Y3JlYXRvcj48ZGM6bGFuZ3VhZ2U+ZnI8L2RjOmxhbmd1YWdlPjxtZXRhIHByb3BlcnR5PSJkY3Rlcm1zOm1vZGlmaWVkIj4yMDI2LTExLTE0VDAwOjAwOjAwWjwvbWV0YT48bWV0YSBuYW1lPSJjb3ZlciIgY29udGVudD0iY292ZXIiLz48L21ldGFkYXRhPjxtYW5pZmVzdD48aXRlbSBpZD0iYzAiIGhyZWY9ImNoYXB0ZXIxLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzEiIGhyZWY9ImNoYXB0ZXIyLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzIiIGhyZWY9ImNoYXB0ZXIzLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iY3NzIiBocmVmPSJzdHlsZS5jc3MiIG1lZGlhLXR5cGU9InRleHQvY3NzIi8+PGl0ZW0gaWQ9ImNvdmVyIiBocmVmPSJjb3Zlci5wbmciIG1lZGlhLXR5cGU9ImltYWdlL3BuZyIgcHJvcGVydGllcz0iY292ZXItaW1hZ2UiLz48aXRlbSBpZD0ibmF2IiBocmVmPSJuYXYueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIgcHJvcGVydGllcz0ibmF2Ii8+PC9tYW5pZmVzdD48c3BpbmU+PGl0ZW1yZWYgaWRyZWY9ImMwIi8+PGl0ZW1yZWYgaWRyZWY9ImMxIi8+PGl0ZW1yZWYgaWRyZWY9ImMyIi8+PC9zcGluZT48L3BhY2thZ2U+",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48cD5VbmUgY2l0YXRpb24gPGEgaHJlZj0iY2hhcHRlcjIueGh0bWwjcGFzc2FnZSI+aW50ZXJuZTwvYT4uPC9wPjxibG9ja3F1b3RlPjxwPkxlIGphcmRpbiByZXN0ZSBvdXZlcnQuPC9wPjwvYmxvY2txdW90ZT48dWw+PGxpPlVuZSBwb21tZTwvbGk+PGxpPkRldXggcG9pcmVzPC9saT48L3VsPjxwPjxpbWcgc3JjPSJjb3Zlci5wbmciIGFsdD0iQ2FycsOpIGJsZXUgZGUgcsOpZsOpcmVuY2UiLz48L3A+PC9ib2R5PjwvaHRtbD4=",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/nav.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxuYXYgeG1sbnM6ZXB1Yj0iaHR0cDovL3d3dy5pZHBmLm9yZy8yMDA3L29wcyIgZXB1Yjp0eXBlPSJ0b2MiPjxvbD48bGk+PGEgaHJlZj0iY2hhcHRlcjEueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDE8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjIueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDI8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjMueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDM8L2E+PC9saT48L29sPjwvbmF2PjwvYm9keT48L2h0bWw+",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-06",
        "epubVersion": 3,
        "language": "fr",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [
          "internal_link",
          "blockquote",
          "list"
        ],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [
              "Une citation interne.",
              "Le jardin reste ouvert.",
              "Une pomme",
              "Deux poires"
            ],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Deux poires"
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-06.epub",
        "bytes": 2764,
        "sha256": "098693857e2325ce50ea5d6b724c9cf6b91332f887a1d6935427ff83e11aff43",
        "referenceSha256": "2437ebc28e21b1f5c9761b331d3bb17614324c267018ab81c1d891f0a7437620"
      },
      "source": "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"
    },
    {
      "id": "epub-07",
      "sourceSha": "c864a1dd2158ef5ae835f672554464952c214fc89ffb45390505548e6dc582a5",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjMuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZTo3PC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDc8L2RjOnRpdGxlPjxkYzpsYW5ndWFnZT5mcjwvZGM6bGFuZ3VhZ2U+PG1ldGEgcHJvcGVydHk9ImRjdGVybXM6bW9kaWZpZWQiPjIwMjYtMTEtMTRUMDA6MDA6MDBaPC9tZXRhPjwvbWV0YWRhdGE+PG1hbmlmZXN0PjxpdGVtIGlkPSJjMCIgaHJlZj0iY2hhcHRlcjEueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMSIgaHJlZj0iY2hhcHRlcjIueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjMiIgaHJlZj0iY2hhcHRlcjMueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIvPjxpdGVtIGlkPSJjc3MiIGhyZWY9InN0eWxlLmNzcyIgbWVkaWEtdHlwZT0idGV4dC9jc3MiLz48aXRlbSBpZD0ibmF2IiBocmVmPSJuYXYueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIgcHJvcGVydGllcz0ibmF2Ii8+PC9tYW5pZmVzdD48c3BpbmU+PGl0ZW1yZWYgaWRyZWY9ImMwIi8+PGl0ZW1yZWYgaWRyZWY9ImMxIi8+PGl0ZW1yZWYgaWRyZWY9ImMyIi8+PC9zcGluZT48L3BhY2thZ2U+",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48cD5MZSB0ZXh0ZSBwcmluY2lwYWwgY29udGludWUuPC9wPjxhc2lkZSBlcHViOnR5cGU9ImZvb3Rub3RlIiBpZD0ibm90ZSIgeG1sbnM6ZXB1Yj0iaHR0cDovL3d3dy5pZHBmLm9yZy8yMDA3L29wcyI+PHA+Tm90ZSBjb25zdWx0YWJsZS48L3A+PC9hc2lkZT48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/nav.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxuYXYgeG1sbnM6ZXB1Yj0iaHR0cDovL3d3dy5pZHBmLm9yZy8yMDA3L29wcyIgZXB1Yjp0eXBlPSJ0b2MiPjxvbD48bGk+PGEgaHJlZj0iY2hhcHRlcjEueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDE8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjIueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDI8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjMueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDM8L2E+PC9saT48L29sPjwvbmF2PjwvYm9keT48L2h0bWw+"
      },
      "reference": {
        "id": "epub-07",
        "epubVersion": 3,
        "language": "fr",
        "titleAbsent": false,
        "authorAbsent": true,
        "coverAbsent": true,
        "features": [
          "identified_footnote_excluded_from_narration"
        ],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [
              "Le texte principal continue."
            ],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Le texte principal continue."
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready_with_metadata_fallback",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-07.epub",
        "bytes": 2476,
        "sha256": "c864a1dd2158ef5ae835f672554464952c214fc89ffb45390505548e6dc582a5",
        "referenceSha256": "c5e4f783168839d3268b55de80a877be85bdbf86ead9ac4f051a77b8df441c1e"
      },
      "source": "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"
    },
    {
      "id": "epub-08",
      "sourceSha": "1918619804d566c0bbdec712a0107cfb29383536399186ad8577f572fbc42353",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjMuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZTo4PC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDg8L2RjOnRpdGxlPjxkYzpjcmVhdG9yPkF1dGV1ciBzeW50aMOpdGlxdWUgdVJlYWRlcjwvZGM6Y3JlYXRvcj48ZGM6bGFuZ3VhZ2U+ZnI8L2RjOmxhbmd1YWdlPjxtZXRhIHByb3BlcnR5PSJkY3Rlcm1zOm1vZGlmaWVkIj4yMDI2LTExLTE0VDAwOjAwOjAwWjwvbWV0YT48bWV0YSBuYW1lPSJjb3ZlciIgY29udGVudD0iY292ZXIiLz48L21ldGFkYXRhPjxtYW5pZmVzdD48aXRlbSBpZD0iYzAiIGhyZWY9ImNoYXB0ZXIxLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzEiIGhyZWY9ImNoYXB0ZXIyLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzIiIGhyZWY9ImNoYXB0ZXIzLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iY3NzIiBocmVmPSJzdHlsZS5jc3MiIG1lZGlhLXR5cGU9InRleHQvY3NzIi8+PGl0ZW0gaWQ9ImNvdmVyIiBocmVmPSJjb3Zlci5wbmciIG1lZGlhLXR5cGU9ImltYWdlL3BuZyIgcHJvcGVydGllcz0iY292ZXItaW1hZ2UiLz48aXRlbSBpZD0ibmF2IiBocmVmPSJuYXYueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIgcHJvcGVydGllcz0ibmF2Ii8+PC9tYW5pZmVzdD48c3BpbmU+PGl0ZW1yZWYgaWRyZWY9ImMwIi8+PGl0ZW1yZWYgaWRyZWY9ImMxIi8+PGl0ZW1yZWYgaWRyZWY9ImMyIi8+PC9zcGluZT48L3BhY2thZ2U+",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48dGFibGU+PHRyPjx0aD5GcnVpdDwvdGg+PHRoPk5vbWJyZTwvdGg+PC90cj48dHI+PHRkPlBvbW1lPC90ZD48dGQ+VHJvaXM8L3RkPjwvdHI+PC90YWJsZT48cD48YSBocmVmPSJodHRwczovL2V4YW1wbGUub3JnLyI+TGllbiBleHRlcm5lPC9hPjwvcD48cD48aW1nIHNyYz0iY292ZXIucG5nIiBhbHQ9IkNhcnLDqSBibGV1IGRlIHLDqWbDqXJlbmNlIi8+PC9wPjwvYm9keT48L2h0bWw+",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/nav.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxuYXYgeG1sbnM6ZXB1Yj0iaHR0cDovL3d3dy5pZHBmLm9yZy8yMDA3L29wcyIgZXB1Yjp0eXBlPSJ0b2MiPjxvbD48bGk+PGEgaHJlZj0iY2hhcHRlcjEueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDE8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjIueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDI8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjMueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDM8L2E+PC9saT48L29sPjwvbmF2PjwvYm9keT48L2h0bWw+",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-08",
        "epubVersion": 3,
        "language": "fr",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [
          "table",
          "external_https_confirmation"
        ],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [
              "Lien externe"
            ],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Lien externe"
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-08.epub",
        "bytes": 2759,
        "sha256": "1918619804d566c0bbdec712a0107cfb29383536399186ad8577f572fbc42353",
        "referenceSha256": "0b1e3bbcffdd6bb1097aab83efea38daa20348bdaa6f644d5aa08690325eedd5"
      },
      "source": "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"
    },
    {
      "id": "epub-09",
      "sourceSha": "e51df04398059b2206d82001eca6ebdb57afc48199366ae9497f369f074158bf",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjMuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZTo5PC9kYzppZGVudGlmaWVyPjxkYzp0aXRsZT5GaXh0dXJlIEVQVUIgMDk8L2RjOnRpdGxlPjxkYzpjcmVhdG9yPkF1dGV1ciBzeW50aMOpdGlxdWUgdVJlYWRlcjwvZGM6Y3JlYXRvcj48ZGM6bGFuZ3VhZ2U+ZnI8L2RjOmxhbmd1YWdlPjxtZXRhIHByb3BlcnR5PSJkY3Rlcm1zOm1vZGlmaWVkIj4yMDI2LTExLTE0VDAwOjAwOjAwWjwvbWV0YT48bWV0YSBuYW1lPSJjb3ZlciIgY29udGVudD0iY292ZXIiLz48L21ldGFkYXRhPjxtYW5pZmVzdD48aXRlbSBpZD0iYzAiIGhyZWY9ImNoYXB0ZXIxLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzEiIGhyZWY9ImNoYXB0ZXIyLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzIiIGhyZWY9ImNoYXB0ZXIzLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iY3NzIiBocmVmPSJzdHlsZS5jc3MiIG1lZGlhLXR5cGU9InRleHQvY3NzIi8+PGl0ZW0gaWQ9ImNvdmVyIiBocmVmPSJjb3Zlci5wbmciIG1lZGlhLXR5cGU9ImltYWdlL3BuZyIgcHJvcGVydGllcz0iY292ZXItaW1hZ2UiLz48aXRlbSBpZD0ibmF2IiBocmVmPSJuYXYueGh0bWwiIG1lZGlhLXR5cGU9ImFwcGxpY2F0aW9uL3hodG1sK3htbCIgcHJvcGVydGllcz0ibmF2Ii8+PC9tYW5pZmVzdD48c3BpbmU+PGl0ZW1yZWYgaWRyZWY9ImMwIi8+PGl0ZW1yZWYgaWRyZWY9ImMxIi8+PGl0ZW1yZWYgaWRyZWY9ImMyIi8+PC9zcGluZT48L3BhY2thZ2U+",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDE8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDEgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48cCBpZD0ibG9uZyI+w6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nDqcOpw6nwn5iAIGZpbi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAyLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMy48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDQuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA1LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDcuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA4LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gOS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMTEuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAxMi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEzLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMTQuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAxNS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDE2LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMTcuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAxOC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDE5LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMjAuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAyMS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDIyLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMjMuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAyNC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDI1LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMjYuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAyNy48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDI4LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMjkuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAzMC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDMxLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMzIuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAzMy48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDM0LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMzUuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAzNi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDM3LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gMzguPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyAzOS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDQwLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNDEuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA0Mi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDQzLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNDQuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA0NS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDQ2LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNDcuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA0OC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDQ5LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNTAuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA1MS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDUyLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNTMuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA1NC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDU1LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNTYuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA1Ny48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDU4LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNTkuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA2MC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDYxLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNjIuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA2My48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDY0LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNjUuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA2Ni48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDY3LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNjguPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA2OS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDcwLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNzEuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA3Mi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDczLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNzQuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA3NS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDc2LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gNzcuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA3OC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDc5LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gODAuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA4MS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDgyLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gODMuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA4NC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDg1LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gODYuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA4Ny48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDg4LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gODkuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA5MC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDkxLjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gOTIuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA5My48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDk0LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gOTUuPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA5Ni48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDk3LjwvcD48cD5QYXJhZ3JhcGhlIGRlIGNvbnRpbnVpdMOpIG51bcOpcm8gOTguPC9wPjxwPlBhcmFncmFwaGUgZGUgY29udGludWl0w6kgbnVtw6lybyA5OS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwMC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwMS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwMi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwMy48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwNC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwNS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwNi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwNy48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwOC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEwOS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExMC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExMS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExMi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExMy48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExNC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExNS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExNi48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExNy48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExOC48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDExOS48L3A+PHA+UGFyYWdyYXBoZSBkZSBjb250aW51aXTDqSBudW3DqXJvIDEyMC48L3A+PHA+PGltZyBzcmM9ImNvdmVyLnBuZyIgYWx0PSJDYXJyw6kgYmxldSBkZSByw6lmw6lyZW5jZSIvPjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDI8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDIgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXBpdHJlIDM8L2gxPjxwIGlkPSJwYXNzYWdlIj5Mw6lhIG91dnJlIGxlIGNoYXBpdHJlIDMgZXQgc3VpdCBsZSBjaGVtaW4gZHUgamFyZGluLjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/nav.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImZyIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxuYXYgeG1sbnM6ZXB1Yj0iaHR0cDovL3d3dy5pZHBmLm9yZy8yMDA3L29wcyIgZXB1Yjp0eXBlPSJ0b2MiPjxvbD48bGk+PGEgaHJlZj0iY2hhcHRlcjEueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDE8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjIueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDI8L2E+PC9saT48bGk+PGEgaHJlZj0iY2hhcHRlcjMueGh0bWwjc3RhcnQiPkNoYXBpdHJlIDM8L2E+PC9saT48L29sPjwvbmF2PjwvYm9keT48L2h0bWw+",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-09",
        "epubVersion": 3,
        "language": "fr",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [
          "long_chapter",
          "block_split_8192_utf16",
          "window_boundary_64_blocks"
        ],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapitre 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapitre 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "Léa ouvre le chapitre 1 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [
              "ééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé😀 fin.",
              "Paragraphe de continuité numéro 1.",
              "Paragraphe de continuité numéro 2.",
              "Paragraphe de continuité numéro 3.",
              "Paragraphe de continuité numéro 4.",
              "Paragraphe de continuité numéro 5.",
              "Paragraphe de continuité numéro 6.",
              "Paragraphe de continuité numéro 7.",
              "Paragraphe de continuité numéro 8.",
              "Paragraphe de continuité numéro 9.",
              "Paragraphe de continuité numéro 10.",
              "Paragraphe de continuité numéro 11.",
              "Paragraphe de continuité numéro 12.",
              "Paragraphe de continuité numéro 13.",
              "Paragraphe de continuité numéro 14.",
              "Paragraphe de continuité numéro 15.",
              "Paragraphe de continuité numéro 16.",
              "Paragraphe de continuité numéro 17.",
              "Paragraphe de continuité numéro 18.",
              "Paragraphe de continuité numéro 19.",
              "Paragraphe de continuité numéro 20.",
              "Paragraphe de continuité numéro 21.",
              "Paragraphe de continuité numéro 22.",
              "Paragraphe de continuité numéro 23.",
              "Paragraphe de continuité numéro 24.",
              "Paragraphe de continuité numéro 25.",
              "Paragraphe de continuité numéro 26.",
              "Paragraphe de continuité numéro 27.",
              "Paragraphe de continuité numéro 28.",
              "Paragraphe de continuité numéro 29.",
              "Paragraphe de continuité numéro 30.",
              "Paragraphe de continuité numéro 31.",
              "Paragraphe de continuité numéro 32.",
              "Paragraphe de continuité numéro 33.",
              "Paragraphe de continuité numéro 34.",
              "Paragraphe de continuité numéro 35.",
              "Paragraphe de continuité numéro 36.",
              "Paragraphe de continuité numéro 37.",
              "Paragraphe de continuité numéro 38.",
              "Paragraphe de continuité numéro 39.",
              "Paragraphe de continuité numéro 40.",
              "Paragraphe de continuité numéro 41.",
              "Paragraphe de continuité numéro 42.",
              "Paragraphe de continuité numéro 43.",
              "Paragraphe de continuité numéro 44.",
              "Paragraphe de continuité numéro 45.",
              "Paragraphe de continuité numéro 46.",
              "Paragraphe de continuité numéro 47.",
              "Paragraphe de continuité numéro 48.",
              "Paragraphe de continuité numéro 49.",
              "Paragraphe de continuité numéro 50.",
              "Paragraphe de continuité numéro 51.",
              "Paragraphe de continuité numéro 52.",
              "Paragraphe de continuité numéro 53.",
              "Paragraphe de continuité numéro 54.",
              "Paragraphe de continuité numéro 55.",
              "Paragraphe de continuité numéro 56.",
              "Paragraphe de continuité numéro 57.",
              "Paragraphe de continuité numéro 58.",
              "Paragraphe de continuité numéro 59.",
              "Paragraphe de continuité numéro 60.",
              "Paragraphe de continuité numéro 61.",
              "Paragraphe de continuité numéro 62.",
              "Paragraphe de continuité numéro 63.",
              "Paragraphe de continuité numéro 64.",
              "Paragraphe de continuité numéro 65.",
              "Paragraphe de continuité numéro 66.",
              "Paragraphe de continuité numéro 67.",
              "Paragraphe de continuité numéro 68.",
              "Paragraphe de continuité numéro 69.",
              "Paragraphe de continuité numéro 70.",
              "Paragraphe de continuité numéro 71.",
              "Paragraphe de continuité numéro 72.",
              "Paragraphe de continuité numéro 73.",
              "Paragraphe de continuité numéro 74.",
              "Paragraphe de continuité numéro 75.",
              "Paragraphe de continuité numéro 76.",
              "Paragraphe de continuité numéro 77.",
              "Paragraphe de continuité numéro 78.",
              "Paragraphe de continuité numéro 79.",
              "Paragraphe de continuité numéro 80.",
              "Paragraphe de continuité numéro 81.",
              "Paragraphe de continuité numéro 82.",
              "Paragraphe de continuité numéro 83.",
              "Paragraphe de continuité numéro 84.",
              "Paragraphe de continuité numéro 85.",
              "Paragraphe de continuité numéro 86.",
              "Paragraphe de continuité numéro 87.",
              "Paragraphe de continuité numéro 88.",
              "Paragraphe de continuité numéro 89.",
              "Paragraphe de continuité numéro 90.",
              "Paragraphe de continuité numéro 91.",
              "Paragraphe de continuité numéro 92.",
              "Paragraphe de continuité numéro 93.",
              "Paragraphe de continuité numéro 94.",
              "Paragraphe de continuité numéro 95.",
              "Paragraphe de continuité numéro 96.",
              "Paragraphe de continuité numéro 97.",
              "Paragraphe de continuité numéro 98.",
              "Paragraphe de continuité numéro 99.",
              "Paragraphe de continuité numéro 100.",
              "Paragraphe de continuité numéro 101.",
              "Paragraphe de continuité numéro 102.",
              "Paragraphe de continuité numéro 103.",
              "Paragraphe de continuité numéro 104.",
              "Paragraphe de continuité numéro 105.",
              "Paragraphe de continuité numéro 106.",
              "Paragraphe de continuité numéro 107.",
              "Paragraphe de continuité numéro 108.",
              "Paragraphe de continuité numéro 109.",
              "Paragraphe de continuité numéro 110.",
              "Paragraphe de continuité numéro 111.",
              "Paragraphe de continuité numéro 112.",
              "Paragraphe de continuité numéro 113.",
              "Paragraphe de continuité numéro 114.",
              "Paragraphe de continuité numéro 115.",
              "Paragraphe de continuité numéro 116.",
              "Paragraphe de continuité numéro 117.",
              "Paragraphe de continuité numéro 118.",
              "Paragraphe de continuité numéro 119.",
              "Paragraphe de continuité numéro 120."
            ],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Paragraphe de continuité numéro 120."
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapitre 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapitre 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 2 et suit le chemin du jardin."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapitre 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapitre 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "Léa ouvre le chapitre 3 et suit le chemin du jardin."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-09.epub",
        "bytes": 3134,
        "sha256": "e51df04398059b2206d82001eca6ebdb57afc48199366ae9497f369f074158bf",
        "referenceSha256": "a152b8ba35bdb27f7d23aa59bb3505ff6e1902829cb05c9a0633836a18cbb937"
      },
      "source": "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"
    },
    {
      "id": "epub-10",
      "sourceSha": "20e8fe981ae2a49c2d4c5cd8d988d10e41d33fb3bc0bed2348a92341ed628899",
      "entries": {
        "mimetype": "YXBwbGljYXRpb24vZXB1Yit6aXA=",
        "META-INF/container.xml": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNvbnRhaW5lciB4bWxucz0idXJuOm9hc2lzOm5hbWVzOnRjOm9wZW5kb2N1bWVudDp4bWxuczpjb250YWluZXIiIHZlcnNpb249IjEuMCI+PHJvb3RmaWxlcz48cm9vdGZpbGUgZnVsbC1wYXRoPSJPRUJQUy9jb250ZW50Lm9wZiIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24vb2VicHMtcGFja2FnZSt4bWwiLz48L3Jvb3RmaWxlcz48L2NvbnRhaW5lcj4=",
        "OEBPS/content.opf": "PD94bWwgdmVyc2lvbj0iMS4wIj8+PHBhY2thZ2UgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiIHZlcnNpb249IjMuMCIgdW5pcXVlLWlkZW50aWZpZXI9ImJvb2tpZCI+PG1ldGFkYXRhIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOmlkZW50aWZpZXIgaWQ9ImJvb2tpZCI+dXJuOnVyZWFkZXI6Zml4dHVyZToxMDwvZGM6aWRlbnRpZmllcj48ZGM6dGl0bGU+Rml4dHVyZSBFUFVCIDEwPC9kYzp0aXRsZT48ZGM6Y3JlYXRvcj5BdXRldXIgc3ludGjDqXRpcXVlIHVSZWFkZXI8L2RjOmNyZWF0b3I+PGRjOmxhbmd1YWdlPmVuPC9kYzpsYW5ndWFnZT48bWV0YSBwcm9wZXJ0eT0iZGN0ZXJtczptb2RpZmllZCI+MjAyNi0xMS0xNFQwMDowMDowMFo8L21ldGE+PG1ldGEgbmFtZT0iY292ZXIiIGNvbnRlbnQ9ImNvdmVyIi8+PC9tZXRhZGF0YT48bWFuaWZlc3Q+PGl0ZW0gaWQ9ImMwIiBocmVmPSJjaGFwdGVyMS54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+PGl0ZW0gaWQ9ImMxIiBocmVmPSJjaGFwdGVyMi54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+PGl0ZW0gaWQ9ImMyIiBocmVmPSJjaGFwdGVyMy54aHRtbCIgbWVkaWEtdHlwZT0iYXBwbGljYXRpb24veGh0bWwreG1sIi8+PGl0ZW0gaWQ9ImNzcyIgaHJlZj0ic3R5bGUuY3NzIiBtZWRpYS10eXBlPSJ0ZXh0L2NzcyIvPjxpdGVtIGlkPSJjb3ZlciIgaHJlZj0iY292ZXIucG5nIiBtZWRpYS10eXBlPSJpbWFnZS9wbmciIHByb3BlcnRpZXM9ImNvdmVyLWltYWdlIi8+PGl0ZW0gaWQ9Im5hdiIgaHJlZj0ibmF2LnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiIHByb3BlcnRpZXM9Im5hdiIvPjwvbWFuaWZlc3Q+PHNwaW5lPjxpdGVtcmVmIGlkcmVmPSJjMCIvPjxpdGVtcmVmIGlkcmVmPSJjMSIvPjxpdGVtcmVmIGlkcmVmPSJjMiIvPjwvc3BpbmU+PC9wYWNrYWdlPg==",
        "OEBPS/style.css": "Ym9keSB7IGNvbG9yOiAjMjAyMDIwOyB9IC5oaWRkZW4geyBkaXNwbGF5OiBub25lOyB9",
        "OEBPS/chapter1.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImVuIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXB0ZXIgMTwvaDE+PHAgaWQ9InBhc3NhZ2UiPlRoZSByZWFkZXIgb3BlbnMgY2hhcHRlciAxIGFuZCBmb2xsb3dzIHRoZSBnYXJkZW4gcGF0aC48L3A+PHA+PGltZyBzcmM9ImNvdmVyLnBuZyIgYWx0PSJDYXJyw6kgYmxldSBkZSByw6lmw6lyZW5jZSIvPjwvcD48L2JvZHk+PC9odG1sPg==",
        "OEBPS/chapter2.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImVuIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXB0ZXIgMjwvaDE+PHAgaWQ9InBhc3NhZ2UiPlRoZSByZWFkZXIgb3BlbnMgY2hhcHRlciAyIGFuZCBmb2xsb3dzIHRoZSBnYXJkZW4gcGF0aC48L3A+PC9ib2R5PjwvaHRtbD4=",
        "OEBPS/chapter3.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImVuIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxoMSBpZD0ic3RhcnQiPkNoYXB0ZXIgMzwvaDE+PHAgaWQ9InBhc3NhZ2UiPlRoZSByZWFkZXIgb3BlbnMgY2hhcHRlciAzIGFuZCBmb2xsb3dzIHRoZSBnYXJkZW4gcGF0aC48L3A+PC9ib2R5PjwvaHRtbD4=",
        "OEBPS/nav.xhtml": "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgeG1sOmxhbmc9ImVuIj48aGVhZD48dGl0bGU+Rml4dHVyZTwvdGl0bGU+PGxpbmsgcmVsPSJzdHlsZXNoZWV0IiB0eXBlPSJ0ZXh0L2NzcyIgaHJlZj0ic3R5bGUuY3NzIi8+PC9oZWFkPjxib2R5PjxuYXYgeG1sbnM6ZXB1Yj0iaHR0cDovL3d3dy5pZHBmLm9yZy8yMDA3L29wcyIgZXB1Yjp0eXBlPSJ0b2MiPjxvbD48bGk+PGEgaHJlZj0iY2hhcHRlcjEueGh0bWwjc3RhcnQiPkNoYXB0ZXIgMTwvYT48L2xpPjxsaT48YSBocmVmPSJjaGFwdGVyMi54aHRtbCNzdGFydCI+Q2hhcHRlciAyPC9hPjwvbGk+PGxpPjxhIGhyZWY9ImNoYXB0ZXIzLnhodG1sI3N0YXJ0Ij5DaGFwdGVyIDM8L2E+PC9saT48L29sPjwvbmF2PjwvYm9keT48L2h0bWw+",
        "OEBPS/cover.png": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGNQSFgARAwQCgAdjgSBQe+XXgAAAABJRU5ErkJggg=="
      },
      "reference": {
        "id": "epub-10",
        "epubVersion": 3,
        "language": "en",
        "titleAbsent": false,
        "authorAbsent": false,
        "coverAbsent": false,
        "features": [],
        "chapters": [
          {
            "chapterId": "c0",
            "href": "OEBPS/chapter1.xhtml",
            "title": "Chapter 1",
            "initialCanonicalBlocks": [
              {
                "id": "c0-b0-s0",
                "text": "Chapter 1"
              },
              {
                "id": "c0-b1-s0",
                "text": "The reader opens chapter 1 and follows the garden path."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "The reader opens chapter 1 and follows the garden path."
          },
          {
            "chapterId": "c1",
            "href": "OEBPS/chapter2.xhtml",
            "title": "Chapter 2",
            "initialCanonicalBlocks": [
              {
                "id": "c1-b0-s0",
                "text": "Chapter 2"
              },
              {
                "id": "c1-b1-s0",
                "text": "The reader opens chapter 2 and follows the garden path."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "The reader opens chapter 2 and follows the garden path."
          },
          {
            "chapterId": "c2",
            "href": "OEBPS/chapter3.xhtml",
            "title": "Chapter 3",
            "initialCanonicalBlocks": [
              {
                "id": "c2-b0-s0",
                "text": "Chapter 3"
              },
              {
                "id": "c2-b1-s0",
                "text": "The reader opens chapter 3 and follows the garden path."
              }
            ],
            "additionalVisibleMainTextInOrder": [],
            "expectedAnchors": [
              "start",
              "passage"
            ],
            "lastMainText": "The reader opens chapter 3 and follows the garden path."
          }
        ],
        "expectedImport": "ready",
        "conformance": "synthetic import-profile input; not EPUBCheck certified; absent mandatory metadata is intentional",
        "rights": "Original synthetic uReader fixture, dedicated to CC0-1.0; no personal or third-party book.",
        "path": "private/corpus/epub-10.epub",
        "bytes": 2674,
        "sha256": "20e8fe981ae2a49c2d4c5cd8d988d10e41d33fb3bc0bed2348a92341ed628899",
        "referenceSha256": "62d7e1946dd55025e4a31613342b4e530a75e737e3a5b80d3f91fc8f67acf623"
      },
      "source": "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"
    }
  ]
}
''';
