"""Command-line parsing for Yuragi's noninteractive application mode."""

from hibana import CaseMode
from std.collections import List


comptime VERSION = "0.0.0"


struct Options(Copyable):
    """Validated command-line options owned by the application."""

    var has_filter: Bool
    var has_language: Bool
    var has_limit: Bool
    var has_case_override: Bool
    var query: String
    var language: String
    var limit: Int
    var case_mode: CaseMode
    var read0: Bool
    var print0: Bool
    var help_requested: Bool
    var version_requested: Bool

    def __init__(out self):
        self.has_filter = False
        self.has_language = False
        self.has_limit = False
        self.has_case_override = False
        self.query = String()
        self.language = String("auto")
        self.limit = 0
        self.case_mode = CaseMode.SMART_ASCII
        self.read0 = False
        self.print0 = False
        self.help_requested = False
        self.version_requested = False


def _set_language(mut options: Options, value: StringSlice) raises:
    if options.has_language:
        raise Error("--lang may be specified only once")
    var language = String(value)
    if (
        language != "auto"
        and language != "zh"
        and language != "ja"
        and language != "ko"
    ):
        raise Error("--lang must be one of: auto, zh, ja, ko")
    options.has_language = True
    options.language = language^


def _set_filter(mut options: Options, value: StringSlice) raises:
    if options.has_filter:
        raise Error("--filter may be specified only once")
    options.has_filter = True
    options.query = String(value)


def _set_limit(mut options: Options, value: StringSlice) raises:
    if options.has_limit:
        raise Error("--limit may be specified only once")
    var limit: Int
    try:
        limit = Int(String(value))
    except:
        raise Error("--limit requires a positive candidate count")
    if limit < 1:
        raise Error("--limit requires a positive candidate count")
    options.has_limit = True
    options.limit = limit


def _set_read0(mut options: Options) raises:
    if options.read0:
        raise Error("--read0 may be specified only once")
    options.read0 = True


def _set_print0(mut options: Options) raises:
    if options.print0:
        raise Error("--print0 may be specified only once")
    options.print0 = True


def _set_case_mode(mut options: Options, case_mode: CaseMode) raises:
    if options.has_case_override:
        raise Error("case sensitivity may be specified only once")
    options.has_case_override = True
    options.case_mode = case_mode


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
        elif argument == "--ignore-case" or argument == "-i":
            _set_case_mode(options, CaseMode.IGNORE_ASCII)
        elif argument == "--no-ignore-case":
            _set_case_mode(options, CaseMode.EXACT)
        else:
            raise Error("unknown argument: ", argument)
        index += 1
    return options^


def usage() -> String:
    """Return the current, deliberately narrow command-line contract."""
    return String(
        "Usage: yuragi --filter QUERY [--limit N] [--lang auto|zh|ja|ko] "
        "[options]\n"
        "\n"
        "Read newline-delimited candidates from standard input and write selected\n"
        "candidates to standard output. Non-empty queries use direct Hibana fuzzy\n"
        "matching; phonetic language matching awaits Yomi integration.\n"
        "Smart case is the default: a query containing an ASCII uppercase letter\n"
        "matches case-sensitively.\n"
        "\n"
        "Options:\n"
        "  -f, --filter QUERY    select candidates for QUERY\n"
        "      --limit N         emit at most N best-ranked candidates\n"
        "      --lang LANGUAGE   phonetic language hint (default: auto)\n"
        "  -i, --ignore-case     match case-insensitively (ASCII)\n"
        "      --no-ignore-case  match case-sensitively\n"
        "      --read0           read NUL-delimited candidates from standard input\n"
        "      --print0          write NUL-delimited candidates to standard output\n"
        "  -h, --help            show this help\n"
        "      --version         show the version\n"
        "\n"
        "Invalid options exit before informational modes. If both --help and\n"
        "--version are validly supplied, --help wins.\n"
        "Exit codes: 0 = success, 1 = no match, 2 = error.\n"
    )


def version_text() -> String:
    """Return the executable version line."""
    return String("yuragi ", VERSION)
