"""Configuration path policy without claiming unsupported TOML loading."""

from std.os.env import getenv


def _join_config_home(base: StringSlice) -> String:
    var prefix = String(base)
    if prefix.endswith("/"):
        return prefix + "yuragi/config.toml"
    return prefix + "/yuragi/config.toml"


def config_path_from_environment(
    *,
    override: String = "",
    xdg_config_home: String = "",
    home: String = "",
) raises -> String:
    """Resolve the reserved path with explicit, XDG, then HOME precedence."""
    if override != "":
        return override
    # XDG_CONFIG_HOME must be absolute. Ignore a relative value and fall back
    # to HOME instead of depending on the process working directory.
    if xdg_config_home.startswith("/"):
        return _join_config_home(xdg_config_home)
    if home != "":
        var config_home = home + "/.config"
        if home.endswith("/"):
            config_home = home + ".config"
        return _join_config_home(config_home)
    raise Error(
        "configuration path requires YURAGI_CONFIG_FILE, XDG_CONFIG_HOME, "
        "or HOME; set one of those environment variables"
    )


def config_path() raises -> String:
    """Resolve Yuragi's reserved configuration path from the process environment."""
    return config_path_from_environment(
        override=getenv("YURAGI_CONFIG_FILE"),
        xdg_config_home=getenv("XDG_CONFIG_HOME"),
        home=getenv("HOME"),
    )
