"""Application orchestration boundaries for noninteractive filtering."""

from std.collections import List

from yuragi.candidate import Candidate
from yuragi.options import Options


def matching_backend_required(options: Options) -> Bool:
    """Return whether the invocation needs ecosystem matching libraries."""
    return options.has_filter and options.query != ""


def validate_foundation_mode(options: Options) raises:
    """Reject modes whose owning libraries or UI are not integrated yet."""
    if not options.has_filter:
        raise Error("interactive mode is not available; use --filter QUERY")
    if matching_backend_required(options):
        raise Error(
            "non-empty --filter requires the pending Moji/Hibana/Yomi integration"
        )


def select_without_matching(
    var candidates: List[Candidate], options: Options
) raises -> List[Candidate]:
    """Implement the only honest pre-integration selection: an empty query."""
    validate_foundation_mode(options)
    return candidates^
