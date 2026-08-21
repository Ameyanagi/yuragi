from mojotui import KeyEvent
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from yuragi.candidate import Candidate, candidates_from_text
from yuragi.interactive import (
    FinderOutcome,
    FinderSession,
    _FinderModel,
    _counter_text,
    _handle_key,
    _is_marked,
    _item_line,
    _match_count,
    _marked_count,
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


def _multi_model(var candidates: List[Candidate]) raises -> _FinderModel:
    var args: List[String] = ["yuragi", "--multi"]
    var options = parse_options(args^)
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


def test_multi_tab_marks_and_moves_down() raises:
    var candidates = candidates_from_text("first\nsecond\nthird\n")
    var model = _multi_model(candidates^)

    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB)))
    assert_true(_is_marked(model, 0))
    assert_equal(_marked_count(model), 1)
    assert_true(_selected_id(model).value() == 1)
    assert_true(model.cursor.selected.value() == UInt(1))


def test_multi_shift_tab_marks_and_moves_up() raises:
    var candidates = candidates_from_text("first\nsecond\nthird\n")
    var model = _multi_model(candidates^)
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.DOWN)))

    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB, KeyEvent.SHIFT)))
    assert_true(_is_marked(model, 1))
    assert_equal(_marked_count(model), 1)
    assert_true(_selected_id(model).value() == 0)
    assert_true(model.cursor.selected.value() == UInt(0))


def test_multi_toggling_twice_unmarks() raises:
    var candidates = candidates_from_text("only\n")
    var model = _multi_model(candidates^)

    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB)))
    assert_true(_is_marked(model, 0))
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB)))
    assert_false(_is_marked(model, 0))
    assert_equal(_marked_count(model), 0)


def test_multi_render_shows_marker_and_marked_count() raises:
    var candidates = candidates_from_text("first\nsecond\n")
    var model = _multi_model(candidates^)
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB)))

    var marked_line = _item_line(model, 0)
    var unmarked_line = _item_line(model, 1)
    assert_equal(marked_line.spans[0].content, "* ")
    assert_equal(unmarked_line.spans[0].content, "  ")
    assert_equal(_counter_text(model), "2/2 (1)")


def test_multi_marks_survive_query_refinement() raises:
    var candidates = candidates_from_text("apple\nbanana\n")
    var model = _multi_model(candidates^)
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB)))

    assert_false(_handle_key(model, KeyEvent.character(String("b"))))
    assert_equal(_match_count(model), 1)
    assert_equal(model.matches[0].text, "banana")
    assert_true(_is_marked(model, 0))
    assert_equal(_counter_text(model), "1/2 (1)")

    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.BACKSPACE)))
    assert_equal(_match_count(model), 2)
    assert_true(_is_marked(model, 0))
    var restored_line = _item_line(model, 0)
    assert_equal(restored_line.spans[0].content, "* ")


def test_multi_enter_returns_reverse_marks_in_source_order() raises:
    var candidates = candidates_from_text("first\nsecond\nthird\n")
    var args: List[String] = ["yuragi", "-m"]
    var session = FinderSession(candidates^, parse_options(args^))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.DOWN)))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.DOWN)))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.TAB)))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.UP)))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.UP)))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.TAB)))

    assert_equal(session._model.marked_source_indices[0], 2)
    assert_equal(session._model.marked_source_indices[1], 0)
    assert_true(_handle_key(session._model, KeyEvent.named(KeyEvent.ENTER)))
    var selected = session.selection()
    assert_equal(len(selected), 2)
    assert_equal(selected[0].source_index, 0)
    assert_equal(selected[0].text, "first")
    assert_equal(selected[1].source_index, 2)
    assert_equal(selected[1].text, "third")


def test_multi_enter_without_marks_accepts_cursor_candidate() raises:
    var candidates = candidates_from_text("first\nsecond\n")
    var args: List[String] = ["yuragi", "-m"]
    var session = FinderSession(candidates^, parse_options(args^))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.DOWN)))
    assert_true(_handle_key(session._model, KeyEvent.named(KeyEvent.ENTER)))

    var selected = session.selection()
    assert_equal(len(selected), 1)
    assert_equal(selected[0].source_index, 1)
    assert_equal(selected[0].text, "second")


def test_tab_without_multi_is_inert() raises:
    var candidates = candidates_from_text("first\nsecond\n")
    var model = _model(candidates^)

    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB)))
    assert_equal(_marked_count(model), 0)
    assert_true(_selected_id(model).value() == 0)
    assert_true(model.cursor.selected.value() == UInt(0))
    var first_line = _item_line(model, 0)
    assert_equal(first_line.spans[0].content, "first")
    assert_equal(_counter_text(model), "2/2")


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
