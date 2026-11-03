# MindManager maps (`.mmap`)

FreeMind opens MindManager `.mmap` files directly and saves them back in the same format, including maps protected with a password. The aim is safe editing: the file stays a valid MindManager map, and everything FreeMind does not understand is kept as it was.

## How saving works

- A map that was opened but not changed is written back byte for byte.
- When something changed, FreeMind edits the original `Document.xml` in place. It changes only the topics, fields and relationships that were edited and keeps every other element, attribute, style and resource untouched.
- Unchanged entries of the ZIP package are copied as they are, without recompressing them.
- After writing, FreeMind reads the new file back and compares it with the map in the editor. If anything differs, the save fails, the original file stays unchanged, and the error names the first difference. Use File › Duplicate to keep a copy in the FreeMind format in that case.

## Saving other maps as `.mmap`

Any map, including a new one or one imported from another format, can be saved as `.mmap` with File › Save As or File › Duplicate. FreeMind writes a minimal MindManager map and adds the topics, notes, links, markers, images, attachments and relationships listed below. MindManager applies its default style to such a map. The same read-back check runs after every save.

## What is read and written

| MindManager | FreeMind | Notes |
| --- | --- | --- |
| Topic text (`ap:Text PlainText`) | Topic title | Line breaks are kept. The text style of an edited title is kept. |
| Subtopics and floating topics | Children | Floating topics are shown as children of the topic that holds them and are written back as floating topics. A topic moved to another parent loses its manual position. |
| Collapsed state | Collapsed | |
| Notes (XHTML) | Note | Read as plain text. An edited note is written as plain paragraphs, so the formatting of that note is lost. |
| Hyperlink URL | Link | Links to topics inside the map (`#...`) are not shown and are kept. |
| Task priority 1-9 | Priority 1-6 | Priorities above 6 are shown as 6 and stay unchanged unless edited. |
| Task percentage 0, 25, 50, 75, 100 | Progress | Other values are kept. |
| Flag and symbol icons | Flags and symbols | Red, orange, yellow, green, blue, purple and black flags; question, exclamation, idea, check, cross, thumbs up and down, money, clock. Other icons are kept. |
| Topic image | Image | New images are stored as PNG in `bin/`. |
| Attachments | Attachments | New attachments are stored in `bin/`. |
| Relationships | Relationships | Adding, removing and reconnecting relationships is saved. Labels are shown, but editing a label does not change the file. |

Not saved to `.mmap`: FreeMind labels, stars, relationship labels, topic styles, structure, theme and boundaries. These edits stay in the editor until the window is closed, but the `.mmap` file does not change because of them. After the first File › Save or Save As that would lose such changes, FreeMind offers to save a copy in the FreeMind format.

## Password-protected maps

FreeMind asks for the password when it opens a protected map and keeps it only in memory for that window. Saving encrypts the document and every new resource with the same password. MindManager stores no preview in protected maps, so FreeMind removes `Preview.png` and `PDFPreview.pdf` from them on save. Passwords from 1 to 56 bytes in UTF-8 are supported.

For unprotected maps FreeMind replaces `Preview.png` with a new preview of the map and removes `PDFPreview.pdf`, which it cannot regenerate.

## Limits

- ZIP64 packages and ZIP-level encryption are not supported. MindManager does not use either.
- Files with broken XML characters are opened after removing the invalid characters. Saving such a file writes the cleaned XML.
