"""Deterministic shell integrations for Yuragi's common picker workflows."""


struct ShellKind(Copyable, Equatable, ImplicitlyCopyable):
    """One supported generated shell integration."""

    var _value: Int

    comptime BASH = ShellKind(_value=0)
    comptime ZSH = ShellKind(_value=1)
    comptime FISH = ShellKind(_value=2)
    comptime POWERSHELL = ShellKind(_value=3)

    def __init__(out self, *, _value: Int):
        self._value = _value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


comptime _BASH = """\
# yuragi shell integration for bash
# Load with: eval "$(yuragi shell bash)"
# fd/fdfind is preferred; POSIX find is the documented fallback.

: "${YURAGI_BIN:=yuragi}"

__yuragi_require() {
  command -v "$YURAGI_BIN" >/dev/null 2>&1 && return 0
  printf 'yuragi: shell integration cannot find %s\n' "$YURAGI_BIN" >&2
  return 127
}

__yuragi_paths() {
  local kind=${1:-all}
  if command -v fd >/dev/null 2>&1; then
    if [ "$kind" = dir ]; then fd --type d --hidden --follow --exclude .git .
    elif [ "$kind" = file ]; then fd --type f --hidden --follow --exclude .git .
    else fd --hidden --follow --exclude .git .; fi
  elif command -v fdfind >/dev/null 2>&1; then
    if [ "$kind" = dir ]; then fdfind --type d --hidden --follow --exclude .git .
    elif [ "$kind" = file ]; then fdfind --type f --hidden --follow --exclude .git .
    else fdfind --hidden --follow --exclude .git .; fi
  elif command -v find >/dev/null 2>&1; then
    if [ "$kind" = dir ]; then
      find . -type d -not -path './.git' -not -path './.git/*' -not -path .
    elif [ "$kind" = file ]; then
      find . -type f -not -path './.git/*'
    else
      find . -mindepth 1 -not -path './.git' -not -path './.git/*'
    fi
  else
    printf 'yuragi: install fd/fdfind or provide POSIX find for path workflows\n' >&2
    return 127
  fi
}

__yuragi_ctrl_t() {
  __yuragi_require || return
  local selected quoted
  selected=$(__yuragi_paths file | "$YURAGI_BIN") || return
  printf -v quoted '%q' "$selected"
  READLINE_LINE=${READLINE_LINE:0:READLINE_POINT}${quoted}${READLINE_LINE:READLINE_POINT}
  READLINE_POINT=$((READLINE_POINT + ${#quoted}))
}

__yuragi_ctrl_r() {
  __yuragi_require || return
  local selected
  selected=$(builtin history | sed 's/^[[:space:]]*[0-9][0-9]*[[:space:]]*//' | "$YURAGI_BIN" --query "$READLINE_LINE") || return
  READLINE_LINE=$selected
  READLINE_POINT=${#READLINE_LINE}
}

__yuragi_alt_c() {
  __yuragi_require || return
  local selected
  selected=$(__yuragi_paths dir | "$YURAGI_BIN") || return
  [ -n "$selected" ] && builtin cd -- "$selected"
}

__yuragi_complete() {
  local word=${COMP_WORDS[COMP_CWORD]}
  case $word in *'**') ;; *) return 1 ;; esac
  __yuragi_require || return
  local query=${word%'**'} selected
  selected=$(__yuragi_paths all | "$YURAGI_BIN" --query "$query") || return
  COMPREPLY=("$selected")
}

bind -x '"\\C-t":__yuragi_ctrl_t'
bind -x '"\\C-r":__yuragi_ctrl_r'
bind -x '"\\ec":__yuragi_alt_c'
complete -D -o default -o bashdefault -o nospace -F __yuragi_complete 2>/dev/null || true
"""


comptime _ZSH = """\
# yuragi shell integration for zsh
# Load with: eval "$(yuragi shell zsh)"
# fd/fdfind is preferred; POSIX find is the documented fallback.

: "${YURAGI_BIN:=yuragi}"

__yuragi_require() {
  command -v "$YURAGI_BIN" >/dev/null 2>&1 && return 0
  print -u2 -- "yuragi: shell integration cannot find $YURAGI_BIN"
  return 127
}

__yuragi_paths() {
  local kind=${1:-all}
  if (( $+commands[fd] )); then
    if [[ $kind == dir ]]; then fd --type d --hidden --follow --exclude .git .
    elif [[ $kind == file ]]; then fd --type f --hidden --follow --exclude .git .
    else fd --hidden --follow --exclude .git .; fi
  elif (( $+commands[fdfind] )); then
    if [[ $kind == dir ]]; then fdfind --type d --hidden --follow --exclude .git .
    elif [[ $kind == file ]]; then fdfind --type f --hidden --follow --exclude .git .
    else fdfind --hidden --follow --exclude .git .; fi
  elif (( $+commands[find] )); then
    if [[ $kind == dir ]]; then
      find . -type d -not -path './.git' -not -path './.git/*' -not -path .
    elif [[ $kind == file ]]; then
      find . -type f -not -path './.git/*'
    else
      find . -mindepth 1 -not -path './.git' -not -path './.git/*'
    fi
  else
    print -u2 -- 'yuragi: install fd/fdfind or provide POSIX find for path workflows'
    return 127
  fi
}

__yuragi_ctrl_t() {
  __yuragi_require || return
  local selected
  selected=$(__yuragi_paths file | "$YURAGI_BIN") || return
  LBUFFER+=${(q)selected}
}

__yuragi_ctrl_r() {
  __yuragi_require || return
  local selected
  selected=$(fc -lnr 1 | "$YURAGI_BIN" --query "$BUFFER") || return
  BUFFER=$selected
  CURSOR=${#BUFFER}
}

__yuragi_alt_c() {
  __yuragi_require || return
  local selected
  selected=$(__yuragi_paths dir | "$YURAGI_BIN") || return
  [[ -n $selected ]] && builtin cd -- "$selected"
  zle reset-prompt
}

__yuragi_complete() {
  local word=${LBUFFER##* }
  if [[ $word != *'**' ]]; then
    zle ${__yuragi_default_tab:-expand-or-complete}
    return
  fi
  __yuragi_require || return
  local query=${word%'**'} selected
  selected=$(__yuragi_paths all | "$YURAGI_BIN" --query "$query") || return
  LBUFFER=${LBUFFER[1,$(( ${#LBUFFER} - ${#word} ))]}${(q)selected}
}

__yuragi_default_tab=${${(s: :)${(M)${(f)"$(bindkey '^I')"}:*}}}[2]}
zle -N __yuragi_ctrl_t
zle -N __yuragi_ctrl_r
zle -N __yuragi_alt_c
zle -N __yuragi_complete
bindkey '^T' __yuragi_ctrl_t
bindkey '^R' __yuragi_ctrl_r
bindkey '^[c' __yuragi_alt_c
bindkey '^I' __yuragi_complete
"""


comptime _FISH = """\
# yuragi shell integration for fish
# Load with: yuragi shell fish | source
# fd/fdfind is preferred; find is the documented fallback.

set -q YURAGI_BIN; or set -gx YURAGI_BIN yuragi

function __yuragi_require
    command -q $YURAGI_BIN; and return 0
    printf 'yuragi: shell integration cannot find %s\n' $YURAGI_BIN >&2
    return 127
end

function __yuragi_paths --argument-names kind
    test -n "$kind"; or set kind all
    if command -q fd
        if test $kind = dir; fd --type d --hidden --follow --exclude .git .
        else if test $kind = file; fd --type f --hidden --follow --exclude .git .
        else; fd --hidden --follow --exclude .git .; end
    else if command -q fdfind
        if test $kind = dir; fdfind --type d --hidden --follow --exclude .git .
        else if test $kind = file; fdfind --type f --hidden --follow --exclude .git .
        else; fdfind --hidden --follow --exclude .git .; end
    else if command -q find
        if test $kind = dir
            find . -type d -not -path './.git' -not -path './.git/*' -not -path .
        else if test $kind = file
            find . -type f -not -path './.git/*'
        else
            find . -mindepth 1 -not -path './.git' -not -path './.git/*'
        end
    else
        echo 'yuragi: install fd/fdfind or provide find for path workflows' >&2
        return 127
    end
end

function __yuragi_ctrl_t
    __yuragi_require; or return
    set -l selected (__yuragi_paths file | $YURAGI_BIN); or return
    commandline -i -- (string escape -- $selected)
end

function __yuragi_ctrl_r
    __yuragi_require; or return
    set -l selected (history | $YURAGI_BIN --query (commandline -b)); or return
    commandline -r -- $selected
end

function __yuragi_alt_c
    __yuragi_require; or return
    set -l selected (__yuragi_paths dir | $YURAGI_BIN); or return
    test -n "$selected"; and cd -- $selected
    commandline -f repaint
end

function __yuragi_complete
    set -l word (commandline -ct)
    if not string match -q '*\\*\\*' -- $word
        commandline -f complete
        return
    end
    __yuragi_require; or return
    set -l query (string replace -r '\\*\\*$' '' -- $word)
    set -l selected (__yuragi_paths all | $YURAGI_BIN --query $query); or return
    commandline -t -- (string escape -- $selected)
end

bind \\ct __yuragi_ctrl_t
bind \\cr __yuragi_ctrl_r
bind \\ec __yuragi_alt_c
bind \\t __yuragi_complete
"""


comptime _POWERSHELL = """\
# yuragi shell integration for PowerShell
# Load with: Invoke-Expression ((yuragi shell powershell) -join "`n")
# fd/fdfind is preferred; Get-ChildItem is the documented fallback.

if (-not $env:YURAGI_BIN) { $env:YURAGI_BIN = 'yuragi' }

function Test-YuragiCommand {
    if (Get-Command $env:YURAGI_BIN -ErrorAction SilentlyContinue) { return $true }
    [Console]::Error.WriteLine("yuragi: shell integration cannot find $env:YURAGI_BIN")
    return $false
}

function ConvertTo-YuragiLiteral([string] $Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-YuragiPaths([string] $Kind = 'all') {
    $fd = Get-Command fd -ErrorAction SilentlyContinue
    if (-not $fd) { $fd = Get-Command fdfind -ErrorAction SilentlyContinue }
    if ($fd) {
        if ($Kind -eq 'dir') { & $fd.Source --type d --hidden --follow --exclude .git . }
        elseif ($Kind -eq 'file') { & $fd.Source --type f --hidden --follow --exclude .git . }
        else { & $fd.Source --hidden --follow --exclude .git . }
        return
    }
    Get-ChildItem -Force -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '[\\\\/]\\.git([\\\\/]|$)' -and
        (($Kind -eq 'all') -or ($Kind -eq 'dir' -and $_.PSIsContainer) -or
         ($Kind -eq 'file' -and -not $_.PSIsContainer))
    } | ForEach-Object { Resolve-Path -Relative -LiteralPath $_.FullName }
}

if (-not (Get-Module -ListAvailable PSReadLine)) {
    [Console]::Error.WriteLine('yuragi: PSReadLine is required for generated key bindings')
    return
}
Import-Module PSReadLine

Set-PSReadLineKeyHandler -Chord Ctrl+t -BriefDescription YuragiFile -ScriptBlock {
    if (-not (Test-YuragiCommand)) { return }
    $selected = (Get-YuragiPaths file | & $env:YURAGI_BIN) -join "`n"
    if ($selected) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert((ConvertTo-YuragiLiteral $selected))
    }
}

Set-PSReadLineKeyHandler -Chord Ctrl+r -BriefDescription YuragiHistory -ScriptBlock {
    if (-not (Test-YuragiCommand)) { return }
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $selected = ((Get-History).CommandLine | & $env:YURAGI_BIN --query $line) -join "`n"
    if ($selected) {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
    }
}

Set-PSReadLineKeyHandler -Chord Alt+c -BriefDescription YuragiDirectory -ScriptBlock {
    if (-not (Test-YuragiCommand)) { return }
    $selected = (Get-YuragiPaths dir | & $env:YURAGI_BIN) -join "`n"
    if ($selected) {
        Set-Location -LiteralPath $selected
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
}

Set-PSReadLineKeyHandler -Chord Tab -BriefDescription YuragiCompletion -ScriptBlock {
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $prefix = $line.Substring(0, $cursor)
    $match = [regex]::Match($prefix, '([^ ]*)\\*\\*$')
    if (-not $match.Success) {
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext()
        return
    }
    if (-not (Test-YuragiCommand)) { return }
    $query = $match.Groups[1].Value
    $selected = (Get-YuragiPaths all | & $env:YURAGI_BIN --query $query) -join "`n"
    if ($selected) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $match.Index,
            $match.Length,
            (ConvertTo-YuragiLiteral $selected)
        )
    }
}
"""


def shell_script(shell: ShellKind) -> String:
    """Return one byte-stable integration script without inspecting the host."""
    if shell == ShellKind.BASH:
        return String(_BASH)
    if shell == ShellKind.ZSH:
        return String(_ZSH)
    if shell == ShellKind.FISH:
        return String(_FISH)
    return String(_POWERSHELL)
