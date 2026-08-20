"""Command-line parsing for Yuragi's noninteractive application mode."""

from std.collections import List


comptime VERSION = "0.0.0"


struct Options(Copyable):
    """Validated command-line options owned by the application."""

    var has_filter: Bool
    var has_language: Bool
    var query: String
    var language: String
    var help_requested: Bool
    var version_requested: Bool

    def __init__(out self):
        self.has_filter = False
        self.has_language = False
        self.query = String()
        self.language = String("auto")
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
        elif argument == "--lang":
            if index + 1 >= len(args):
                raise Error("--lang requires a language")
            index += 1
            _set_language(options, args[index])
        elif argument.startswith("--lang="):
            _set_language(options, argument.removeprefix("--lang="))
        else:
            raise Error("unknown argument: ", argument)
        index += 1
    return options^


def usage() -> String:
    """Return the current, deliberately narrow command-line contract."""
    return String(
        "Usage: yuragi --filter QUERY [--lang auto|zh|ja|ko]\n"
        "\n"
        "Read newline-delimited candidates from standard input and write selected\n"
        "candidates to standard output. Non-empty matching is gated on the Moji,\n"
        "Hibana, and Yomi integration milestone.\n"
        "\n"
        "Options:\n"
        "  -f, --filter QUERY   select candidates for QUERY\n"
        "      --lang LANGUAGE  phonetic language hint (default: auto)\n"
        "  -h, --help           show this help\n"
        "      --version        show the version\n"
        "\n"
        "Invalid options exit before informational modes. If both --help and\n"
        "--version are validly supplied, --help wins.\n"
        "Exit codes: 0 = success, 1 = no match (reserved), 2 = error.\n"
    )


def version_text() -> String:
    """Return the executable version line."""
    return String("yuragi ", VERSION)
