"""Explicit search-language policy for Yuragi's small public API."""


struct LanguageMode(Copyable, Equatable, ImplicitlyCopyable):
    """Choose which bounded Yomi key family is prepared.

    ``AUTO`` intentionally means direct text matching only.  Yuragi does not
    guess a language from a label or query; callers opt into Japanese,
    Chinese, or Korean phonetic expansion explicitly.
    """

    var _value: Int

    comptime AUTO = LanguageMode(_value=0)
    comptime JA = LanguageMode(_value=1)
    comptime ZH = LanguageMode(_value=2)
    comptime KO = LanguageMode(_value=3)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def validate(self) raises:
        """Reject forged or stale discriminants at an API boundary."""
        if (
            self != LanguageMode.AUTO
            and self != LanguageMode.JA
            and self != LanguageMode.ZH
            and self != LanguageMode.KO
        ):
            raise Error("unsupported Yuragi language mode")
