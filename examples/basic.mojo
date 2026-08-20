from std.collections import List

from yuragi.candidate import candidates_from_text, render_candidates
from yuragi.options import parse_options
from yuragi.pipeline import select_without_matching


def main() raises:
    var args: List[String] = ["yuragi", "--filter", ""]
    var options = parse_options(args^)
    var candidates = candidates_from_text("北京大学\nnotes\n카메라\n")
    var selected = select_without_matching(candidates^, options)
    print(render_candidates(selected^), end="")
