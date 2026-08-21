from mojotui import KeyEvent
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from yuragi.candidate import Candidate, candidates_from_text
from yuragi.interactive import (
    FinderOutcome,
    FinderSession,
    _FinderModel,
    _handle_key,
    _match_count,
    _selected_id,
    _total_count,
)
from yuragi.options import Options, parse_options
from yuragi.pipeline import rank_picker_query


def _model(var candidates: List[Candidate]) raises -> _FinderModel:
    var options = Options()
    var seeded_query = String(options.query)
    var matches = rank_picker_query(candidates, seeded_query, options)
    return _FinderModel(candidates^, options, matches^)


def test_typing_narrows_matches_and_counter() raises:
    var candidates = candidates_from_text("apple\nbanana\npear\n")
    var model = _model(candidates^)
    assert_equal(_match_count(model), 3)
    assert_equal(_total_count(model), 3)

    assert_false(_handle_key(model, KeyEvent.character(String("b"))))
    assert_equal(model.query, "b")
    assert_equal(_match_count(model), 1)
    assert_equal(_total_count(model), 3)
    assert_equal(model.matches[0].text, "banana")


def test_selection_survives_refinement_by_candidate_id() raises:
    var candidates = candidates_from_text("za\nab\nac\n")
    var model = _model(candidates^)
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.DOWN)))
    assert_true(_selected_id(model).value() == 1)
    assert_true(model.cursor.selected.value() == UInt(1))

    assert_false(_handle_key(model, KeyEvent.character(String("a"))))
    assert_true(_selected_id(model).value() == 1)
    assert_true(model.cursor.selected.value() == UInt(0))
    assert_equal(model.matches[0].text, "ab")


def test_enter_accepts_exact_cursor_candidate() raises:
    var candidates = candidates_from_text("first\nsecond\n")
    var session = FinderSession(candidates^, Options())
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.DOWN)))
    assert_true(_handle_key(session._model, KeyEvent.named(KeyEvent.ENTER)))
    assert_true(session._model.outcome == FinderOutcome.ACCEPTED)

    var selected = session.selection()
    assert_equal(len(selected), 1)
    assert_equal(selected[0].source_index, 1)
    assert_equal(selected[0].text, "second")


def test_escape_aborts_with_empty_selection() raises:
    var candidates = candidates_from_text("first\nsecond\n")
    var session = FinderSession(candidates^, Options())
    assert_true(_handle_key(session._model, KeyEvent.named(KeyEvent.ESCAPE)))
    assert_true(session._model.outcome == FinderOutcome.ABORTED)
    assert_equal(len(session.selection()), 0)


def test_empty_query_preserves_all_candidates_in_source_order() raises:
    var candidates = candidates_from_text("third\nfirst\nsecond\n")
    var model = _model(candidates^)

    assert_equal(model.query, "")
    assert_equal(_match_count(model), 3)
    for index in range(3):
        assert_equal(model.matches[index].source_index, index)
    assert_equal(model.matches[0].text, "third")
    assert_equal(model.matches[1].text, "first")
    assert_equal(model.matches[2].text, "second")


def test_seeded_query_initializes_ranked_state_on_first_match() raises:
    var args: List[String] = ["yuragi", "--query", "ba"]
    var options = parse_options(args^)
    var candidates = candidates_from_text("apple\nbar\nbanana\n")
    var session = FinderSession(candidates^, options)
    ref model = session._model

    assert_equal(model.query, "ba")
    assert_equal(_match_count(model), 2)
    assert_equal(model.matches[0].text, "bar")
    assert_equal(model.matches[1].text, "banana")
    assert_true(model.cursor.selected.value() == UInt(0))
    assert_true(_selected_id(model).value() == model.matches[0].source_index)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
