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
import time
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
        if value == 0x0D:
            self.column = 0
        elif value == 0x0A:
            self.row = min(self.row + 1, self.rows - 1)
        elif value == 0x08:
            self.column = max(self.column - 1, 0)
        elif value == 0x09:
            self.column = min((self.column // 8 + 1) * 8, self.columns - 1)
        elif 0x20 <= value <= 0x7E:
            self.cells[self.row][self.column] = chr(value)
            self.column = min(self.column + 1, self.columns - 1)

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
    print(
        "Interactive PTY tests passed "
        "(accept, abort, editor controls, paste, no-match guidance, multi, "
        "source order, and explicit zh/ja/ko search)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
