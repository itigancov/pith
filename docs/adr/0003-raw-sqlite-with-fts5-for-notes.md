# Raw SQLite with FTS5 for Notes

Notes live in a single SQLite database accessed through the system `sqlite3` C API behind our own `NoteStore`, with no SwiftData and no GRDB. Search needs substring matching that ignores case, accents and ё/е, which only FTS5 `trigram` over a Swift-folded column gives at keystroke speed; SwiftData has no full-text search at all (its predicates are a full scan). GRDB would give FTS5 too, but the schema is one table plus one FTS index, its 7.9+ releases track the newest Swift, and it is maintained mostly by one person, so a few hundred lines of our own wrapper keep the app free of third-party dependencies.

## Consequences

- Migrations are ours: `PRAGMA user_version` plus ordered SQL steps.
- The store runs on the main actor: an autosave of a 5k-line Note with FTS takes about 2.5 ms.
- Backups must use `VACUUM INTO` or the backup API, never a file copy, because of the `-wal`/`-shm` files.
