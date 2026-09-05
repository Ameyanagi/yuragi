"""Command-line parsing for Yuragi's filter and interactive modes."""

from hibana import CaseMode
from std.collections import List

from yuragi.shell import ShellKind


comptime VERSION = "0.1.0"


struct CommandKind(Copyable, Equatable, ImplicitlyCopyable):
    """Top-level execution mode selected before candidate processing."""

    var _value: Int

    comptime FIND = CommandKind(_value=0)
    comptime DOCTOR = CommandKind(_value=1)
    comptime SHELL = CommandKind(_value=2)
    comptime CONFIG_PATH = CommandKind(_value=3)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


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
    var max_input_bytes: Int
    var max_candidates: Int
    var max_record_bytes: Int
    var case_mode: CaseMode
    var read0: Bool
    var print0: Bool
    var explain: Bool
    var select_1: Bool
    var exit_0: Bool
    var multi: Bool
    var no_config: Bool
    var help_requested: Bool
    var version_requested: Bool
    var command: CommandKind
    var shell: ShellKind

    def __init__(out self):
        self.has_filter = False
        self.has_query = False
        self.has_language = False
        self.has_limit = False
        self.has_case_override = False
        self.query = String()
        self.language = String("auto")
        self.limit = 0
        self.max_input_bytes = 268_435_456
        self.max_candidates = 1_000_000
        self.max_record_bytes = 1_048_576
        self.case_mode = CaseMode.SMART_ASCII
        self.read0 = False
        self.print0 = False
        self.explain = False
        self.select_1 = False
        self.exit_0 = False
        self.multi = False
        self.no_config = False
        self.help_requested = False
        self.version_requested = False
        self.command = CommandKind.FIND
        self.shell = ShellKind.BASH


def _parse_subcommand(args: List[String], mut options: Options) raises -> Bool:
    if len(args) < 2:
        return False
    var command = args[1]
    if command == "doctor":
        if len(args) == 3 and args[2] == "--no-config":
            options.no_config = True
        elif len(args) != 2:
            raise Error("doctor accepts no arguments; got: ", args[2])
        options.command = CommandKind.DOCTOR
        return True
    if command == "shell":
        if len(args) < 3:
            raise Error("shell requires one of: bash, zsh, fish, powershell")
        if len(args) > 3:
            raise Error("shell accepts one shell name; unexpected argument: ", args[3])
        var shell = args[2]
        if shell == "bash":
            options.shell = ShellKind.BASH
        elif shell == "zsh":
            options.shell = ShellKind.ZSH
        elif shell == "fish":
            options.shell = ShellKind.FISH
        elif shell == "powershell":
            options.shell = ShellKind.POWERSHELL
        else:
            raise Error(
                "unsupported shell: ",
                shell,
                "; choose bash, zsh, fish, or powershell",
            )
        options.command = CommandKind.SHELL
        return True
    if command == "config":
        if len(args) < 3:
            raise Error("config requires the path action; use: yuragi config path")
        if args[2] != "path":
            raise Error(
                "unsupported config action: ",
                args[2],
                "; the only supported action is path",
            )
        if len(args) > 3:
            raise Error("config path accepts no arguments; got: ", args[3])
        options.command = CommandKind.CONFIG_PATH
        return True
    return False


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
    if _parse_subcommand(args, options):
        return options^
    var index = 1
    while index < len(args):
        var argument = String(args[index])
        if argument == "--help" or argument == "-h":
            options.help_requested = True
        elif argument == "--no-config":
            options.no_config = True
        elif argument == "--smart-case":
            _set_case_mode(options, CaseMode.SMART_ASCII)
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
        elif (
            argument.startswith("--max-input-bytes")
            or argument.startswith("--max-candidates")
            or argument.startswith("--max-record-bytes")
        ):
            var fields = argument.split("=", maxsplit=1)
            var flag = String(fields[0])
            if (
                flag != "--max-input-bytes"
                and flag != "--max-candidates"
                and flag != "--max-record-bytes"
            ):
                raise Error("unknown argument '", argument, "' (try 'yuragi --help')")
            var value: String
            if len(fields) == 2:
                value = String(fields[1])
            else:
                if index + 1 >= len(args):
                    raise Error(flag, " requires a positive integer; use ", flag, " N")
                index += 1
                value = String(args[index])
            var amount: Int
            try:
                amount = Int(value)
            except:
                raise Error(
                    flag,
                    " value '",
                    value,
                    "' must be a positive integer within range; use ",
                    flag,
                    " N",
                )
            if amount < 1:
                raise Error(
                    flag, " value '", value, "' must be >= 1; increase the limit"
                )
            if flag == "--max-input-bytes":
                options.max_input_bytes = amount
            elif flag == "--max-candidates":
                options.max_candidates = amount
            else:
                options.max_record_bytes = amount
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
        "Usage: yuragi [--filter QUERY | --query QUERY] [--limit N]\n             "
        " [--lang auto|zh|ja|ko] [options]\n       yuragi doctor [--no-config]\n      "
        " yuragi shell bash|zsh|fish|powershell\n       yuragi config path\n\nRead"
        " newline-delimited candidates from standard input and write"
        " selected\ncandidates to standard output. Without --filter, open an inline"
        " picker;\nfilter and interactive modes share one prepared search index. auto"
        " keeps\ndirect matching; ja, zh, and ko opt into bounded Yomi phonetic"
        " keys.\nSmart case is the default: a query containing an ASCII uppercase"
        " letter\nmatches case-sensitively.\n\nOptions:\n  -f, --filter QUERY          "
        " filter candidates noninteractively for QUERY\n  -q, --query STR             "
        " seed the interactive prompt with STR\n  -1, --select-1               accept a"
        " sole initial match without the picker\n  -0, --exit-0                 exit 1"
        " on no initial matches without the picker\n  -m, --multi                 "
        " select multiple candidates with TAB/Shift-TAB\n      --limit N               "
        " emit at most N best-ranked candidates\n      --lang LANGUAGE          auto"
        " (direct), ja, zh, or ko (default: auto)\n  -i, --ignore-case            match"
        " case-insensitively (ASCII)\n  +i, --no-ignore-case         match"
        " case-sensitively\n      --smart-case             restore ASCII smart case"
        " explicitly\n      --no-config              skip config file loading"
        " (environment still applies)\n      --read0                  read"
        " NUL-delimited candidates from standard input\n      --print0                "
        " write NUL-delimited candidates to standard output\n      --max-input-bytes N "
        "     cap raw input bytes (default: 268435456)\n      --max-candidates N      "
        " cap input records (default: 1000000)\n      --max-record-bytes N     cap raw"
        " bytes per record (default: 1048576)\n      --explain                print"
        " rank, score, key kind, and match positions\n  -h, --help                  "
        " show this help\n      --version                show the"
        " version\n\nCommands:\n  doctor                report environment and workflow"
        " dependencies\n  shell SHELL           print Ctrl-T, Ctrl-R, Alt-C, and **"
        " integration\n  config path           print the resolved config"
        " path\n\nInteractive flag matrix: --query seeds the prompt;"
        " --select-1\nauto-accepts and prints a sole initial match; --exit-0 exits"
        " 1\nimmediately when the initial match set is empty; --multi enables\nmarking"
        " multiple candidates. With --query, both automation flags\nevaluate the seeded"
        " query. All four flags are interactive-mode-only\nand are usage errors with"
        " --filter.\nKeybindings: Enter accepts; TAB marks and moves down; Shift-TAB"
        " marks\nand moves up in --multi mode. Both are inert without"
        " --multi.\nLeft/Right/Home/End move the query cursor; Backspace/Delete"
        " edit.\nCtrl-U clears; Ctrl-W deletes the previous word; Ctrl-Z/Y"
        " undo/redo.\n\nSettings: CLI > YURAGI_LANG/YURAGI_CASE/YURAGI_LIMIT > config >"
        " defaults.\nConfig supports lang, case, and limit; run config path for its"
        " location.\nInvalid options exit before informational modes. If both --help"
        " and\n--version are validly supplied, --help wins.\nExit codes: 0 = success, 1"
        " = no match, 2 = error, 130 = interactive abort.\n"
    )


def version_text() -> String:
    """Return the executable version line."""
    return String("yuragi ", VERSION)
