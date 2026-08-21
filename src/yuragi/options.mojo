"""Command-line parsing for Yuragi's filter and interactive modes."""

from hibana import CaseMode
from std.collections import List


comptime VERSION = "0.0.0"


struct Options(Copyable):
    """Validated command-line options owned by the application."""

    var has_filter: Bool
    var has_query: Bool
    var has_language: Bool
    var has_limit: Bool
    var has_case_override: Bool
    var query: String
    var language: String
    var limit: Int
    var case_mode: CaseMode
    var read0: Bool
    var print0: Bool
    var explain: Bool
    var select_1: Bool
    var exit_0: Bool
    var multi: Bool
    var help_requested: Bool
    var version_requested: Bool

    def __init__(out self):
        self.has_filter = False
        self.has_query = False
        self.has_language = False
        self.has_limit = False
        self.has_case_override = False
        self.query = String()
        self.language = String("auto")
        self.limit = 0
        self.case_mode = CaseMode.SMART_ASCII
        self.read0 = False
        self.print0 = False
        self.explain = False
        self.select_1 = False
        self.exit_0 = False
        self.multi = False
        self.help_requested = False
        self.version_requested = False


def _set_language(mut options: Options, value: StringSlice) raises:
    var language = String(value)
    if language == "all" or language == "plain":
        raise Error(
            "--lang ",
            language,
            " is reserved to match yuru's register and is not yet supported",
        )
    if (
        language != "auto"
        and language != "zh"
        and language != "ja"
        and language != "ko"
    ):
        raise Error(
            "invalid value '",
            language,
            "' for --lang (possible values: auto, zh, ja, ko)",
        )
    options.has_language = True
    options.language = language^


def _set_filter(mut options: Options, value: StringSlice):
    options.has_filter = True
    options.query = String(value)


def _set_query(mut options: Options, value: StringSlice):
    options.has_query = True
    options.query = String(value)


def _set_limit(mut options: Options, value: StringSlice) raises:
    var limit: Int
    try:
        limit = Int(String(value))
    except:
        var trimmed = value.strip()
        var digits = trimmed
        if trimmed.startswith("+"):
            digits = trimmed.removeprefix("+")
        if digits.byte_length() > 0 and digits.is_ascii_digit():
            raise Error(
                "invalid value '",
                value,
                "' for --limit: count exceeds the supported integer range",
            )
        raise Error(
            "invalid value '",
            value,
            "' for --limit: expected a positive integer count (try 'yuragi --help')",
        )
    if limit < 1:
        raise Error(
            "invalid value '",
            value,
            "' for --limit: the candidate count must be at least 1",
        )
    options.has_limit = True
    options.limit = limit


def _set_read0(mut options: Options):
    options.read0 = True


def _set_print0(mut options: Options):
    options.print0 = True


def _set_explain(mut options: Options):
    options.explain = True


def _set_select_1(mut options: Options):
    options.select_1 = True


def _set_exit_0(mut options: Options):
    options.exit_0 = True


def _set_multi(mut options: Options):
    options.multi = True


def _set_case_mode(mut options: Options, case_mode: CaseMode):
    options.has_case_override = True
    options.case_mode = case_mode


def _validate_options(options: Options) raises:
    if options.has_filter and options.has_query:
        raise Error("--query cannot be used with --filter")
    if options.has_filter and options.select_1:
        raise Error("--select-1 cannot be used with --filter")
    if options.has_filter and options.exit_0:
        raise Error("--exit-0 cannot be used with --filter")
    if options.has_filter and options.multi:
        raise Error("--multi cannot be used with --filter")


def parse_options(args: List[String]) raises -> Options:
    """Parse all argv before applying help/version execution precedence."""
    var options = Options()
    var index = 1
    while index < len(args):
        var argument = String(args[index])
        if argument == "--help" or argument == "-h":
            options.help_requested = True
        elif argument == "--version":
            options.version_requested = True
        elif argument == "--filter" or argument == "-f":
            if index + 1 >= len(args):
                raise Error("--filter requires a query")
            index += 1
            _set_filter(options, args[index])
        elif argument.startswith("--filter="):
            _set_filter(options, argument.removeprefix("--filter="))
        elif argument.startswith("-f") and argument.byte_length() > 2:
            _set_filter(options, argument.removeprefix("-f"))
        elif argument == "--query" or argument == "-q":
            if index + 1 >= len(args):
                raise Error("--query requires a query")
            index += 1
            _set_query(options, args[index])
        elif argument.startswith("--query="):
            _set_query(options, argument.removeprefix("--query="))
        elif argument.startswith("-q") and argument.byte_length() > 2:
            _set_query(options, argument.removeprefix("-q"))
        elif argument == "--limit":
            if index + 1 >= len(args):
                raise Error("--limit requires a positive candidate count")
            index += 1
            _set_limit(options, args[index])
        elif argument.startswith("--limit="):
            _set_limit(options, argument.removeprefix("--limit="))
        elif argument == "--lang":
            if index + 1 >= len(args):
                raise Error("--lang requires a language")
            index += 1
            _set_language(options, args[index])
        elif argument.startswith("--lang="):
            _set_language(options, argument.removeprefix("--lang="))
        elif argument == "--read0":
            _set_read0(options)
        elif argument == "--print0":
            _set_print0(options)
        elif argument == "--explain":
            _set_explain(options)
        elif argument == "--select-1" or argument == "-1":
            _set_select_1(options)
        elif argument == "--exit-0" or argument == "-0":
            _set_exit_0(options)
        elif argument == "--multi" or argument == "-m":
            _set_multi(options)
        elif argument == "--ignore-case" or argument == "-i":
            _set_case_mode(options, CaseMode.IGNORE_ASCII)
        elif argument == "--no-ignore-case" or argument == "+i":
            _set_case_mode(options, CaseMode.EXACT)
        else:
            raise Error("unknown argument '", argument, "' (try 'yuragi --help')")
        index += 1
    _validate_options(options)
    return options^


def usage() -> String:
    """Return the current, deliberately narrow command-line contract."""
    return String(
        "Usage: yuragi [--filter QUERY | --query QUERY] [--limit N]\n"
        "              [--lang auto|zh|ja|ko] [options]\n"
        "\n"
        "Read newline-delimited candidates from standard input and write selected\n"
        "candidates to standard output. Without --filter, open an inline picker;\n"
        "filter mode uses direct Hibana fuzzy matching. Phonetic language matching\n"
        "awaits Yomi integration.\n"
        "Smart case is the default: a query containing an ASCII uppercase letter\n"
        "matches case-sensitively.\n"
        "\n"
        "Options:\n"
        "  -f, --filter QUERY    filter candidates noninteractively for QUERY\n"
        "  -q, --query STR       seed the interactive prompt with STR\n"
        "  -1, --select-1        accept a sole initial match without the picker\n"
        "  -0, --exit-0          exit 1 on no initial matches without the picker\n"
        "  -m, --multi           select multiple candidates with TAB/Shift-TAB\n"
        "      --limit N         emit at most N best-ranked candidates\n"
        "      --lang LANGUAGE   phonetic language hint (default: auto)\n"
        "  -i, --ignore-case     match case-insensitively (ASCII)\n"
        "  +i, --no-ignore-case  match case-sensitively\n"
        "      --read0           read NUL-delimited candidates from standard input\n"
        "      --print0          write NUL-delimited candidates to standard output\n"
        "      --explain         print rank, score, key kind, and match positions\n"
        "  -h, --help            show this help\n"
        "      --version         show the version\n"
        "\n"
        "Interactive flag matrix: --query seeds the prompt; --select-1\n"
        "auto-accepts and prints a sole initial match; --exit-0 exits 1\n"
        "immediately when the initial match set is empty; --multi enables\n"
        "marking multiple candidates. With --query, both automation flags\n"
        "evaluate the seeded query. All four flags are interactive-mode-only\n"
        "and are usage errors with --filter.\n"
        "Keybindings: Enter accepts; TAB marks and moves down; Shift-TAB marks\n"
        "and moves up in --multi mode. Both are inert without --multi.\n"
        "Ctrl-U clears the query; Ctrl-W deletes the trailing word.\n"
        "\n"
        "Invalid options exit before informational modes. If both --help and\n"
        "--version are validly supplied, --help wins.\n"
        "Exit codes: 0 = success, 1 = no match, 2 = error, 130 = interactive abort.\n"
    )


def version_text() -> String:
    """Return the executable version line."""
    return String("yuragi ", VERSION)
