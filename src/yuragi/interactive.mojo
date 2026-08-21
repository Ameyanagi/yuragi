"""Inline MojoTUI application adapter for interactive candidate selection."""

from mojotui import (
    Application,
    Buffer,
    Color,
    Command,
    Constraint,
    InitResult,
    InlineBackend,
    InputEvent,
    KeyEvent,
    Layout,
    Line,
    List,
    ListItem,
    ListState,
    PosixReactor,
    Rect,
    RuntimeAdapter,
    SessionOptions,
    Style,
    StylePatch,
    Subscription,
    SystemClock,
    TerminalApplicationHost,
    UpdateResult,
    detect_terminal_capabilities,
    render_line,
)
from std.collections import List as MojoList, Optional
from std.ffi import c_int, external_call

from yuragi.candidate import Candidate
from yuragi.options import Options
from yuragi.pipeline import rank_picker_query
from yuragi.ranking import RankedCandidate


comptime _VIEWPORT_HEIGHT = 12


struct FinderOutcome(Copyable, Equatable, ImplicitlyCopyable):
    """Nominal completion state for one interactive finder run."""

    var _value: Int

    comptime ACCEPTED = FinderOutcome(_value=0)
    comptime ABORTED = FinderOutcome(_value=1)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


struct _FinderModel(Copyable):
    var candidates: MojoList[Candidate]
    var options: Options
    var query: String
    var matches: MojoList[RankedCandidate]
    var cursor: ListState
    var selected_source_index: Optional[Int]
    var marked_source_indices: MojoList[Int]
    var outcome: FinderOutcome

    def __init__(
        out self,
        var candidates: MojoList[Candidate],
        options: Options,
        var matches: MojoList[RankedCandidate],
    ):
        self.options = options.copy()
        self.query = String(options.query)
        self.cursor = ListState()
        self.selected_source_index = None
        self.marked_source_indices = MojoList[Int]()
        self.outcome = FinderOutcome.ABORTED
        if len(matches) > 0:
            self.cursor.select(UInt(0), len(matches))
            self.selected_source_index = matches[0].source_index
        self.matches = matches^
        self.candidates = candidates^


def _match_count(model: _FinderModel) -> Int:
    return len(model.matches)


def _total_count(model: _FinderModel) -> Int:
    return len(model.candidates)


def _selected_id(model: _FinderModel) -> Optional[Int]:
    return model.selected_source_index.copy()


def _marked_count(model: _FinderModel) -> Int:
    return len(model.marked_source_indices)


def _contains_source_index(source_indices: MojoList[Int], source_index: Int) -> Bool:
    for index in range(len(source_indices)):
        if source_indices[index] == source_index:
            return True
    return False


def _is_marked(model: _FinderModel, source_index: Int) -> Bool:
    return _contains_source_index(model.marked_source_indices, source_index)


def _toggled_mark_order(
    source_indices: MojoList[Int], source_index: Int
) -> MojoList[Int]:
    """Return candidate IDs in mark order after toggling one candidate ID."""
    var toggled = source_indices.copy()
    for index in range(len(toggled)):
        if toggled[index] == source_index:
            _ = toggled.pop(index)
            return toggled^
    toggled.append(source_index)
    return toggled^


def _toggle_cursor_mark(mut model: _FinderModel):
    if not model.selected_source_index:
        return
    model.marked_source_indices = _toggled_mark_order(
        model.marked_source_indices,
        model.selected_source_index.value(),
    )


def _accepted_source_indices(model: _FinderModel) -> MojoList[Int]:
    """Resolve accepted candidate IDs while retaining mark order internally."""
    if model.options.multi and len(model.marked_source_indices) > 0:
        return model.marked_source_indices.copy()
    var accepted = MojoList[Int]()
    if model.selected_source_index:
        accepted.append(model.selected_source_index.value())
    return accepted^


def _resolved_selection(model: _FinderModel) -> MojoList[Candidate]:
    """Resolve accepted IDs to copied candidates in ascending source order."""
    var selected = MojoList[Candidate]()
    if model.outcome != FinderOutcome.ACCEPTED:
        return selected^

    var remaining = _accepted_source_indices(model)
    while len(remaining) > 0:
        var earliest = 0
        for index in range(1, len(remaining)):
            if remaining[index] < remaining[earliest]:
                earliest = index
        var accepted_id = remaining.pop(earliest)
        for candidate_index in range(len(model.candidates)):
            if model.candidates[candidate_index].source_index == accepted_id:
                selected.append(
                    Candidate(
                        accepted_id,
                        String(model.candidates[candidate_index].text),
                    )
                )
                break
    return selected^


def _erase_last_grapheme(mut text: String):
    var previous = 0
    var end = 0
    for grapheme in text.graphemes():
        previous = end
        end += grapheme.byte_length()
    var shortened = String(text[byte=:previous])
    text = shortened^


def _adopt_cursor_id(mut model: _FinderModel):
    if not model.cursor.selected:
        model.selected_source_index = None
        return
    var row = Int(model.cursor.selected.value())
    model.selected_source_index = model.matches[row].source_index


def _rerank(mut model: _FinderModel) raises:
    var previous_row = 0
    if model.cursor.selected:
        previous_row = Int(model.cursor.selected.value())
    var previous_id = model.selected_source_index.copy()

    var matches = rank_picker_query(model.candidates, model.query, model.options)
    model.matches = matches^

    if len(model.matches) == 0:
        model.cursor.select(None, 0)
        model.selected_source_index = None
        return

    if previous_id:
        for row in range(len(model.matches)):
            if model.matches[row].source_index == previous_id.value():
                model.cursor.select(UInt(row), len(model.matches))
                model.selected_source_index = previous_id.value()
                return

    var nearest_row = min(previous_row, len(model.matches) - 1)
    model.cursor.select(UInt(nearest_row), len(model.matches))
    _adopt_cursor_id(model)


def _control_character(key: KeyEvent, text: StringSlice) -> Bool:
    return (
        key.code == KeyEvent.CHARACTER
        and key.text == text
        and key.modifiers.contains(KeyEvent.CONTROL)
    )


def _handle_key(mut model: _FinderModel, key: KeyEvent) raises -> Bool:
    if key.code == KeyEvent.ESCAPE or _control_character(key, "c"):
        model.outcome = FinderOutcome.ABORTED
        return True
    if key.code == KeyEvent.ENTER:
        model.outcome = FinderOutcome.ACCEPTED
        return True
    if (
        key.code == KeyEvent.TAB
        and model.options.multi
        and (key.modifiers == KeyEvent.NO_MODIFIERS or key.modifiers == KeyEvent.SHIFT)
    ):
        _toggle_cursor_mark(model)
        if key.modifiers == KeyEvent.SHIFT:
            model.cursor.previous(len(model.matches))
        else:
            model.cursor.next(len(model.matches))
        _adopt_cursor_id(model)
        return False
    if key.code == KeyEvent.DOWN or _control_character(key, "n"):
        model.cursor.next(len(model.matches))
        _adopt_cursor_id(model)
    elif key.code == KeyEvent.UP or _control_character(key, "p"):
        model.cursor.previous(len(model.matches))
        _adopt_cursor_id(model)
    elif key.code == KeyEvent.BACKSPACE:
        _erase_last_grapheme(model.query)
        _rerank(model)
    elif key.code == KeyEvent.CHARACTER and not key.modifiers.contains(
        KeyEvent.CONTROL
    ):
        model.query += key.text
        _rerank(model)
    return False


def _item_line(model: _FinderModel, index: Int) raises -> Line:
    var patch = StylePatch(
        foreground=Color.indexed(6),
        add_modifiers=Style.BOLD,
    )
    var line = Line.from_text(model.matches[index].text.copy())
    if model.query != "":
        line = Line.highlighted(
            model.matches[index].text.copy(),
            model.matches[index].positions,
            patch,
        )
    if not model.options.multi:
        return line^

    var marker = String("  ")
    if _is_marked(model, model.matches[index].source_index):
        marker = String("* ")
    var marked_line = Line.from_text(marker^)
    for span_index in range(len(line.spans)):
        marked_line.append(line.spans[span_index])
    return marked_line^


def _items(model: _FinderModel) raises -> MojoList[ListItem]:
    var items = MojoList[ListItem](capacity=len(model.matches))
    for index in range(len(model.matches)):
        items.append(ListItem.from_line(_item_line(model, index)))
    return items^


def _counter_text(model: _FinderModel) -> String:
    var counter = String(_match_count(model)) + "/" + String(_total_count(model))
    if model.options.multi:
        counter += " ("
        counter += String(_marked_count(model))
        counter += ")"
    return counter^


struct _FinderApplication(Application, Copyable):
    comptime Model = _FinderModel
    comptime Message = KeyEvent
    comptime Effect = Bool

    var initial_model: _FinderModel

    def __init__(out self, initial_model: _FinderModel):
        self.initial_model = initial_model.copy()

    def init(mut self) raises -> InitResult[Self.Model, Self.Effect]:
        return InitResult[Self.Model, Self.Effect].ready(self.initial_model.copy())

    def update(
        mut self, mut model: Self.Model, var key: Self.Message
    ) raises -> UpdateResult[Self.Effect]:
        if _handle_key(model, key):
            return UpdateResult[Self.Effect].exit()
        return UpdateResult[Self.Effect].redraw_only()

    def view(self, model: Self.Model, area: Rect, mut buffer: Buffer) raises:
        var regions = Layout.vertical(
            [Constraint.length(1), Constraint.length(1), Constraint.fill()]
        ).split(area)
        if len(regions) < 3:
            return
        render_line(
            Line.from_text(String("> ") + model.query),
            regions[0],
            buffer,
        )
        render_line(
            Line.from_text(_counter_text(model)),
            regions[1],
            buffer,
        )
        var cursor = model.cursor.copy()
        List(_items(model)).render(regions[2], buffer, cursor)

    def on_input(
        self, model: Self.Model, var event: InputEvent
    ) raises -> Optional[Self.Message]:
        if event.isa[KeyEvent]():
            return event[KeyEvent].copy()
        return None


struct _FinderAdapter(RuntimeAdapter):
    comptime ApplicationType = _FinderApplication

    def __init__(out self):
        pass

    def execute(mut self, var command: Command[Self.ApplicationType.Effect]) raises:
        pass

    def start(
        mut self, var subscription: Subscription[Self.ApplicationType.Effect]
    ) raises:
        pass

    def stop(mut self, id: StringSlice) raises:
        pass

    def take_messages(mut self) raises -> MojoList[Self.ApplicationType.Message]:
        return []

    def close(mut self) raises:
        pass

    def close_silently(mut self):
        pass


def _open_controlling_terminal() raises -> Int:
    var path = String("/dev/tty")
    # SAFETY: the owned string stays alive for the complete libc call and
    # provides a NUL-terminated read-only C view; O_RDWR (2) does not require
    # `open`'s optional mode argument.
    var descriptor = external_call["open", c_int, num_fixed_args=2](
        path.as_c_string_slice(),
        c_int(2),
    )
    if descriptor < 0:
        raise Error(
            "interactive mode requires a controlling terminal; run yuragi "
            "from a terminal"
        )
    return Int(descriptor)


def _close_descriptor(descriptor: Int) raises:
    # SAFETY: this function receives the live descriptor returned by `open` and
    # is called exactly once after all terminal host operations have completed.
    var status = external_call["close", c_int](c_int(descriptor))
    if status != 0:
        raise Error("failed to close the controlling terminal")


struct FinderSession:
    """Own one testable finder model and its optional terminal application run."""

    var _model: _FinderModel

    def __init__(
        out self, var candidates: MojoList[Candidate], options: Options
    ) raises:
        """Create an interactive session over owned candidates."""
        var seeded_query = String(options.query)
        var matches = rank_picker_query(candidates, seeded_query, options)
        self._model = _FinderModel(candidates^, options, matches^)

    def __init__(
        out self,
        var candidates: MojoList[Candidate],
        options: Options,
        var initial_matches: MojoList[RankedCandidate],
    ):
        """Create a session from the pure pre-TUI initial ranking."""
        self._model = _FinderModel(candidates^, options, initial_matches^)

    def run(mut self) raises -> FinderOutcome:
        """Run the inline picker on the controlling terminal."""
        var descriptor = _open_controlling_terminal()
        try:
            var capabilities = detect_terminal_capabilities()
            # InlineBackend has no from-terminal constructor. PosixReactor owns
            # the safe terminal-size query and exposes its initial observation.
            var size_probe = PosixReactor(descriptor, descriptor)
            var host = TerminalApplicationHost(
                _FinderAdapter(),
                _FinderApplication(self._model),
                SystemClock(),
                InlineBackend(
                    size_probe.last_size.width,
                    _VIEWPORT_HEIGHT,
                    output_descriptor=descriptor,
                    capabilities=capabilities,
                ),
                options=SessionOptions(alternate_screen=False),
                input_descriptor=descriptor,
                output_descriptor=descriptor,
            )
            host.run()
            self._model = host.application.runtime.model.copy()
        finally:
            _close_descriptor(descriptor)
        return self._model.outcome.copy()

    def selection(self) -> MojoList[Candidate]:
        """Return accepted candidates in source order, or empty after abort."""
        return _resolved_selection(self._model)
