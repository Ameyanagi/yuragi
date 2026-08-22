"""Inline MojoTUI application adapter for interactive candidate selection."""

from hibana import CaseMode
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
from std.ffi import c_int, c_ulong, external_call
from std.io import FileDescriptor

from yuragi.candidate import Candidate
from yuragi.options import Options
from yuragi.pipeline import initial_automation_indexed
from yuragi.ranking import RankedCandidate
from yuragi.search_index import SearchIndex


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
    var index: SearchIndex
    var identity_mode: Bool
    var case_mode: CaseMode
    var has_limit: Bool
    var limit: Int
    var multi: Bool
    var query: String
    var matches: MojoList[RankedCandidate]
    var total_matches: Int
    var cursor: ListState
    var selected_source_index: Optional[Int]
    var marked_source_indices: MojoList[Int]
    var outcome: FinderOutcome

    def __init__(
        out self,
        var index: SearchIndex,
        options: Options,
        var matches: MojoList[RankedCandidate],
        total_matches: Int,
    ):
        self.case_mode = options.case_mode
        self.has_limit = options.has_limit
        self.limit = options.limit
        self.multi = options.multi
        self.query = String(options.query)
        self.index = index^
        self.identity_mode = self.query == ""
        self.cursor = ListState()
        self.selected_source_index = None
        self.marked_source_indices = MojoList[Int]()
        self.outcome = FinderOutcome.ABORTED
        if self.identity_mode:
            self.matches = MojoList[RankedCandidate]()
            self.total_matches = len(self.index)
            if len(self.index) > 0:
                self.cursor.select(UInt(0), len(self.index))
                self.selected_source_index = self.index.source_index_at(0)
        else:
            if len(matches) > 0:
                self.cursor.select(UInt(0), len(matches))
                self.selected_source_index = matches[0].source_index
            self.matches = matches^
            self.total_matches = total_matches


def _match_count(model: _FinderModel) -> Int:
    return model.total_matches


def _total_count(model: _FinderModel) -> Int:
    return len(model.index)


def _row_count(model: _FinderModel) -> Int:
    """Return visible logical rows without materializing identity candidates."""
    if not model.identity_mode:
        return len(model.matches)
    if model.has_limit:
        return min(model.limit, len(model.index))
    return len(model.index)


def _row_source_index(model: _FinderModel, row: Int) -> Int:
    if model.identity_mode:
        return model.index.source_index_at(row)
    return model.matches[row].source_index


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
    var selected = model.selected_source_index.value()
    if (
        not _is_marked(model, selected)
        and model.has_limit
        and len(model.marked_source_indices) >= model.limit
    ):
        return
    model.marked_source_indices = _toggled_mark_order(
        model.marked_source_indices,
        selected,
    )


def _accepted_source_indices(model: _FinderModel) -> MojoList[Int]:
    """Resolve accepted candidate IDs while retaining mark order internally."""
    if model.multi and len(model.marked_source_indices) > 0:
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
        for candidate_index in range(len(model.index)):
            if model.index.source_index_at(candidate_index) == accepted_id:
                selected.append(model.index.copy_candidate_at(candidate_index))
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
    model.selected_source_index = _row_source_index(model, row)


def _rerank(mut model: _FinderModel) raises:
    var previous_row = 0
    if model.cursor.selected:
        previous_row = Int(model.cursor.selected.value())
    var previous_id = model.selected_source_index.copy()

    var k = model.limit if model.has_limit else len(model.index)
    if model.query == "":
        # One retained row is enough to update the index's complete identity
        # match set; the model resolves all logical rows lazily from the index.
        var page = model.index.search(model.query, model.case_mode, 1)
        model.total_matches = page.total_matches
        model.matches.clear()
        model.identity_mode = True
    else:
        var page = model.index.search(model.query, model.case_mode, k)
        model.total_matches = page.total_matches
        model.matches = page^.take_rows()
        model.identity_mode = False

    var row_count = _row_count(model)
    if row_count == 0:
        model.cursor.select(None, 0)
        model.selected_source_index = None
        return

    if previous_id:
        for row in range(row_count):
            if _row_source_index(model, row) == previous_id.value():
                model.cursor.select(UInt(row), row_count)
                model.selected_source_index = previous_id.value()
                return

    var nearest_row = min(previous_row, row_count - 1)
    model.cursor.select(UInt(nearest_row), row_count)
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
        and model.multi
        and (key.modifiers == KeyEvent.NO_MODIFIERS or key.modifiers == KeyEvent.SHIFT)
    ):
        _toggle_cursor_mark(model)
        if key.modifiers == KeyEvent.SHIFT:
            model.cursor.previous(_row_count(model))
        else:
            model.cursor.next(_row_count(model))
        _adopt_cursor_id(model)
        return False
    if key.code == KeyEvent.DOWN or _control_character(key, "n"):
        model.cursor.next(_row_count(model))
        _adopt_cursor_id(model)
    elif key.code == KeyEvent.UP or _control_character(key, "p"):
        model.cursor.previous(_row_count(model))
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
    var text = (
        model.index.copy_candidate_at(index)
        .text if model.identity_mode else model.matches[index]
        .text.copy()
    )
    var line = Line.from_text(text.copy())
    if model.query != "":
        line = Line.highlighted(
            text^,
            model.matches[index].positions,
            patch,
        )
    if not model.multi:
        return line^

    var marker = String("  ")
    if _is_marked(model, _row_source_index(model, index)):
        marker = String("* ")
    var marked_line = Line.from_text(marker^)
    for span_index in range(len(line.spans)):
        marked_line.append(line.spans[span_index])
    return marked_line^


def _visible_window(model: _FinderModel, height: Int) -> Tuple[Int, Int]:
    """Return a deterministic half-open row window around the cursor."""
    var row_count = _row_count(model)
    if height <= 0 or row_count == 0:
        return (0, 0)
    var count = min(height, row_count)
    var selected = 0
    if model.cursor.selected:
        selected = Int(model.cursor.selected.value())
    var start = max(0, selected - count // 2)
    start = min(start, row_count - count)
    return (start, start + count)


def _items(
    model: _FinderModel, start: Int = 0, end: Int = -1
) raises -> MojoList[ListItem]:
    """Materialize only the requested visible half-open result window."""
    var row_count = _row_count(model)
    var bounded_end = row_count if end < 0 else min(end, row_count)
    var bounded_start = min(max(start, 0), bounded_end)
    var items = MojoList[ListItem](capacity=bounded_end - bounded_start)
    for index in range(bounded_start, bounded_end):
        items.append(ListItem.from_line(_item_line(model, index)))
    return items^


def _counter_text(model: _FinderModel) -> String:
    var counter = String(_match_count(model)) + "/" + String(_total_count(model))
    if model.multi:
        counter += " ("
        counter += String(_marked_count(model))
        counter += ")"
    return counter^


struct _FinderApplication(Application):
    comptime Model = _FinderModel
    comptime Message = KeyEvent
    comptime Effect = Bool

    var initial_model: Optional[_FinderModel]

    def __init__(out self, initial_model: _FinderModel):
        self.initial_model = initial_model.copy()

    def init(mut self) raises -> InitResult[Self.Model, Self.Effect]:
        return InitResult[Self.Model, Self.Effect].ready(self.initial_model.take())

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
        var window = _visible_window(model, regions[2].height)
        var cursor = ListState()
        if model.cursor.selected and window[1] > window[0]:
            cursor.select(
                UInt(Int(model.cursor.selected.value()) - window[0]),
                window[1] - window[0],
            )
        List(_items(model, window[0], window[1])).render(regions[2], buffer, cursor)

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
    # macOS poll(2) reports POLLNVAL for descriptors opened through the
    # /dev/tty alias, which would fail mojotui's reactor. Resolve the real
    # controlling-terminal device from a standard descriptor that is a TTY
    # and open that device; fall back to /dev/tty only when none is.
    var standard_descriptors: MojoList[Int] = [2, 1, 0]
    var name = MojoList[UInt8](length=256, fill=0)
    for index in range(len(standard_descriptors)):
        var candidate = standard_descriptors[index]
        if not FileDescriptor(candidate).isatty():
            continue
        # SAFETY: ttyname_r writes a NUL-terminated device path into the
        # owned buffer, which stays alive for both libc calls; O_RDWR (2)
        # does not require `open`'s optional mode argument.
        var status = external_call["ttyname_r", c_int](
            c_int(candidate), Pointer(to=name[0]), c_ulong(len(name))
        )
        if status != 0:
            continue
        var descriptor = external_call["open", c_int, num_fixed_args=2](
            Pointer(to=name[0]), c_int(2)
        )
        if descriptor >= 0:
            return Int(descriptor)
    var path = String("/dev/tty")
    # SAFETY: the owned string stays alive for the complete libc call and
    # provides a NUL-terminated read-only C view.
    var fallback = external_call["open", c_int, num_fixed_args=2](
        path.as_c_string_slice(),
        c_int(2),
    )
    if fallback < 0:
        raise Error(
            "interactive mode requires a controlling terminal; run yuragi "
            "from a terminal"
        )
    return Int(fallback)


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
        var index = SearchIndex(candidates^)
        var initial = initial_automation_indexed(index, options)
        var total_matches = initial.total_matches
        var matches = initial^.take_matches()
        self._model = _FinderModel(index^, options, matches^, total_matches)

    def __init__(
        out self,
        var index: SearchIndex,
        options: Options,
        var initial_matches: MojoList[RankedCandidate],
        total_matches: Int,
    ):
        """Create a session from the pure pre-TUI initial ranking."""
        self._model = _FinderModel(index^, options, initial_matches^, total_matches)

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
