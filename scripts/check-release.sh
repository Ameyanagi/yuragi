#!/usr/bin/env bash

set -euo pipefail

metadata_only=false
if [[ "${1:-}" == "--metadata-only" ]]; then
    metadata_only=true
    shift
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 [--metadata-only] vMAJOR.MINOR.PATCH [EXPECTED_COMMIT]" >&2
    exit 2
fi

tag_name=$1
expected_commit=${2:-HEAD}

if [[ ! "$tag_name" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "release tag '$tag_name' must match vMAJOR.MINOR.PATCH" >&2
    exit 1
fi
release_version=${BASH_REMATCH[1]}
tag_ref="refs/tags/$tag_name"

if [[ "$metadata_only" == false ]]; then
    if ! git rev-parse --verify --quiet "$tag_ref" >/dev/null; then
        echo "release tag '$tag_name' is not available in the checkout" >&2
        exit 1
    fi
    if [[ $(git cat-file -t "$tag_ref") != "tag" ]]; then
        echo "release tag '$tag_name' must be an annotated tag" >&2
        exit 1
    fi

    tag_commit=$(git rev-parse "$tag_ref^{commit}")
    checkout_commit=$(git rev-parse "$expected_commit^{commit}")
    if [[ "$tag_commit" != "$checkout_commit" ]]; then
        echo "release tag '$tag_name' resolves to $tag_commit, not $checkout_commit" >&2
        exit 1
    fi
    if ! git merge-base --is-ancestor "$tag_commit" refs/remotes/origin/main; then
        echo "release commit $tag_commit is not contained in origin/main" >&2
        exit 1
    fi
fi

pixi_name=$(
    awk '
        $0 == "[workspace]" { in_workspace = 1; next }
        in_workspace && /^\[/ { exit }
        in_workspace && /^name = "/ {
            sub(/^name = "/, "")
            sub(/"$/, "")
            print
        }
    ' pixi.toml
)
recipe_name=$(sed -nE 's/^  name: ([^[:space:]]+)$/\1/p' conda.recipe/recipe.yaml)
if [[ "$pixi_name" != "yuragi" || "$recipe_name" != "yuragi" ]]; then
    echo "package identity must remain pixi=yuragi and recipe=yuragi" >&2
    exit 1
fi

pixi_version=$(
    awk '
        $0 == "[workspace]" { in_workspace = 1; next }
        in_workspace && /^\[/ { exit }
        in_workspace && /^version = "/ {
            sub(/^version = "/, "")
            sub(/"$/, "")
            print
        }
    ' pixi.toml
)
recipe_version=$(sed -nE 's/^  version: "([^"]+)"$/\1/p' conda.recipe/recipe.yaml)
cli_version=$(sed -nE 's/^comptime VERSION = "([^"]+)"$/\1/p' src/yuragi/options.mojo)
if [[ "$pixi_version" != "$release_version" ]]; then
    echo "release tag '$tag_name' does not match pixi.toml version '$pixi_version'" >&2
    exit 1
fi
if [[ "$recipe_version" != "$release_version" ]]; then
    echo "release tag '$tag_name' does not match recipe version '$recipe_version'" >&2
    exit 1
fi
if [[ "$cli_version" != "$release_version" ]]; then
    echo "release tag '$tag_name' does not match CLI version '$cli_version'" >&2
    exit 1
fi

declare -a workspace_pins=(
    'mojo:1.0.0'
    'mojo-hibana:0.1.0'
    'mojo-moji:0.1.0'
    'mojo-mojotui:0.1.1'
    'mojo-yomi:0.1.1'
)
for entry in "${workspace_pins[@]}"; do
    package=${entry%%:*}
    version=${entry#*:}
    expected_line="$package = \"==$version\""
    if ! awk -v package="$package" -v expected="$expected_line" '
        $0 == "[dependencies]" { in_dependencies = 1; next }
        in_dependencies && /^\[/ { in_dependencies = 0 }
        in_dependencies {
            name = $0
            sub(/ = .*/, "", name)
            if (name == package) {
                total += 1
                if ($0 == expected) exact += 1
            }
        }
        END { exit !(total == 1 && exact == 1) }
    ' pixi.toml; then
        echo "pixi.toml [dependencies] must contain exactly '$expected_line'" >&2
        exit 1
    fi
done

declare -a recipe_pins=(
    'mojo-compiler ==1.0.0'
    'mojo-hibana ==0.1.0'
    'mojo-moji ==0.1.0'
    'mojo-mojotui ==0.1.1'
    'mojo-yomi ==0.1.1'
)
for section in build host run; do
    for expected in "${recipe_pins[@]}"; do
        awk -v wanted="$section" -v expected="$expected" '
            $0 == "requirements:" { in_requirements = 1; next }
            in_requirements && /^[^ ]/ { in_requirements = 0 }
            in_requirements && /^  [[:alnum:]_-]+:$/ {
                current = $1
                sub(/:$/, "", current)
            }
            in_requirements && current == wanted && /^    - / {
                dependency = substr($0, 7)
                name = dependency
                sub(/ .*/, "", name)
                expected_name = expected
                sub(/ .*/, "", expected_name)
                if (name == expected_name) {
                    total += 1
                    if (dependency == expected) exact += 1
                }
            }
            END { exit !(total == 1 && exact == 1) }
        ' conda.recipe/recipe.yaml || {
            echo "recipe $section must contain exactly '$expected'" >&2
            exit 1
        }
    done
done

escaped_version=${release_version//./\\.}
changelog_dates=$(
    sed -nE "s/^## \\[$escaped_version\\] - ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\\1/p" CHANGELOG.md
)
if [[ ! "$changelog_dates" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "CHANGELOG.md must contain one dated [$release_version] heading" >&2
    exit 1
fi

if ! grep -Fq 'GH_REPO: ${{ github.repository }}' .github/workflows/release.yml; then
    echo "release publisher must set GH_REPO before running outside a Git checkout" >&2
    exit 1
fi

echo "release contract verified: $tag_name, exact stable Mojo and ecosystem dependencies, changelog $changelog_dates, and publisher repository context"
