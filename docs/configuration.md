# Configuration

Yuragi loads optional settings for both filter and interactive finder execution.
Run `yuragi config path` to see the file it will read. Resolution is:

1. Nonempty `YURAGI_CONFIG_FILE` (used literally; no shell expansion).
2. Absolute `XDG_CONFIG_HOME`, followed by `/yuragi/config.toml`.
3. `HOME`, followed by `/.config/yuragi/config.toml`.

A relative `XDG_CONFIG_HOME` is ignored. A missing file uses the remaining
sources and defaults; Yuragi does not create files or directories automatically.
An unreadable file or inaccessible parent is an error, not an absent file.
Files must be regular files (symlinks to regular files are accepted) and no
larger than 65,536 bytes. This bounds startup reads and prevents a FIFO from
blocking the finder. A configuration-path resolution failure exits 2.

For example, create the resolved directory and a file with:

```toml
# Search preferences
lang = "ja"
case = "smart"
limit = 20
```

The supported format is an intentionally small, flat TOML schema: one bare
allowlisted key and value per line, whitespace, LF or CRLF, blank lines,
and `#` comments outside strings. Enum values use matching single or double
quotes and their literal lowercase spelling. `limit` uses positive decimal
digits without signs, separators, or leading zeros. Escapes, multiline strings,
tables, dotted/quoted keys, arrays, dates, booleans, and other TOML forms are
outside this schema and produce a corrective error. This is not a general
TOML parser. No new runtime or parser dependency is required.

| Setting | Supported values | Environment | CLI override | Default |
| --- | --- | --- | --- | --- |
| `lang` | `"auto"`, `"ja"`, `"zh"`, `"ko"` | `YURAGI_LANG` | `--lang VALUE` | `auto` (direct matching) |
| `case` | `"smart"`, `"ignore"`, `"exact"` | `YURAGI_CASE` | `--smart-case`, `--ignore-case`, `--no-ignore-case` | `smart` (ASCII smart case) |
| `limit` | Integer at least 1 | `YURAGI_LIMIT` | `--limit N` | Unlimited; omit the key |

For **each setting independently**, precedence is **CLI > environment > config
> defaults**. Environment values are unquoted strings, and an empty variable
means unset. A CLI language override does not reset a case or limit setting
from another source. Repeated CLI options retain their existing last-wins
behavior. All values supplied by the file and environment are validated, even
when a CLI value would override them; malformed files and invalid settings
never disappear silently.

```sh
# Environment overrides the file, and this CLI flag overrides that environment.
YURAGI_CASE=exact yuragi --smart-case --filter camera < candidates.txt

# Skip a malformed or unwanted config file; environment overrides still apply.
yuragi --no-config --filter camera < candidates.txt
```

Use `--no-config` to skip path resolution and file access entirely. To request
only defaults plus CLI options, also unset `YURAGI_LANG`, `YURAGI_CASE`, and
`YURAGI_LIMIT`. Input budgets, framing, queries, multi-select, shell commands,
and preview execution are deliberately outside the configuration surface.
Unknown and duplicate keys are errors. No commands, interpolation, or shell
expansion are executed from settings.

`yuragi doctor` reads and validates the same file and reports whether it was
loaded or absent. Invalid configuration exits 2 with the path (and line where
available), key, offending value, and a correction. `yuragi doctor --no-config`
can inspect other workflow dependencies without resolving or opening the file.
Help, version, shell generation, and `config path` do not load the file, so those
commands remain available while repairing a bad configuration.

The test suite checks every setting at every precedence layer, mixed sources,
empty environment variables, defaults, malformed/duplicate/unknown values,
missing/unreadable/inaccessible/oversized/nonregular files, informational modes,
and the explicit no-config escape through the compiled CLI.
