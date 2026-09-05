from hibana import CaseMode
from std.collections import List
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from yuragi.config import (
    ConfigSettings,
    apply_settings,
    environment_settings,
    load_config_file,
    parse_config,
)
from yuragi.options import parse_options


def test_defaults_and_supported_flat_toml() raises:
    var empty = parse_config("# only a comment\r\n\r\n", "/cfg/config.toml")
    assert_false(Bool(empty.language))
    assert_false(Bool(empty.case_mode))
    assert_false(Bool(empty.limit))
    var settings = parse_config(
        "lang = 'ja' # Japanese\r\ncase=\"exact\"\nlimit = 12\n", "/cfg/config.toml"
    )
    assert_equal(settings.language.value(), "ja")
    assert_true(settings.case_mode.value() == CaseMode.EXACT)
    assert_equal(settings.limit.value(), 12)
    var args: List[String] = ["yuragi"]
    var options = parse_options(args)
    apply_settings(options, empty, empty)
    assert_equal(options.language, "auto")
    assert_true(options.case_mode == CaseMode.SMART_ASCII)
    assert_false(options.has_limit)


def test_each_setting_uses_cli_then_environment_then_file_then_default() raises:
    var config = parse_config("lang='ja'\ncase='exact'\nlimit=4\n", "/cfg/config.toml")
    var environment = environment_settings(language="zh", case_mode="ignore", limit="3")
    var empty = ConfigSettings()
    var args: List[String] = ["yuragi"]
    var from_file = parse_options(args)
    apply_settings(from_file, config, empty)
    assert_equal(from_file.language, "ja")
    assert_true(from_file.case_mode == CaseMode.EXACT)
    assert_equal(from_file.limit, 4)
    assert_true(from_file.has_limit)
    var from_environment = parse_options(args)
    apply_settings(from_environment, config, environment)
    assert_equal(from_environment.language, "zh")
    assert_true(from_environment.case_mode == CaseMode.IGNORE_ASCII)
    assert_equal(from_environment.limit, 3)
    var cli_args: List[String] = [
        "yuragi",
        "--lang",
        "ko",
        "--smart-case",
        "--limit",
        "2",
    ]
    var from_cli = parse_options(cli_args)
    apply_settings(from_cli, config, environment)
    assert_equal(from_cli.language, "ko")
    assert_true(from_cli.case_mode == CaseMode.SMART_ASCII)
    assert_equal(from_cli.limit, 2)
    # Independent fields fall through without one source resetting others.
    var mixed_args: List[String] = ["yuragi", "--lang", "auto"]
    var mixed = parse_options(mixed_args)
    var case_environment = environment_settings(case_mode="smart")
    apply_settings(mixed, config, case_environment)
    assert_equal(mixed.language, "auto")
    assert_true(mixed.case_mode == CaseMode.SMART_ASCII)
    assert_equal(mixed.limit, 4)


def test_unknown_duplicate_malformed_and_wrong_type_values_report_context() raises:
    with assert_raises(
        contains=(
            "/cfg/config.toml:2: key 'preview' value '\"touch marker\"': remove this"
            " unsupported key"
        )
    ):
        _ = parse_config('# comment\npreview = "touch marker"\n', "/cfg/config.toml")
    with assert_raises(
        contains="key 'lang' value ''ko'': remove the duplicate lang assignment"
    ):
        _ = parse_config("lang='ja'\nlang='ko'", "/cfg/config.toml")
    with assert_raises(
        contains=(
            "key '<line>' value '[search]': use one top-level key = value assignment"
        )
    ):
        _ = parse_config("[search]\nlang='ja'", "/cfg/config.toml")
    with assert_raises(
        contains="key 'case' value 'full': choose smart, ignore, or exact"
    ):
        _ = parse_config("case='full'", "/cfg/config.toml")
    with assert_raises(contains="key 'lang' value 'all': choose auto, ja, zh, or ko"):
        _ = parse_config("lang='all'", "/cfg/config.toml")
    with assert_raises(contains="use matching single or double quotes"):
        _ = parse_config("lang=ja", "/cfg/config.toml")
    with assert_raises(
        contains="key 'limit' value '\"3\"': use a positive decimal integer"
    ):
        _ = parse_config('limit="3"', "/cfg/config.toml")
    with assert_raises(contains="key 'limit' value '0': use at least 1"):
        _ = parse_config("limit=0", "/cfg/config.toml")
    with assert_raises(contains="remove the leading zero"):
        _ = parse_config("limit=012", "/cfg/config.toml")
    with assert_raises(contains="supported Int range"):
        _ = parse_config("limit=9999999999999999999999999999999", "/cfg/config.toml")
    with assert_raises(contains="write the supported lowercase enum value literally"):
        _ = parse_config("lang='ja#comment'", "/cfg/config.toml")
    with assert_raises(contains="use matching single or double quotes"):
        _ = parse_config("lang='ja' trailing", "/cfg/config.toml")


def test_environment_values_are_validated_without_shell_expansion() raises:
    with assert_raises(
        contains=(
            "environment YURAGI_LANG: key 'lang' value 'xx': choose auto, ja, zh, or ko"
        )
    ):
        _ = environment_settings(language="xx")
    with assert_raises(
        contains=(
            "environment YURAGI_CASE: key 'case' value 'unicode': choose smart, ignore,"
            " or exact"
        )
    ):
        _ = environment_settings(case_mode="unicode")
    with assert_raises(
        contains=(
            "environment YURAGI_LIMIT: key 'limit' value '$(echo 3)': use a positive"
            " decimal integer"
        )
    ):
        _ = environment_settings(limit="$(echo 3)")
    var empty = environment_settings(language="", case_mode="", limit="")
    assert_false(Bool(empty.language))
    assert_false(Bool(empty.case_mode))
    assert_false(Bool(empty.limit))


def test_no_config_flags_and_smart_case_are_explicit_overrides() raises:
    var args: List[String] = [
        "yuragi",
        "--no-config",
        "--no-ignore-case",
        "--smart-case",
    ]
    var options = parse_options(args)
    assert_true(options.no_config)
    assert_true(options.has_case_override)
    assert_true(options.case_mode == CaseMode.SMART_ASCII)
    var doctor_args: List[String] = ["yuragi", "doctor", "--no-config"]
    assert_true(parse_options(doctor_args).no_config)


def test_missing_and_non_regular_config_files() raises:
    assert_false(Bool(load_config_file(".pixi/config-file-that-does-not-exist.toml")))
    with assert_raises(
        contains=(
            "key '<file>' value 'not a regular file': use a readable regular"
            " config.toml file"
        )
    ):
        _ = load_config_file(".pixi")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
