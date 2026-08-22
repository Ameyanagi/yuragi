"""Inline MojoTUI application adapter for interactive candidate selection."""

from hibana import CaseMode
from mojotui import (
    Application,
    Buffer,
    Color,
    Command,
    Constraint,
    ControllerActionKind,
    EditorCommand,
    EditorCommandKind,
    EditorControllerAction,
    EditorState,
    InitResult,
    InlineBackend,
    InputEvent,
    KeyEvent,
    Keymap,
    KeymapState,
    Layout,
    Line,
    List,
    ListItem,
    ListState,
    MemoryClipboard,
    PasteEvent,
    PosixReactor,
    Rect,
    RuntimeAdapter,
    Selection,
    SelectionSet,
    SessionOptions,
    Style,
    StylePatch,
    Subscription,
    SystemClock,
    TerminalApplicationHost,
    TextInput,
    UpdateResult,
    detect_terminal_capabilities,
    default_editor_keymap,
    execute_text_input_command,
    render_line,
    text_input_action,
)
from std.collections import List as MojoList, Optional, Span as StdSpan
from std.ffi import c_int, c_ulong, external_call
from std.io import FileDescriptor
from std.utils import Variant

from yuragi.candidate import Candidate
from yuragi.options import Options
from yuragi.pipeline import initial_automation_indexed, language_mode
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


comptime FinderMessage = Variant[KeyEvent, EditorCommand]


struct _FinderModel(Movable):
    var index: SearchIndex
    var identity_mode: Bool
    var case_mode: CaseMode
    var has_limit: Bool
    var limit: Int
    var multi: Bool
    var language_label: String
    var input: EditorState
    var clipboard: MemoryClipboard
    var keymap: Keymap[EditorControllerAction]
    var keymap_state: KeymapState[EditorControllerAction]
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
    ) raises:
        self.case_mode = options.case_mode
        self.has_limit = options.has_limit
        self.limit = options.limit
        self.multi = options.multi
        self.language_label = String(options.language)
        self.input = EditorState(String(options.query))
        self.input.engine.selections = SelectionSet(
            [Selection.caret(self.input.engine.document.byte_length())]
        )
        self.clipboard = MemoryClipboard()
        self.keymap = default_editor_keymap()
        self.keymap_state = KeymapState[EditorControllerAction]()
        self.index = index^
        self.identity_mode = options.query == ""
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


def _query_text(model: _FinderModel) -> String:
    """Return the editor-backed query value used by the shared index."""
    return model.input.engine.document.to_string()


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
    var query = _query_text(model)
    if query == "":
        # One retained row is enough to update the index's complete identity
        # match set; the model resolves all logical rows lazily from the index.
        var page = model.index.search(query, model.case_mode, 1)
        model.total_matches = page.total_matches
        model.matches.clear()
        model.identity_mode = True
    else:
        var page = model.index.search(query, model.case_mode, k)
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


def _apply_editor_command(
    mut model: _FinderModel, command: EditorCommand
) raises -> Bool:
    """Apply one MojoTUI transaction and rerank at most once."""
    var before = model.input.engine.document.version
    var handled = execute_text_input_command(model.input, command, model.clipboard)
    if model.input.engine.document.version != before:
        _rerank(model)
    return handled


def _clear_query(mut model: _FinderModel) raises -> Bool:
    var length = model.input.engine.document.byte_length()
    if length == 0:
        return False
    model.input.engine.selections = SelectionSet([Selection(0, length)])
    return _apply_editor_command(model, EditorCommand.insert(""))


def _is_unicode_whitespace(value: Int) -> Bool:
    """Return whether a scalar has Unicode 17's White_Space property."""
    return (
        (value >= 0x9 and value <= 0xD)
        or value == 0x20
        or value == 0x85
        or value == 0xA0
        or value == 0x1680
        or (value >= 0x2000 and value <= 0x200A)
        or value == 0x2028
        or value == 0x2029
        or value == 0x202F
        or value == 0x205F
        or value == 0x3000
    )


def _grapheme_is_whitespace(grapheme: StringSlice) -> Bool:
    """Classify one extended grapheme without splitting its byte range."""
    var scalar_count = 0
    for scalar in grapheme.codepoints():
        scalar_count += 1
        if not _is_unicode_whitespace(Int(scalar.to_u32())):
            return False
    return scalar_count > 0


def _delete_previous_word(mut model: _FinderModel) raises -> Bool:
    """Delete one Unicode-whitespace-delimited word as one transaction."""
    var selection = model.input.engine.selections.primary_selection()
    if not selection.is_empty():
        return _apply_editor_command(
            model, EditorCommand(EditorCommandKind.DELETE_BACKWARD)
        )
    var cursor = selection.head
    if cursor == 0:
        return False
    var text = _query_text(model)
    var starts = MojoList[Int]()
    var whitespace = MojoList[Bool]()
    var byte_offset = 0
    for grapheme in text.graphemes():
        var end = byte_offset + grapheme.byte_length()
        if end > cursor:
            break
        starts.append(byte_offset)
        whitespace.append(_grapheme_is_whitespace(grapheme))
        byte_offset = end
    if len(starts) == 0:
        return False

    var grapheme_index = len(starts) - 1
    var start = cursor
    while grapheme_index >= 0 and whitespace[grapheme_index]:
        start = starts[grapheme_index]
        grapheme_index -= 1
    while grapheme_index >= 0 and not whitespace[grapheme_index]:
        start = starts[grapheme_index]
        grapheme_index -= 1
    model.input.engine.selections = SelectionSet([Selection(start, cursor)])
    return _apply_editor_command(model, EditorCommand.insert(""))


def _delete_to_line_end(mut model: _FinderModel) raises -> Bool:
    """Delete from the primary caret to its line end as one transaction."""
    var cursor = model.input.engine.selections.primary_selection().head
    var line = model.input.engine.document.line_of_offset(cursor)
    var end = model.input.engine.document.line_end(line)
    if cursor == end:
        return False
    model.input.engine.selections = SelectionSet([Selection(cursor, end)])
    return _apply_editor_command(model, EditorCommand.insert(""))


def _apply_keymap(mut model: _FinderModel, key: KeyEvent) raises -> Bool:
    """Resolve navigation, deletion, clipboard, history, and plain text."""
    var resolution = model.keymap.resolve(model.keymap_state, key, "editor", 0)
    var handled = False
    for index in range(len(resolution.actions)):
        var action = resolution.actions[index].copy()
        if action.kind == ControllerActionKind.EDIT and action.command:
            handled = _apply_editor_command(model, action.command.value()) or handled
    if not resolution.consumed:
        var action = text_input_action(key)
        if action and action.value().command:
            handled = (
                _apply_editor_command(model, action.value().command.value()) or handled
            )
        elif (
            key.code == KeyEvent.CHARACTER
            and key.modifiers == KeyEvent.SHIFT
            and key.text != ""
        ):
            # Enhanced keyboard protocols may report Shift explicitly. Keep it
            # as text while continuing to reject Alt/Control-modified input.
            handled = (
                _apply_editor_command(model, EditorCommand.insert(key.text.copy()))
                or handled
            )
    return handled


def _handle_key(mut model: _FinderModel, key: KeyEvent) raises -> Bool:
    if not key.is_activation():
        return False
    if key.code == KeyEvent.ESCAPE or _control_character(key, "c"):
        model.outcome = FinderOutcome.ABORTED
        return True
    if key.code == KeyEvent.ENTER:
        if not model.selected_source_index:
            return False
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
    elif _control_character(key, "u"):
        _ = _clear_query(model)
    elif _control_character(key, "w"):
        _ = _delete_previous_word(model)
    elif _control_character(key, "a"):
        _ = _apply_editor_command(
            model, EditorCommand.motion(EditorCommandKind.LINE_START)
        )
    elif _control_character(key, "e"):
        _ = _apply_editor_command(
            model, EditorCommand.motion(EditorCommandKind.LINE_END)
        )
    elif _control_character(key, "b"):
        _ = _apply_editor_command(
            model, EditorCommand.motion(EditorCommandKind.MOVE_LEFT)
        )
    elif _control_character(key, "f"):
        _ = _apply_editor_command(
            model, EditorCommand.motion(EditorCommandKind.MOVE_RIGHT)
        )
    elif _control_character(key, "h"):
        _ = _apply_editor_command(
            model, EditorCommand(EditorCommandKind.DELETE_BACKWARD)
        )
    elif _control_character(key, "d"):
        _ = _apply_editor_command(
            model, EditorCommand(EditorCommandKind.DELETE_FORWARD)
        )
    elif _control_character(key, "k"):
        _ = _delete_to_line_end(model)
    else:
        _ = _apply_keymap(model, key)
    return False


def _is_terminal_control(value: Int) -> Bool:
    return (
        (value >= 0 and value <= 0x1F)
        or value == 0x7F
        or (value >= 0x80 and value <= 0x9F)
    )


def _control_escape(value: Int) -> String:
    """Return one visible, inert, fixed-width escape for a control scalar."""
    var escape = String("\\")
    escape += "u{"
    for shift in range(12, -1, -4):
        var digit = (value >> shift) & 0xF
        escape += chr(ord("0") + digit if digit < 10 else ord("A") + digit - 10)
    escape += "}"
    return escape^


def _display_scalar_length(value: Int) -> Int:
    if _is_terminal_control(value):
        return 8
    if value == 0x5C:
        return 2
    return 1


def _display_text(text: StringSlice) -> String:
    """Encode candidate scalars with an injective terminal-safe grammar."""
    var display = String()
    for scalar in text.codepoints():
        var value = Int(scalar.to_u32())
        if _is_terminal_control(value):
            display += _control_escape(value)
        elif value == 0x5C:
            display += "\\"
            display += "\\"
        else:
            display.append(scalar)
    return display^


def _display_positions(text: StringSlice, positions: StdSpan[Int, _]) -> MojoList[Int]:
    """Project source-scalar highlights across every display expansion."""
    var projected = MojoList[Int]()
    var source_index = 0
    var position_index = 0
    var display_index = 0
    for scalar in text.codepoints():
        var value = Int(scalar.to_u32())
        var display_length = _display_scalar_length(value)
        if (
            position_index < len(positions)
            and positions[position_index] == source_index
        ):
            for offset in range(display_length):
                projected.append(display_index + offset)
            position_index += 1
        source_index += 1
        display_index += display_length
    return projected^


def _item_line(model: _FinderModel, index: Int) raises -> Line:
    var patch = StylePatch(
        foreground=Color.indexed(6),
        add_modifiers=Style.BOLD,
    )
    var source_text = (
        model.index.copy_candidate_at(index)
        .text if model.identity_mode else model.matches[index]
        .text.copy()
    )
    var display_text = _display_text(source_text)
    var line = Line.from_text(display_text.copy())
    var query = _query_text(model)
    if query != "":
        var display_positions = _display_positions(
            source_text, model.matches[index].positions
        )
        line = Line.highlighted(
            display_text^,
            display_positions,
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


def _counter_text(model: _FinderModel, shown: Int = -1) -> String:
    var retained = _row_count(model)
    var visible = retained if shown < 0 else shown
    return String(
        "lang=",
        model.language_label,
        " matches=",
        _match_count(model),
        "/",
        _total_count(model),
        " retained=",
        retained,
        " shown=",
        visible,
        " marks=",
        _marked_count(model),
    )


struct _FinderApplication(Application):
    comptime Model = _FinderModel
    comptime Message = FinderMessage
    comptime Effect = Bool

    var initial_model: Optional[_FinderModel]

    def __init__(out self, var initial_model: _FinderModel):
        self.initial_model = initial_model^

    def init(mut self) raises -> InitResult[Self.Model, Self.Effect]:
        return InitResult[Self.Model, Self.Effect].ready(self.initial_model.take())

    def update(
        mut self, mut model: Self.Model, var message: Self.Message
    ) raises -> UpdateResult[Self.Effect]:
        if message.isa[EditorCommand]():
            var handled = _apply_editor_command(model, message[EditorCommand])
            return (
                UpdateResult[Self.Effect]
                .redraw_only() if handled else UpdateResult[Self.Effect]
                .unchanged()
            )
        if _handle_key(model, message[KeyEvent]):
            return UpdateResult[Self.Effect].exit()
        return UpdateResult[Self.Effect].redraw_only()

    def view(self, model: Self.Model, area: Rect, mut buffer: Buffer) raises:
        var regions = Layout.vertical(
            [
                Constraint.length(1),
                Constraint.length(1),
                Constraint.length(1),
                Constraint.fill(),
            ]
        ).split(area)
        if len(regions) < 4:
            return
        render_line(Line.from_text("> "), regions[0], buffer)
        if regions[0].width > 2:
            TextInput(focused=True).render_readonly(
                Rect(regions[0].x + 2, regions[0].y, regions[0].width - 2, 1),
                buffer,
                model.input,
            )
        var window = _visible_window(model, regions[3].height)
        render_line(
            Line.from_text(_counter_text(model, window[1] - window[0])),
            regions[1],
            buffer,
        )
        render_line(
            Line.from_text("↑/↓ select  Enter accept  Esc/Ctrl-C quit  Ctrl-U reset"),
            regions[2],
            buffer,
        )
        if _row_count(model) == 0:
            render_line(
                Line.from_text("No matches — edit the query or Ctrl-U to reset"),
                regions[3],
                buffer,
            )
            return
        var cursor = ListState()
        if model.cursor.selected and window[1] > window[0]:
            cursor.select(
                UInt(Int(model.cursor.selected.value()) - window[0]),
                window[1] - window[0],
            )
        List(_items(model, window[0], window[1])).render(regions[3], buffer, cursor)

    def on_input(
        self, model: Self.Model, var event: InputEvent
    ) raises -> Optional[Self.Message]:
        if event.isa[PasteEvent]():
            return FinderMessage(EditorCommand.insert(event[PasteEvent].text))
        if event.isa[KeyEvent]() and event[KeyEvent].is_activation():
            return FinderMessage(event[KeyEvent].copy())
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


struct _OwnedDescriptor(Movable):
    """Close one controlling-terminal descriptor on every exit path."""

    var value: Int
    var open: Bool

    def __init__(out self, value: Int):
        self.value = value
        self.open = True

    def close(mut self) raises:
        if not self.open:
            return
        _close_descriptor(self.value)
        self.open = False

    def __deinit__(deinit self):
        if self.open:
            _ = external_call["close", c_int](c_int(self.value))


struct FinderSession:
    """Own one testable finder model and its optional terminal application run."""

    var _model: _FinderModel
    var _ran: Bool
    var _terminal_outcome: FinderOutcome
    var _terminal_selection: MojoList[Candidate]

    def __init__(
        out self, var candidates: MojoList[Candidate], options: Options
    ) raises:
        """Create an interactive session over owned candidates."""
        var index = SearchIndex(candidates^, language_mode(options))
        var initial = initial_automation_indexed(index, options)
        var total_matches = initial.total_matches
        var matches = initial^.take_matches()
        self._model = _FinderModel(index^, options, matches^, total_matches)
        self._ran = False
        self._terminal_outcome = FinderOutcome.ABORTED
        self._terminal_selection = MojoList[Candidate]()

    def __init__(
        out self,
        var index: SearchIndex,
        options: Options,
        var initial_matches: MojoList[RankedCandidate],
        total_matches: Int,
    ) raises:
        """Create a session from the pure pre-TUI initial ranking."""
        self._model = _FinderModel(index^, options, initial_matches^, total_matches)
        self._ran = False
        self._terminal_outcome = FinderOutcome.ABORTED
        self._terminal_selection = MojoList[Candidate]()

    def run(mut self) raises -> FinderOutcome:
        """Run the inline picker on the controlling terminal."""
        # Keep the session fully initialized while its large live model is
        # temporarily owned by the host. The placeholder has an empty corpus;
        # no SearchIndex or candidate storage is copied.
        var placeholder_candidates = MojoList[Candidate]()
        var placeholder_index = SearchIndex(
            placeholder_candidates^, self._model.index.language()
        )
        var placeholder_options = Options()
        placeholder_options.language = String(self._model.language_label)
        var placeholder_matches = MojoList[RankedCandidate]()
        var host_model = _FinderModel(
            placeholder_index^,
            placeholder_options,
            placeholder_matches^,
            0,
        )
        swap(self._model, host_model)
        var descriptor = _OwnedDescriptor(_open_controlling_terminal())
        var capabilities = detect_terminal_capabilities()
        var size_probe = PosixReactor(descriptor.value, descriptor.value)
        var host = TerminalApplicationHost(
            _FinderAdapter(),
            _FinderApplication(host_model^),
            SystemClock(),
            InlineBackend(
                size_probe.last_size.width,
                _VIEWPORT_HEIGHT,
                output_descriptor=descriptor.value,
                capabilities=capabilities,
            ),
            options=SessionOptions(alternate_screen=False),
            input_descriptor=descriptor.value,
            output_descriptor=descriptor.value,
        )
        host.run()
        ref finished_model = host.application.runtime.model
        self._terminal_outcome = finished_model.outcome.copy()
        self._terminal_selection = _resolved_selection(finished_model)
        self._ran = True
        descriptor.close()
        return self._terminal_outcome.copy()

    def selection(self) -> MojoList[Candidate]:
        """Return accepted candidates in source order, or empty after abort."""
        if self._ran:
            return self._terminal_selection.copy()
        return _resolved_selection(self._model)

    def take_selection(mut self) -> MojoList[Candidate]:
        """Consume accepted terminal output without copying its strings."""
        if not self._ran:
            return _resolved_selection(self._model)
        var selected = MojoList[Candidate]()
        swap(selected, self._terminal_selection)
        return selected^
