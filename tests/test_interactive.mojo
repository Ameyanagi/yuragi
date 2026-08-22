from mojotui import InputEvent, KeyEvent, PasteEvent
from std.collections import List
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from yuragi.candidate import Candidate, candidates_from_text
from yuragi.interactive import (
    FinderOutcome,
    FinderSession,
    _FinderApplication,
    _FinderModel,
    _counter_text,
    _handle_key,
    _is_marked,
    _item_line,
    _match_count,
    _marked_count,
    _query_text,
    _row_count,
    _selected_id,
    _total_count,
    _visible_window,
)
from yuragi.options import Options, parse_options
from yuragi.pipeline import rank_picker_query
from yuragi.search_index import SearchIndex


def _model(var candidates: List[Candidate]) raises -> _FinderModel:
    var options = Options()
    var seeded_query = String(options.query)
    var matches = rank_picker_query(candidates, seeded_query, options)
    var index = SearchIndex(candidates^)
    return _FinderModel(index^, options, matches^, len(matches))


def _multi_model(var candidates: List[Candidate]) raises -> _FinderModel:
    var args: List[String] = ["yuragi", "--multi"]
    var options = parse_options(args^)
    var seeded_query = String(options.query)
    var matches = rank_picker_query(candidates, seeded_query, options)
    var index = SearchIndex(candidates^)
    return _FinderModel(index^, options, matches^, len(matches))


def _seeded_model(
    var candidates: List[Candidate], query: String
) raises -> _FinderModel:
    var args: List[String] = ["yuragi", "--query", query]
    var options = parse_options(args^)
    var seeded_query = String(options.query)
    var matches = rank_picker_query(candidates, seeded_query, options)
    var index = SearchIndex(candidates^)
    return _FinderModel(index^, options, matches^, len(matches))


def test_typing_narrows_matches_and_counter() raises:
    var candidates = candidates_from_text("apple\nbanana\npear\n")
    var model = _model(candidates^)
    assert_equal(_match_count(model), 3)
    assert_equal(_total_count(model), 3)

    assert_false(_handle_key(model, KeyEvent.character(String("b"))))
    assert_equal(_query_text(model), "b")
    assert_equal(_match_count(model), 1)
    assert_equal(_total_count(model), 3)
    assert_equal(model.matches[0].text, "banana")


def test_control_u_clears_query_and_restores_all_matches() raises:
    var candidates = candidates_from_text("alpha\nbravo\ncharlie\n")
    var model = _seeded_model(candidates^, String("br"))
    assert_equal(_match_count(model), 1)

    assert_false(
        _handle_key(
            model,
            KeyEvent.character(String("u"), KeyEvent.CONTROL),
        )
    )
    assert_equal(_query_text(model), "")
    assert_equal(_match_count(model), 3)


def test_control_w_deletes_the_trailing_word() raises:
    var candidates = candidates_from_text("alpha bravo\nalpha charlie\nsolo\n")
    var model = _seeded_model(candidates^, String("alpha bravo"))
    assert_false(
        _handle_key(
            model,
            KeyEvent.character(String("w"), KeyEvent.CONTROL),
        )
    )
    assert_equal(_query_text(model), "alpha ")

    var solo_candidates = candidates_from_text("alpha bravo\nalpha charlie\nsolo\n")
    var solo_model = _seeded_model(solo_candidates^, String("solo"))
    assert_false(
        _handle_key(
            solo_model,
            KeyEvent.character(String("w"), KeyEvent.CONTROL),
        )
    )
    assert_equal(_query_text(solo_model), "")
    assert_equal(_match_count(solo_model), 3)


def test_editor_cursor_delete_home_end_and_history_commands() raises:
    var candidates = candidates_from_text("abc\nother\n")
    var model = _seeded_model(candidates^, String("ac"))
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.LEFT)))
    assert_false(_handle_key(model, KeyEvent.character(String("b"))))
    assert_equal(_query_text(model), "abc")
    assert_equal(_match_count(model), 1)

    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.HOME)))
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.DELETE)))
    assert_equal(_query_text(model), "bc")
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.END)))
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.BACKSPACE)))
    assert_equal(_query_text(model), "b")

    assert_false(_handle_key(model, KeyEvent.character(String("z"), KeyEvent.CONTROL)))
    assert_equal(_query_text(model), "bc")
    assert_false(_handle_key(model, KeyEvent.character(String("y"), KeyEvent.CONTROL)))
    assert_equal(_query_text(model), "b")


def test_shift_text_is_accepted_but_alt_characters_do_not_leak() raises:
    var candidates = candidates_from_text("alpha\n")
    var model = _model(candidates^)
    assert_false(_handle_key(model, KeyEvent.character(String("A"), KeyEvent.SHIFT)))
    assert_equal(_query_text(model), "A")
    assert_false(_handle_key(model, KeyEvent.character(String("x"), KeyEvent.ALT)))
    assert_equal(_query_text(model), "A")


def test_paste_is_one_editor_transaction_and_one_rerank() raises:
    var candidates = candidates_from_text("alpha\nbravo\ncharlie\n")
    var model = _model(candidates^)
    var application = _FinderApplication(model^)
    var initialized = application.init()
    var live_model = initialized.take_model()
    var before = live_model.input.engine.document.version
    var message = application.on_input(live_model, InputEvent(PasteEvent("br\n")))
    assert_true(message)
    _ = application.update(live_model, message.take())
    assert_equal(live_model.input.engine.document.version, before + 1)
    assert_equal(_query_text(live_model), "br")
    assert_equal(_match_count(live_model), 1)
    assert_equal(live_model.matches[0].text, "bravo")


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


def test_enter_with_no_result_keeps_picker_open() raises:
    var candidates = candidates_from_text("first\nsecond\n")
    var model = _seeded_model(candidates^, String("missing"))
    assert_equal(_row_count(model), 0)
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.ENTER)))
    assert_true(model.outcome == FinderOutcome.ABORTED)


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
    assert_equal(
        _counter_text(model),
        "lang=auto matches=2/2 retained=2 shown=2 marks=1",
    )


def test_multi_marks_survive_query_refinement() raises:
    var candidates = candidates_from_text("apple\nbanana\n")
    var model = _multi_model(candidates^)
    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.TAB)))

    assert_false(_handle_key(model, KeyEvent.character(String("b"))))
    assert_equal(_match_count(model), 1)
    assert_equal(model.matches[0].text, "banana")
    assert_true(_is_marked(model, 0))
    assert_equal(
        _counter_text(model),
        "lang=auto matches=1/2 retained=1 shown=1 marks=1",
    )

    assert_false(_handle_key(model, KeyEvent.named(KeyEvent.BACKSPACE)))
    assert_equal(_match_count(model), 2)
    assert_equal(len(model.matches), 0)
    assert_equal(_row_count(model), 2)
    assert_true(model.identity_mode)
    assert_true(_is_marked(model, 0))
    var restored_line = _item_line(model, 0)
    assert_equal(restored_line.spans[0].content, "* ")


def test_multi_limit_caps_marks_across_query_changes() raises:
    var candidates = candidates_from_text("alpha\nbravo\n")
    var args: List[String] = ["yuragi", "--multi", "--limit", "1"]
    var session = FinderSession(candidates^, parse_options(args^))

    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.TAB)))
    assert_equal(_marked_count(session._model), 1)
    assert_false(_handle_key(session._model, KeyEvent.character(String("b"))))
    assert_false(_handle_key(session._model, KeyEvent.named(KeyEvent.TAB)))
    assert_equal(_marked_count(session._model), 1)

    assert_true(_handle_key(session._model, KeyEvent.named(KeyEvent.ENTER)))
    var selected = session.selection()
    assert_equal(len(selected), 1)
    assert_equal(selected[0].text, "alpha")


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
    assert_equal(
        _counter_text(model),
        "lang=auto matches=2/2 retained=2 shown=2 marks=0",
    )


def test_escape_aborts_with_empty_selection() raises:
    var candidates = candidates_from_text("first\nsecond\n")
    var session = FinderSession(candidates^, Options())
    assert_true(_handle_key(session._model, KeyEvent.named(KeyEvent.ESCAPE)))
    assert_true(session._model.outcome == FinderOutcome.ABORTED)
    assert_equal(len(session.selection()), 0)


def test_empty_query_preserves_all_candidates_in_source_order() raises:
    var candidates = candidates_from_text("third\nfirst\nsecond\n")
    var model = _model(candidates^)

    assert_equal(_query_text(model), "")
    assert_equal(_match_count(model), 3)
    assert_equal(len(model.matches), 0)
    assert_equal(_row_count(model), 3)
    assert_equal(_item_line(model, 0).spans[0].content, "third")
    assert_equal(_item_line(model, 1).spans[0].content, "first")
    assert_equal(_item_line(model, 2).spans[0].content, "second")


def test_seeded_query_initializes_ranked_state_on_first_match() raises:
    var args: List[String] = ["yuragi", "--query", "ba"]
    var options = parse_options(args^)
    var candidates = candidates_from_text("apple\nbar\nbanana\n")
    var session = FinderSession(candidates^, options)
    ref model = session._model

    assert_equal(_query_text(model), "ba")
    assert_equal(_match_count(model), 2)
    assert_equal(model.matches[0].text, "bar")
    assert_equal(model.matches[1].text, "banana")
    assert_true(model.cursor.selected.value() == UInt(0))
    assert_true(_selected_id(model).value() == model.matches[0].source_index)

    assert_false(_handle_key(model, KeyEvent.character(String("n"))))
    assert_equal(_query_text(model), "ban")
    assert_true(model.index.last_search_was_incremental())
    assert_equal(model.index.last_scanned_count(), 2)


def test_session_constructor_prepares_the_explicit_language_once() raises:
    var args: List[String] = ["yuragi", "--lang", "zh", "--query", "bjdx"]
    var candidates = candidates_from_text("北京大学\nnotes\n")
    var session = FinderSession(candidates^, parse_options(args^))
    assert_equal(_query_text(session._model), "bjdx")
    assert_equal(_match_count(session._model), 1)
    assert_equal(session._model.matches[0].text, "北京大学")
    assert_true(_counter_text(session._model).startswith("lang=zh matches=1/2"))


def test_seeded_limited_query_preserves_exact_total_match_count() raises:
    var args: List[String] = ["yuragi", "--query", "a", "--limit", "1"]
    var options = parse_options(args^)
    var candidates = candidates_from_text("apple\nbanana\npear\n")
    var session = FinderSession(candidates^, options)

    assert_equal(len(session._model.matches), 1)
    assert_equal(_match_count(session._model), 3)
    assert_equal(
        _counter_text(session._model),
        "lang=auto matches=3/3 retained=1 shown=1 marks=0",
    )


def test_empty_query_limit_bounds_interactive_rows_not_exact_count() raises:
    var args: List[String] = ["yuragi", "--limit", "1"]
    var candidates = candidates_from_text("first\nsecond\nthird\n")
    var session = FinderSession(candidates^, parse_options(args^))

    assert_equal(_match_count(session._model), 3)
    assert_equal(_row_count(session._model), 1)
    assert_equal(_item_line(session._model, 0).spans[0].content, "first")


def test_visible_window_materializes_only_rows_around_cursor() raises:
    var candidates = candidates_from_text("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n")
    var model = _model(candidates^)
    for _ in range(8):
        assert_false(_handle_key(model, KeyEvent.named(KeyEvent.DOWN)))

    var window = _visible_window(model, 4)
    assert_equal(window[0], 6)
    assert_equal(window[1], 10)

    var empty_window = _visible_window(model, 0)
    assert_equal(empty_window[0], 0)
    assert_equal(empty_window[1], 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
