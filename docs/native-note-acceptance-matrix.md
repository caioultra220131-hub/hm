# Native Note Acceptance Matrix

This matrix is for manual acceptance only. It does not change runtime code paths.

## Static validation

Run this before manual checks:

```bash
node ./scripts/validate-native-note-fixtures.mjs
```

This confirms that the fixture set covers:

- legacy strokes version 1 and 2
- paged and infinite mode
- blank, pdf, and hybrid preview and scene payloads
- empty scene, page-0, and scene-bounds snapshots

## Matrix

| Acceptance item | Fixtures | Manual action | Pass condition |
| --- | --- | --- | --- |
| Reopen should not drift | `legacy-strokes/strokes.v1.paged.json`, `legacy-strokes/strokes.v1.infinite.json`, `legacy-strokes/strokes.v2.paged.json`, `legacy-strokes/strokes.v2.infinite.json`, matching native scene fixtures | Load fixture into a document package, open the note, close it, reopen it, then export a scene snapshot | Stroke bounds, page anchoring, and object counts remain unchanged after reopen |
| Surface change should not drift | `native-scene/scene.blank.infinite.bounds.json`, `native-scene/scene.pdf.infinite.bounds.json`, `native-scene/scene.hybrid.infinite.bounds.json` | Open the document, resize or recreate the drawing surface, then export another scene snapshot | `layout.documentBounds` and each object `bounds` remain stable |
| Paged page-0 should stay stable | `native-preview/preview.pdf.paged.page0.json`, `native-preview/preview.hybrid.paged.page0.json`, `native-scene/scene.pdf.paged.page0.json`, `native-scene/scene.hybrid.paged.page0.json` | Open the document directly to page 0, reopen it, and compare preview and scene outputs | `pageIndex` stays `0`, `pageId` stays `page-0`, and page bounds do not change |
| Infinite grid should not drift | `native-preview/preview.blank.infinite.bounds.json`, `native-preview/preview.pdf.infinite.bounds.json`, `native-preview/preview.hybrid.infinite.bounds.json`, matching scene fixtures | Open an infinite document, pan and zoom, reopen, then export preview and scene payloads | World-space bounds remain stable and coordinates do not shift around the origin |
| PDF must stay below ink | `native-preview/preview.pdf.paged.page0.json`, `native-preview/preview.pdf.infinite.bounds.json`, `native-preview/preview.hybrid.paged.page0.json`, `native-preview/preview.hybrid.infinite.bounds.json`, matching scene fixtures | Open the fixture and inspect the rendered order or exported payload | Preview `layers` keeps `pdf` before `ink`, and scene objects keep PDF nodes on layer `pdf` with annotations on layer `ink` |
| Legacy migration should save as new format | All `legacy-strokes/*.json` fixtures | Open a legacy package, trigger the normal save path, then inspect the persisted `strokes.json` | Saved output uses version `2` and the new keys such as `objectId`, `colorHex`, `shapeType`, and `points[*].timeStamp` |

## Notes

- The validator checks fixture structure and coverage only.
- The matrix intentionally avoids any change to `napi_init.cpp`, `NativeNoteEngine.ets`, `EditorWorkspace.ets`, or `DocumentLibraryService.ets`.

