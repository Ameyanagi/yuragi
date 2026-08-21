"""Stable line-oriented diagnostics for retained ranked matches."""

from std.collections import List

from yuragi.ranking import RankedCandidate


comptime KEY_KIND_ORIGINAL = "original"


def render_explanation(ranked: List[RankedCandidate]) -> String:
    """Render ranked matches as newline-terminated explanation lines.

    Each line is ``RANK<TAB>SCORE<TAB>KEY<TAB>POSITIONS<TAB>TEXT``.
    """
    var output = String()
    for index in range(len(ranked)):
        output += String(
            index + 1,
            "\t",
            ranked[index].score,
            "\t",
            KEY_KIND_ORIGINAL,
            "\t",
        )
        for position_index in range(len(ranked[index].positions)):
            if position_index > 0:
                output += ","
            output += String(ranked[index].positions[position_index])
        output += "\t"
        output += ranked[index].text
        output += "\n"
    return output^
