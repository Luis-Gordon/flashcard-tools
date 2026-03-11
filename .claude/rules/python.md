---
globs: "flashcard-anki/**/*.py"
---
- Python 3.9+ (Anki's bundled version)
- Type hints on all function signatures
- No `Any` except Anki runtime types (`mw`, `Note`, `Collection`) — use `# type: ignore[...]`
- `TypedDict` for structured data, `dataclass` for internal models
- Files: `snake_case.py`, Classes: `PascalCase`, Constants: `UPPER_SNAKE_CASE`
