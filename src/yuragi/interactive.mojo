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
from yuragi.pipeline import rank_query
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


def _identity_rows(candidates: Span[Candidate, _]) -> MojoList[RankedCandidate]:
    var rows = MojoList[RankedCandidate](capacity=len(candidates))
    for index in range(len(candidates)):
        rows.append(
            RankedCandidate(
                candidates[index].source_index,
                String(candidates[index].text),
                0,
                MojoList[Int](),
            )
        )
    return rows^


struct _FinderModel(Copyable):
    var candidates: MojoList[Candidate]
    var options: Options
    var query: String
    var matches: MojoList[RankedCandidate]
    var cursor: ListState
    var selected_source_index: Optional[Int]
    var accepted_source_index: Optional[Int]
    var outcome: FinderOutcome

    def __init__(out self, var candidates: MojoList[Candidate], options: Options):
        var matches = _identity_rows(candidates)
        self.options = options.copy()
        self.query = String()
        self.cursor = ListState()
        self.selected_source_index = None
        self.accepted_source_index = None
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

    var matches: MojoList[RankedCandidate]
    if model.query == "":
        matches = _identity_rows(model.candidates)
    else:
        matches = rank_query(model.candidates, model.query, model.options)
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
        model.accepted_source_index = None
        return True
    if key.code == KeyEvent.ENTER:
        model.outcome = FinderOutcome.ACCEPTED
        model.accepted_source_index = model.selected_source_index.copy()
        return True
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


def _items(model: _FinderModel) raises -> MojoList[ListItem]:
    var items = MojoList[ListItem](capacity=len(model.matches))
    var patch = StylePatch(
        foreground=Color.indexed(6),
        add_modifiers=Style.BOLD,
    )
    for index in range(len(model.matches)):
        if model.query == "":
            items.append(
                ListItem.from_line(Line.from_text(model.matches[index].text.copy()))
            )
        else:
            items.append(
                ListItem.from_line(
                    Line.highlighted(
                        model.matches[index].text.copy(),
                        model.matches[index].positions,
                        patch,
                    )
                )
            )
    return items^


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
            Line.from_text(
                String(_match_count(model)) + "/" + String(_total_count(model))
            ),
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

    def __init__(out self, var candidates: MojoList[Candidate], options: Options):
        """Create an interactive session over owned candidates."""
        self._model = _FinderModel(candidates^, options)

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
        """Return the accepted cursor candidate, or an empty list after abort."""
        var selected = MojoList[Candidate]()
        if self._model.outcome != FinderOutcome.ACCEPTED:
            return selected^
        if not self._model.accepted_source_index:
            return selected^
        var accepted_id = self._model.accepted_source_index.value()
        for index in range(len(self._model.candidates)):
            if self._model.candidates[index].source_index == accepted_id:
                selected.append(
                    Candidate(
                        accepted_id,
                        String(self._model.candidates[index].text),
                    )
                )
                break
        return selected^
