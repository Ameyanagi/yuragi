"""Stable line-oriented diagnostics for retained ranked matches."""

from std.collections import List

from yuragi.ranking import RankedCandidate
from yuragi.phonetic import key_kind_name


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
            key_kind_name(ranked[index].key_kind),
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
