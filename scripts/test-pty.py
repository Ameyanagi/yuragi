#!/usr/bin/env python3
"""Exercise Yuragi's compiled interactive contract through a real PTY."""

from __future__ import annotations

import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import tempfile
import time
import unicodedata
from pathlib import Path
from typing import Callable


READ_TIMEOUT_SECONDS = 5.0
CANDIDATES = b"alpha\nbravo\ncharlie\n"


class TerminalScreen:
    """Track the small ANSI subset emitted by MojoTUI's inline backend."""

    def __init__(self, rows: int = 24, columns: int = 80) -> None:
        self.rows = rows
        self.columns = columns
        self.cells = [[" "] * columns for _ in range(rows)]
        self.row = 0
        self.column = 0
        self.saved_row = 0
        self.saved_column = 0
        self.pending = bytearray()
        self.utf8_pending = bytearray()

    def feed(self, data: bytes) -> None:
        self.pending.extend(data)
        offset = 0
        while offset < len(self.pending):
            value = self.pending[offset]
            if value == 0x1B:
                consumed = self._consume_escape(offset)
                if consumed == 0:
                    break
                offset += consumed
            else:
                self._consume_byte(value)
                offset += 1
        del self.pending[:offset]

    def _consume_escape(self, offset: int) -> int:
        if offset + 1 >= len(self.pending):
            return 0
        if self.pending[offset + 1] != ord("["):
            return 2

        final_offset = offset + 2
        while final_offset < len(self.pending):
            value = self.pending[final_offset]
            if 0x40 <= value <= 0x7E:
                raw_parameters = bytes(self.pending[offset + 2 : final_offset])
                self._consume_csi(raw_parameters, chr(value))
                return final_offset - offset + 1
            final_offset += 1
        return 0

    def _parameters(self, raw: bytes) -> list[int]:
        text = raw.decode("ascii", errors="ignore").lstrip("?=>")
        if not text:
            return []
        result = []
        for field in text.split(";"):
            result.append(int(field) if field.isdigit() else 0)
        return result

    def _amount(self, parameters: list[int]) -> int:
        return max(parameters[0], 1) if parameters else 1

    def _consume_csi(self, raw_parameters: bytes, final: str) -> None:
        parameters = self._parameters(raw_parameters)
        if final == "A":
            self.row = max(self.row - self._amount(parameters), 0)
        elif final == "B":
            self.row = min(self.row + self._amount(parameters), self.rows - 1)
        elif final == "C":
            self.column = min(
                self.column + self._amount(parameters), self.columns - 1
            )
        elif final == "D":
            self.column = max(self.column - self._amount(parameters), 0)
        elif final in ("H", "f"):
            row = parameters[0] if parameters else 1
            column = parameters[1] if len(parameters) > 1 else 1
            self.row = min(max(row - 1, 0), self.rows - 1)
            self.column = min(max(column - 1, 0), self.columns - 1)
        elif final == "G":
            column = parameters[0] if parameters else 1
            self.column = min(max(column - 1, 0), self.columns - 1)
        elif final == "J" and parameters and parameters[0] == 2:
            self.cells = [[" "] * self.columns for _ in range(self.rows)]
        elif final == "K":
            mode = parameters[0] if parameters else 0
            if mode == 2:
                self.cells[self.row] = [" "] * self.columns
            elif mode == 1:
                for column in range(self.column + 1):
                    self.cells[self.row][column] = " "
            else:
                for column in range(self.column, self.columns):
                    self.cells[self.row][column] = " "
        elif final == "s":
            self.saved_row = self.row
            self.saved_column = self.column
        elif final == "u":
            self.row = self.saved_row
            self.column = self.saved_column

    def _consume_byte(self, value: int) -> None:
        if self.utf8_pending or value >= 0x80:
            self.utf8_pending.append(value)
            try:
                text = self.utf8_pending.decode("utf-8")
            except UnicodeDecodeError as error:
                if error.reason == "unexpected end of data":
                    return
                self.utf8_pending.clear()
                return
            self.utf8_pending.clear()
            for character in text:
                self._write_character(character)
            return
        if value == 0x0D:
            self.column = 0
        elif value == 0x0A:
            self.row = min(self.row + 1, self.rows - 1)
        elif value == 0x08:
            self.column = max(self.column - 1, 0)
        elif value == 0x09:
            self.column = min((self.column // 8 + 1) * 8, self.columns - 1)
        elif 0x20 <= value <= 0x7E:
            self._write_character(chr(value))

    def _write_character(self, character: str) -> None:
        if unicodedata.combining(character) or unicodedata.category(character) in (
            "Cf",
            "Me",
            "Mn",
        ):
            return
        width = 2 if unicodedata.east_asian_width(character) in ("F", "W") else 1
        self.cells[self.row][self.column] = character
        if width == 2 and self.column + 1 < self.columns:
            self.cells[self.row][self.column + 1] = ""
        self.column = min(self.column + width, self.columns - 1)

    def line(self, row: int) -> str:
        return "".join(self.cells[row]).rstrip()

    def contains(self, text: str) -> bool:
        return any(text in self.line(row) for row in range(self.rows))

    def selected(self, text: str) -> bool:
        return any(
            self.line(row).startswith(">") and text in self.line(row)
            for row in range(self.rows)
        )

    def snapshot(self) -> list[str]:
        return [line for row in range(self.rows) if (line := self.line(row))]


def comparable_attributes(attributes: list[object]) -> list[object]:
    """Ignore kernel-owned transient flags while comparing user configuration."""
    result = list(attributes)
    result[3] = int(result[3]) & ~int(getattr(termios, "PENDIN", 0))
    result[6] = list(result[6])
    return result


def fail(
    name: str, message: str, output: bytearray, screen: TerminalScreen
) -> None:
    raise AssertionError(
        f"{name}: {message}; screen={screen.snapshot()!r}; ui={bytes(output)!r}"
    )


def read_pty(
    master: int, output: bytearray, screen: TerminalScreen
) -> bool:
    try:
        chunk = os.read(master, 4096)
    except OSError:
        return False
    if not chunk:
        return False
    output.extend(chunk)
    screen.feed(chunk)
    return True


def read_until(
    name: str,
    master: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
    description: str,
    condition: Callable[[TerminalScreen], bool],
) -> None:
    deadline = time.monotonic() + READ_TIMEOUT_SECONDS
    while not condition(screen) and time.monotonic() < deadline:
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            read_pty(master, output, screen)
        if process.poll() is not None and not readable:
            break
    if not condition(screen):
        fail(
            name,
            f"child did not render {description}; exit={process.poll()}",
            output,
            screen,
        )


def wait_for_exit(
    name: str,
    master: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> int:
    deadline = time.monotonic() + READ_TIMEOUT_SECONDS
    while process.poll() is None and time.monotonic() < deadline:
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            read_pty(master, output, screen)
    if process.poll() is None:
        process.kill()
        process.wait()
        fail(name, "child timed out", output, screen)

    while select.select([master], [], [], 0)[0]:
        if not read_pty(master, output, screen):
            break
    return process.returncode


def wait_for_initial_picker(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
    *,
    multi: bool = False,
) -> None:
    counter = (
        "lang=auto matches=3/3 retained=3 shown=3 marks="
        + ("0" if multi else "0")
    )

    def picker_is_ready(current: TerminalScreen) -> bool:
        return (
            current.line(1).startswith(counter)
            and current.contains("alpha")
            and current.contains("bravo")
            and current.contains("charlie")
        )

    read_until(
        name,
        master,
        process,
        output,
        screen,
        "initial picker status with all candidates",
        picker_is_ready,
    )
    attributes = termios.tcgetattr(slave)
    if int(attributes[3]) & (termios.ICANON | termios.ECHO):
        fail(name, "controlling terminal did not enter raw mode", output, screen)


Driver = Callable[
    [
        str,
        int,
        int,
        subprocess.Popen[bytes],
        bytearray,
        TerminalScreen,
    ],
    None,
]


def drive_picker_accepts(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(name, master, slave, process, output, screen)

    os.write(master, b"b")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "query 'b' with counter 1/3",
        lambda current: current.line(0).startswith("> b")
        and current.line(1).startswith("lang=auto matches=1/3"),
    )
    os.write(master, b"r")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "query 'br'",
        lambda current: current.line(0).startswith("> br"),
    )
    os.write(master, b"\r")


def drive_escape(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(name, master, slave, process, output, screen)
    os.write(master, b"\x1b")


def drive_control_c(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(name, master, slave, process, output, screen)
    os.write(master, b"\x03")


def drive_control_u_clears_query(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(name, master, slave, process, output, screen)
    os.write(master, b"br")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "query 'br'",
        lambda current: current.line(0).startswith("> br"),
    )
    os.write(master, b"\x15")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "empty query with counter 3/3 after Ctrl-U",
        lambda current: current.line(0) == ">"
        and current.line(1).startswith("lang=auto matches=3/3"),
    )
    os.write(master, b"\x1b")


def drive_control_w_deletes_word(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(name, master, slave, process, output, screen)
    os.write(master, b"br")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "query 'br'",
        lambda current: current.line(0).startswith("> br"),
    )
    os.write(master, b"\x17")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "empty query with counter 3/3 after Ctrl-W",
        lambda current: current.line(0) == ">"
        and current.line(1).startswith("lang=auto matches=3/3"),
    )
    os.write(master, b"\x1b")


def drive_terminal_editor_bindings(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(name, master, slave, process, output, screen)
    os.write(master, b"lpha")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "partial query before Ctrl-A",
        lambda current: current.line(0).startswith("> lpha"),
    )

    # Ctrl-A must move to the start, not select all as in the generic editor
    # keymap. Inserting `a` therefore restores the exact `alpha` query.
    os.write(master, b"\x01a")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "Ctrl-A line start without select-all",
        lambda current: current.line(0).startswith("> alpha")
        and current.line(1).startswith("lang=auto matches=1/3"),
    )

    # Ctrl-A, Ctrl-F, Ctrl-K leaves the first grapheme. Undo restores the
    # query through the unchanged default Ctrl-Z binding.
    os.write(master, b"\x01\x06\x0b")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "Ctrl-F movement and Ctrl-K kill-to-end",
        lambda current: current.line(0) == "> a",
    )
    os.write(master, b"\x1a")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "Ctrl-Z restores Ctrl-K transaction",
        lambda current: current.line(0).startswith("> alpha"),
    )

    os.write(master, b"\x05\x02\x08")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "Ctrl-E, Ctrl-B, and Ctrl-H edit at the caret",
        lambda current: current.line(0).startswith("> alpa"),
    )
    os.write(master, b"\x1a\x01\x04")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "Ctrl-D forward deletion",
        lambda current: current.line(0).startswith("> lpha"),
    )
    os.write(master, b"\x1a\r")


def drive_multi(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(
        name, master, slave, process, output, screen, multi=True
    )

    os.write(master, b"\t")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "alpha marked and cursor on bravo",
        lambda current: current.contains("* alpha")
        and current.selected("bravo"),
    )
    os.write(master, b"\t")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "alpha and bravo marked with cursor on charlie",
        lambda current: current.contains("* alpha")
        and current.contains("* bravo")
        and current.selected("charlie"),
    )
    os.write(master, b"\r")


def drive_multi_reverse_order(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(
        name, master, slave, process, output, screen, multi=True
    )

    os.write(master, b"\x1b[B")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "cursor on bravo",
        lambda current: current.selected("bravo"),
    )
    os.write(master, b"\x1b[B")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "cursor on charlie",
        lambda current: current.selected("charlie"),
    )

    # CSI Z is Shift-TAB: mark charlie and move to bravo. A following TAB
    # marks bravo and moves back to charlie, so mark order is the reverse of
    # the required source-ordered stdout.
    os.write(master, b"\x1b[Z")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "charlie marked and cursor on bravo",
        lambda current: current.contains("* charlie")
        and current.selected("bravo"),
    )
    os.write(master, b"\t")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "charlie and bravo marked",
        lambda current: current.contains("* charlie")
        and current.contains("* bravo"),
    )
    os.write(master, b"\r")


def drive_paste_transaction(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_initial_picker(name, master, slave, process, output, screen)
    os.write(master, b"\x1b[200~br\n\x1b[201~")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "one sanitized paste with one retained match",
        lambda current: current.line(0).startswith("> br")
        and current.line(1).startswith("lang=auto matches=1/3 retained=1"),
    )
    os.write(master, b"\r")


def drive_no_match_enter_stays_open(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "no-match guidance",
        lambda current: current.line(1).startswith("lang=auto matches=0/3")
        and current.contains("No matches"),
    )
    os.write(master, b"\r")
    time.sleep(0.1)
    if process.poll() is not None:
        fail(name, "Enter closed a picker with no selected row", output, screen)
    os.write(master, b"\x1b")


def drive_language_match(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    language = name.split()[0]
    expected_matches = 2 if language == "ko" else 1
    read_until(
        name,
        master,
        process,
        output,
        screen,
        f"{language} language status and phonetic match",
        lambda current: current.line(1).startswith(
            f"lang={language} matches={expected_matches}/"
        ),
    )
    os.write(master, b"\r")


def wait_for_control_candidates(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "distinct sanitized control candidate rows",
        lambda current: current.line(1).startswith(
            "lang=auto matches=2/2 retained=2 shown=2 marks=0"
        )
        and current.selected(r"a\u{000A}b")
        and current.contains("ab"),
    )
    attributes = termios.tcgetattr(slave)
    if int(attributes[3]) & (termios.ICANON | termios.ECHO):
        fail(name, "controlling terminal did not enter raw mode", output, screen)


def drive_read0_accepts_control_candidate(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_control_candidates(name, master, slave, process, output, screen)
    os.write(master, b"\r")


def drive_read0_accepts_plain_candidate(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    wait_for_control_candidates(name, master, slave, process, output, screen)
    os.write(master, b"\x1b[B")
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "plain candidate selected independently of the control candidate",
        lambda current: current.selected("ab")
        and current.contains(r"a\u{000A}b"),
    )
    os.write(master, b"\r")


def drive_c1_candidate(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    read_until(
        name,
        master,
        process,
        output,
        screen,
        "inert C1 escape in the selected row",
        lambda current: current.line(1).startswith(
            "lang=auto matches=2/2 retained=2 shown=2 marks=0"
        )
        and current.selected(r"a\u{009B}b")
        and current.contains("plain"),
    )
    attributes = termios.tcgetattr(slave)
    if int(attributes[3]) & (termios.ICANON | termios.ECHO):
        fail(name, "controlling terminal did not enter raw mode", output, screen)
    os.write(master, b"\r")


def drive_injective_collision_pair(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    if name.startswith("C0"):
        actual_display = r"a\u{000A}b"
        literal_display = "a␊b"
    else:
        actual_display = r"c\u{009B}d"
        literal_display = r"c\\u{009B}d"

    read_until(
        name,
        master,
        process,
        output,
        screen,
        "both visually distinct sides of the display collision pair",
        lambda current: current.line(1).startswith(
            "lang=auto matches=2/2 retained=2 shown=2 marks=0"
        )
        and current.selected(actual_display)
        and current.contains(literal_display),
    )
    attributes = termios.tcgetattr(slave)
    if int(attributes[3]) & (termios.ICANON | termios.ECHO):
        fail(name, "controlling terminal did not enter raw mode", output, screen)

    if "literal" in name:
        os.write(master, b"\x1b[B")
        read_until(
            name,
            master,
            process,
            output,
            screen,
            "literal side selected independently",
            lambda current: current.selected(literal_display)
            and current.contains(actual_display),
        )
    os.write(master, b"\r")


def drive_large_query_cancellation(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    read_until(
        name, master, process, output, screen, "large corpus picker",
        lambda current: current.contains("matches=10000/10000"),
    )
    os.write(master, "京".encode())
    read_until(
        name, master, process, output, screen, "searching query frame",
        lambda current: current.line(0).startswith("> 京")
        and current.contains("Searching"),
    )
    # A new generation must reach the screen before the old ranking finishes.
    os.write(master, b"\x15" + "不存在".encode())
    read_until(
        name, master, process, output, screen, "replacement query frame",
        lambda current: current.line(0).startswith("> 不存在")
        and current.contains("Searching"),
    )
    os.write(master, b"\x03" if "Ctrl-C" in name else b"\x1b")


def drive_seeded_large_query_finishes(
    name: str,
    master: int,
    slave: int,
    process: subprocess.Popen[bytes],
    output: bytearray,
    screen: TerminalScreen,
) -> None:
    read_until(
        name, master, process, output, screen, "exact completed seeded query",
        lambda current: current.contains("matches=1000/1000 retained=3")
        and not current.contains("Searching"),
    )
    os.write(master, b"\r")


def run_case(
    binary: Path,
    name: str,
    arguments: list[str],
    expected_stdout: bytes,
    expected_exit: int,
    *,
    driver: Driver | None = None,
    check_restoration: bool = False,
    candidates: bytes = CANDIDATES,
) -> None:
    master, slave = pty.openpty()
    config_directory = tempfile.TemporaryDirectory(prefix="yuragi-pty-config-")
    process: subprocess.Popen[bytes] | None = None
    output = bytearray()
    screen = TerminalScreen()
    try:
        fcntl.ioctl(
            slave,
            termios.TIOCSWINSZ,
            struct.pack("HHHH", screen.rows, screen.columns, 0, 0),
        )
        original_attributes = termios.tcgetattr(slave)
        environment = os.environ.copy()
        environment["TERM"] = "xterm-256color"
        for key in ("YURAGI_LANG", "YURAGI_CASE", "YURAGI_LIMIT"):
            environment.pop(key, None)
        environment["YURAGI_CONFIG_FILE"] = str(
            Path(config_directory.name) / "absent.toml"
        )
        # Yuragi resolves its terminal from the first standard descriptor
        # that is a TTY (here stderr, the PTY slave) via ttyname_r, so the
        # child needs no new session or TIOCSCTTY; the parent can keep
        # inspecting the slave after the child exits.
        process = subprocess.Popen(
            [str(binary), *arguments],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=slave,
            close_fds=True,
            env=environment,
        )
        if process.stdin is None:
            fail(name, "stdin pipe was not created", output, screen)
        process.stdin.write(candidates)
        process.stdin.close()
        process.stdin = None

        if driver is not None:
            driver(name, master, slave, process, output, screen)
        exit_code = wait_for_exit(name, master, process, output, screen)

        if process.stdout is None:
            fail(name, "stdout pipe was not created", output, screen)
        actual_stdout = process.stdout.read()
        if actual_stdout != expected_stdout:
            fail(
                name,
                f"expected stdout {expected_stdout!r}, got {actual_stdout!r}",
                output,
                screen,
            )
        if exit_code != expected_exit:
            fail(
                name,
                f"expected exit {expected_exit}, got {exit_code}",
                output,
                screen,
            )

        if check_restoration:
            restored_attributes = termios.tcgetattr(slave)
            if comparable_attributes(restored_attributes) != comparable_attributes(
                original_attributes
            ):
                fail(
                    name,
                    "terminal attributes were not restored\n"
                    f"original={original_attributes!r}\n"
                    f"restored={restored_attributes!r}",
                    output,
                    screen,
                )
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
                process.wait()
            if process.stdin is not None:
                process.stdin.close()
            if process.stdout is not None:
                process.stdout.close()
        os.close(master)
        os.close(slave)
        config_directory.cleanup()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: test-pty.py PATH_TO_YURAGI", file=sys.stderr)
        return 2
    binary = Path(sys.argv[1]).resolve()

    run_case(
        binary,
        "picker accepts narrowed match",
        [],
        b"bravo\n",
        0,
        driver=drive_picker_accepts,
        check_restoration=True,
    )
    run_case(binary, "escape aborts", [], b"", 130, driver=drive_escape)
    run_case(binary, "control-c aborts", [], b"", 130, driver=drive_control_c)
    run_case(
        binary,
        "control-u clears query",
        [],
        b"",
        130,
        driver=drive_control_u_clears_query,
    )
    run_case(
        binary,
        "control-w deletes word",
        [],
        b"",
        130,
        driver=drive_control_w_deletes_word,
    )
    run_case(
        binary,
        "terminal editor control bindings",
        [],
        b"alpha\n",
        0,
        driver=drive_terminal_editor_bindings,
    )
    run_case(
        binary,
        "select-1 accepts initial match",
        ["--select-1", "--query", "charlie"],
        b"charlie\n",
        0,
    )
    run_case(
        binary,
        "exit-0 exits on no initial match",
        ["--exit-0", "--query", "zzz"],
        b"",
        1,
    )
    run_case(
        binary,
        "multi accepts two marks",
        ["--multi"],
        b"alpha\nbravo\n",
        0,
        driver=drive_multi,
    )
    run_case(
        binary,
        "multi emits source order",
        ["--multi", "--query", ""],
        b"bravo\ncharlie\n",
        0,
        driver=drive_multi_reverse_order,
    )
    run_case(
        binary,
        "paste reranks once",
        [],
        b"bravo\n",
        0,
        driver=drive_paste_transaction,
    )
    run_case(
        binary,
        "no-match Enter stays open",
        ["--query", "zzz"],
        b"",
        130,
        driver=drive_no_match_enter_stays_open,
    )
    run_case(
        binary,
        "read0 selects embedded-newline candidate",
        ["--read0", "--print0"],
        b"a\nb\0",
        0,
        driver=drive_read0_accepts_control_candidate,
        check_restoration=True,
        candidates=b"a\nb\0ab\0",
    )
    run_case(
        binary,
        "read0 selects plain candidate independently",
        ["--read0", "--print0"],
        b"ab\0",
        0,
        driver=drive_read0_accepts_plain_candidate,
        check_restoration=True,
        candidates=b"a\nb\0ab\0",
    )
    run_case(
        binary,
        "C1 display is inert and selection preserves bytes",
        ["--print0"],
        b"a\xc2\x9bb\0",
        0,
        driver=drive_c1_candidate,
        check_restoration=True,
        candidates=b"a\xc2\x9bb\nplain\n",
    )
    run_case(
        binary,
        "C0 actual collision side preserves bytes",
        ["--read0", "--print0"],
        b"a\nb\0",
        0,
        driver=drive_injective_collision_pair,
        check_restoration=True,
        candidates=b"a\nb\0" + "a␊b".encode() + b"\0",
    )
    run_case(
        binary,
        "C0 literal collision side preserves bytes",
        ["--read0", "--print0"],
        "a␊b".encode() + b"\0",
        0,
        driver=drive_injective_collision_pair,
        check_restoration=True,
        candidates=b"a\nb\0" + "a␊b".encode() + b"\0",
    )
    run_case(
        binary,
        "C1 actual collision side preserves bytes",
        ["--read0", "--print0"],
        b"c\xc2\x9bd\0",
        0,
        driver=drive_injective_collision_pair,
        check_restoration=True,
        candidates=b"c\xc2\x9bd\0c\\u{009B}d\0",
    )
    run_case(
        binary,
        "C1 literal collision side preserves bytes",
        ["--read0", "--print0"],
        b"c\\u{009B}d\0",
        0,
        driver=drive_injective_collision_pair,
        check_restoration=True,
        candidates=b"c\xc2\x9bd\0c\\u{009B}d\0",
    )
    run_case(
        binary,
        "zh PTY phonetic",
        ["--lang", "zh", "--query", "bjdx"],
        "北京大学\n".encode(),
        0,
        driver=drive_language_match,
        candidates="北京大学\nnotes\n".encode(),
    )
    run_case(
        binary,
        "ja PTY phonetic",
        ["--lang", "ja", "--query", "kamera"],
        "カメラ\n".encode(),
        0,
        driver=drive_language_match,
        candidates="カメラ\n日本語\n".encode(),
    )
    run_case(
        binary,
        "ko PTY phonetic",
        ["--lang", "ko", "--query", "hangeul"],
        "한글\n".encode(),
        0,
        driver=drive_language_match,
        candidates="한글\n한글\nnotes\n".encode(),
    )
    run_case(
        binary, "large seeded query completes with exact limited totals",
        ["--query", "京", "--limit", "3"], "北京 0000\n".encode(), 0,
        driver=drive_seeded_large_query_finishes, check_restoration=True,
        candidates="".join(f"北京 {index:04d}\n" for index in range(1000)).encode(),
    )
    large_corpus = "".join(
        f"北京 カメラ 카메라 検索 {index:05d}\n" for index in range(10_000)
    ).encode()
    for abort in ("Escape", "Ctrl-C"):
        run_case(
            binary, f"large query {abort} cancels stale generation", [], b"", 130,
            driver=drive_large_query_cancellation,
            check_restoration=True, candidates=large_corpus,
        )
    print(
        "Interactive PTY tests passed "
        "(accept, abort, terminal editing, paste, no-match guidance, multi, "
        "source order, injective control display, explicit zh/ja/ko search, and large query cancellation)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
