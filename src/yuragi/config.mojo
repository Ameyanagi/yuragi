"""Validated flat TOML settings and explicit CLI/environment/file precedence."""

from hibana import CaseMode
from std.collections import Optional
from std.ffi import ErrNo, get_errno
from std.os.env import getenv
from std.pathlib import Path

from yuragi.options import Options


comptime MAX_CONFIG_BYTES = 65_536


struct ConfigSettings(Copyable):
    """Only the supported settings; absence leaves the next source in control."""

    var language: Optional[String]
    var case_mode: Optional[CaseMode]
    var limit: Optional[Int]

    def __init__(out self):
        self.language = None
        self.case_mode = None
        self.limit = None


def _join_config_home(base: StringSlice) -> String:
    var prefix = String(base)
    if prefix.endswith("/"):
        return prefix + "yuragi/config.toml"
    return prefix + "/yuragi/config.toml"


def config_path_from_environment(
    *,
    override: String = "",
    xdg_config_home: String = "",
    home: String = "",
) raises -> String:
    """Resolve the path with explicit, absolute XDG, then HOME precedence."""
    if override != "":
        return override
    if xdg_config_home.startswith("/"):
        return _join_config_home(xdg_config_home)
    if home != "":
        var config_home = home + "/.config"
        if home.endswith("/"):
            config_home = home + ".config"
        return _join_config_home(config_home)
    raise Error(
        "configuration path requires YURAGI_CONFIG_FILE, XDG_CONFIG_HOME, "
        "or HOME; set one of those environment variables"
    )


def config_path() raises -> String:
    return config_path_from_environment(
        override=getenv("YURAGI_CONFIG_FILE"),
        xdg_config_home=getenv("XDG_CONFIG_HOME"),
        home=getenv("HOME"),
    )


def _invalid(
    source: StringSlice, key: StringSlice, value: StringSlice, correction: StringSlice
) -> Error:
    return Error(String(source, ": key '", key, "' value '", value, "': ", correction))


def _language(source: StringSlice, value: StringSlice) raises -> String:
    if value == "auto" or value == "ja" or value == "zh" or value == "ko":
        return String(value)
    raise _invalid(source, "lang", value, "choose auto, ja, zh, or ko")


def _case(source: StringSlice, value: StringSlice) raises -> CaseMode:
    if value == "smart":
        return CaseMode.SMART_ASCII
    if value == "ignore":
        return CaseMode.IGNORE_ASCII
    if value == "exact":
        return CaseMode.EXACT
    raise _invalid(source, "case", value, "choose smart, ignore, or exact")


def _limit(source: StringSlice, value: StringSlice) raises -> Int:
    # The documented settings grammar uses positive decimal digits, matching
    # ordinary CLI values. Signs, separators and other TOML numeric types are
    # rejected explicitly rather than silently coerced.
    if value.byte_length() == 0 or not value.is_ascii_digit():
        raise _invalid(
            source,
            "limit",
            value,
            "use a positive decimal integer, for example limit = 20",
        )
    if value.byte_length() > 1 and value.startswith("0"):
        raise _invalid(
            source,
            "limit",
            value,
            "remove the leading zero; use a positive decimal integer",
        )
    var count: Int
    try:
        count = Int(String(value))
    except:
        raise _invalid(
            source,
            "limit",
            value,
            "use a positive decimal integer within the supported Int range",
        )
    if count < 1:
        raise _invalid(
            source,
            "limit",
            value,
            "use at least 1; omit limit for the unlimited default",
        )
    return count


def _unquote(
    source: StringSlice, key: StringSlice, value: StringSlice
) raises -> String:
    if value.byte_length() < 2:
        raise _invalid(
            source,
            key,
            value,
            'use a single-line quoted value, for example lang = "ja"',
        )
    var bytes = value.as_bytes()
    var quote = bytes[0]
    if (quote != 34 and quote != 39) or bytes[len(bytes) - 1] != quote:
        raise _invalid(
            source,
            key,
            value,
            "use matching single or double quotes around the supported value",
        )
    # All allowlisted enum values are ASCII words. The supported flat schema
    # deliberately excludes escapes and multiline strings; no shell expansion.
    for position in range(1, len(bytes) - 1):
        if bytes[position] < 97 or bytes[position] > 122:
            raise _invalid(
                source,
                key,
                value,
                (
                    "write the supported lowercase enum value literally inside one pair"
                    " of quotes"
                ),
            )
    return String(value[byte = 1 : len(bytes) - 1])


def parse_config(text: StringSlice, path: StringSlice) raises -> ConfigSettings:
    """Parse the documented flat settings schema; reject unsupported TOML forms."""
    if text.byte_length() > MAX_CONFIG_BYTES:
        raise _invalid(
            path,
            "<file>",
            String(text.byte_length()),
            "keep config.toml at or below 65536 bytes, or use --no-config",
        )
    var settings = ConfigSettings()
    var line_number = 0
    # Split only LF: CRLF is stripped, and TOML comments remain on their line.
    for raw_line in text.split("\n"):
        line_number += 1
        var line = raw_line.strip()
        if line.byte_length() == 0 or line.startswith("#"):
            continue
        var source = String(path, ":", line_number)
        var fields = line.split("=", maxsplit=1)
        if len(fields) != 2:
            raise _invalid(
                source,
                "<line>",
                line,
                (
                    "use one top-level key = value assignment; supported keys: lang,"
                    " case, limit"
                ),
            )
        var key = fields[0].strip()
        var raw_value = fields[1].strip()
        # Comments outside quotes are stripped. A # inside quotes survives so
        # the enum validator reports the original offending value.
        var quote = UInt8(0)
        var comment = raw_value.byte_length()
        var bytes = raw_value.as_bytes()
        for position in range(len(bytes)):
            var byte = bytes[position]
            if quote == 0 and (byte == 34 or byte == 39):
                quote = byte
            elif quote != 0 and byte == quote:
                quote = 0
            elif quote == 0 and byte == 35:
                comment = position
                break
        var value = raw_value[byte=0:comment].strip()
        if key == "lang":
            if settings.language:
                raise _invalid(
                    source, key, value, "remove the duplicate lang assignment"
                )
            settings.language = _language(source, _unquote(source, key, value))
        elif key == "case":
            if settings.case_mode:
                raise _invalid(
                    source, key, value, "remove the duplicate case assignment"
                )
            settings.case_mode = _case(source, _unquote(source, key, value))
        elif key == "limit":
            if settings.limit:
                raise _invalid(
                    source, key, value, "remove the duplicate limit assignment"
                )
            settings.limit = _limit(source, value)
        else:
            raise _invalid(
                source,
                key,
                value,
                "remove this unsupported key; supported keys: lang, case, limit",
            )
    return settings^


def load_config_file(path: StringSlice) raises -> Optional[ConfigSettings]:
    """Load at most 64 KiB; missing files are optional, unreadable files are errors."""
    if not Path(path).exists():
        # Mojo 1.0 Path.exists() suppresses every stat error. Only ENOENT
        # means an optional file is absent; an
        # inaccessible parent or malformed path must not silently use defaults.
        var error_number = get_errno()
        if error_number == ErrNo.ENOENT:
            return None
        raise _invalid(
            path,
            "<file>",
            String("stat errno ", error_number),
            "make the path accessible, choose YURAGI_CONFIG_FILE, or pass --no-config",
        )
    if not Path(path).is_file():
        raise _invalid(
            path,
            "<file>",
            "not a regular file",
            "use a readable regular config.toml file, or pass --no-config",
        )
    var text: String
    try:
        with open(path, "r") as file:
            text = file.read(MAX_CONFIG_BYTES + 1)
    except error:
        raise _invalid(
            path,
            "<file>",
            String(error),
            "make this file readable, choose YURAGI_CONFIG_FILE, or pass --no-config",
        )
    return parse_config(text, path)


def environment_settings(
    *, language: StringSlice = "", case_mode: StringSlice = "", limit: StringSlice = ""
) raises -> ConfigSettings:
    """Validate explicit environment values; empty variables mean unset."""
    var settings = ConfigSettings()
    if language.byte_length() > 0:
        settings.language = _language("environment YURAGI_LANG", language)
    if case_mode.byte_length() > 0:
        settings.case_mode = _case("environment YURAGI_CASE", case_mode)
    if limit.byte_length() > 0:
        settings.limit = _limit("environment YURAGI_LIMIT", limit)
    return settings^


def apply_settings(
    mut options: Options, config: ConfigSettings, environment: ConfigSettings
):
    """Apply CLI > environment > config > defaults independently per setting."""
    if not options.has_language:
        if environment.language:
            options.language = environment.language.value().copy()
        elif config.language:
            options.language = config.language.value().copy()
    if not options.has_case_override:
        if environment.case_mode:
            options.case_mode = environment.case_mode.value()
        elif config.case_mode:
            options.case_mode = config.case_mode.value()
    if not options.has_limit:
        if environment.limit:
            options.limit = environment.limit.value()
            options.has_limit = True
        elif config.limit:
            options.limit = config.limit.value()
            options.has_limit = True


def apply_runtime_configuration(mut options: Options) raises:
    """Read settings only for actual finder execution, after CLI parsing."""
    var config = ConfigSettings()
    if not options.no_config:
        var loaded = load_config_file(config_path())
        if loaded:
            config = loaded.take()
    var environment = environment_settings(
        language=getenv("YURAGI_LANG"),
        case_mode=getenv("YURAGI_CASE"),
        limit=getenv("YURAGI_LIMIT"),
    )
    apply_settings(options, config, environment)
