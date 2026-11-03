# XMind workbooks (`.xmind`)

FreeMind opens `.xmind` workbooks from current XMind versions (the JSON format) as regular documents and saves them back as `.xmind`. Any other map, new or imported, can be saved as a new `.xmind` with File › Save As or File › Duplicate.

Workbooks with more than one sheet and XMind 8 files are still imported as new unsaved maps, one per sheet.

## How saving works

- A workbook that was opened but not changed is written back byte for byte.
- When something changed, FreeMind edits the original `content.json` in place. It changes only the topics, fields and relationships that were edited and keeps every other key, such as themes, styles, positions, extensions and attributed titles of unchanged topics.
- New images and attachments are stored in `resources/` and listed in `manifest.json`. `Thumbnails/thumbnail.png` is replaced with a new preview.
- After writing, FreeMind reads the new file back and compares it with the map in the editor. If anything differs, the save fails, the original file stays unchanged, and the error names the first difference.

## What is read and written

| XMind | FreeMind | Notes |
| --- | --- | --- |
| Topic title | Topic title | An edited title drops XMind's rich-text title for that topic. |
| Attached, callout, summary and floating topics | Children | Callout, summary and floating topics are shown after the attached children and are written back with their kind. A topic moved to another parent becomes an attached topic. |
| Folded branch | Collapsed | |
| Notes | Note | Read as plain text. An edited note is written as plain paragraphs. |
| Hyperlink | Link | A topic in XMind holds one link or one attachment. When a topic has both, the link is saved. |
| Attachment (`xap:` link) | Attachment | Only the first attachment of a topic is saved. |
| Markers | Markers | Priority, progress, flags, stars and the FreeMind symbols. Other XMind markers are kept. |
| Labels | Labels | |
| Image | Image | |
| Boundaries | Boundaries | A boundary around several siblings is shown on each of them and written back per topic when it changes. |
| Relationships | Relationships | Including labels. Control points and styles of existing relationships are kept. |
| Structure of the central topic | Structure | |

Not saved to `.xmind`: FreeMind theme, topic styles other than boundaries, spacing, line style, topic width and relationship styles.
