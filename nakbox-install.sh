#!/bin/sh
# Nakbox installer for Linux and WSL.
#
# Downloads the newest Nakbox release from GitHub and sets it up.
#
#   Standard:  ./nakbox-install.sh            asks for sudo: system packages,
#                                             app menu entry, "nakbox" command
#   Portable:  ./nakbox-install-portable.sh   no root needed, everything stays
#              (or --portable)                in one folder you can move
#
# The Nakbox repository is private, so the installer needs a GitHub token
# with read access to it (fine-grained token: Contents = Read-only).
# Give it with NAKBOX_GITHUB_TOKEN=... or type it when asked. It is saved in
# the Nakbox folder (config/update_token, readable by you only) so Nakbox can
# look for updates when it starts.
#
# Options:
#   --portable        portable install (also chosen when the file name
#                     contains "portable")
#   --dir DIR         install folder (asked if not given)
#   --version TAG     install this release instead of the newest
#   --python PATH     Python to build Nakbox's environment with (3.10+). Without
#                     this the installer lists the Pythons it finds and asks;
#                     with --yes it uses python3
#   --list-pythons    print the Python installs found (version<TAB>path) and stop
#   --yes             do not ask anything, use defaults
#   --no-setup        do not create the Python environment now
#   --uninstall       remove a standard install
set -eu

REPO=${NAKBOX_REPO:-Aksulaattori/Nakbox}
API=${NAKBOX_API:-https://api.github.com}
TOKEN=${NAKBOX_GITHUB_TOKEN:-}
DESKTOP_FILE=/usr/share/applications/nakbox.desktop
COMMAND_FILE=/usr/local/bin/nakbox

MODE=standard
case "$(basename -- "$0")" in *portable*) MODE=portable ;; esac
DIR=
VERSION=latest
PY=
LIST_PYTHONS=0
YES=0
SETUP=1
UNINSTALL=0

say() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --portable) MODE=portable ;;
        --standard) MODE=standard ;;
        --dir) [ $# -ge 2 ] || die "--dir needs a folder"; DIR=$2; shift ;;
        --version) [ $# -ge 2 ] || die "--version needs a tag"; VERSION=$2; shift ;;
        --python) [ $# -ge 2 ] || die "--python needs a path"; PY=$2; shift ;;
        --list-pythons) LIST_PYTHONS=1 ;;
        --yes|-y) YES=1 ;;
        --no-setup) SETUP=0 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

have_tty() {
    [ "$YES" -eq 0 ] && [ -r /dev/tty ] && ( : </dev/tty ) 2>/dev/null
}

# ask PROMPT DEFAULT -> $REPLY
ask() {
    REPLY=$2
    if have_tty; then
        printf '%s [%s]: ' "$1" "$2" >/dev/tty
        IFS= read -r REPLY </dev/tty || REPLY=
        [ -n "$REPLY" ] || REPLY=$2
    fi
}

# ask_secret PROMPT -> $REPLY (empty if nothing was typed)
ask_secret() {
    REPLY=
    if have_tty; then
        printf '%s: ' "$1" >/dev/tty
        stty -echo </dev/tty 2>/dev/null || true
        IFS= read -r REPLY </dev/tty || REPLY=
        stty echo </dev/tty 2>/dev/null || true
        printf '\n' >/dev/tty
    fi
}

absolute_dir() {
    case "$1" in
        *\\*)
            # A Windows path given inside WSL (\\wsl.localhost\Ubuntu\home\me\Nakbox,
            # C:\Nakbox). Taken as it is, it would become one oddly named folder
            # under the current directory.
            converted=
            case "$1" in
                \\\\*|[A-Za-z]:\\*)
                    if command -v wslpath >/dev/null 2>&1; then
                        converted=$(wslpath -a -u "$1" 2>/dev/null) || converted=
                    fi
                    ;;
            esac
            case "$converted" in
                /*) printf '%s\n' "$converted" ;;
                *) die "the install folder must be a Linux path such as ~/Nakbox, not: $1" ;;
            esac
            ;;
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$PWD/$1" ;;
    esac
}

# python_info PATH -> "3.14.0<TAB>/real/path" when PATH runs and is Python 3.10+
python_info() {
    "$1" -c 'import os, sys
if sys.version_info < (3, 10):
    sys.exit(1)
print("%d.%d.%d\t%s" % (sys.version_info[:3] + (os.path.realpath(sys.executable),)))' 2>/dev/null
}

# All Python 3.10+ installs found on PATH and in the usual extra places,
# newest first, one "version<TAB>path" line each.
list_pythons() {
    old_ifs=$IFS
    IFS=:
    # shellcheck disable=SC2086
    set -- $PATH
    IFS=$old_ifs
    for d in "$@" "$HOME/.local/bin" /usr/local/bin /usr/bin \
        "$HOME"/.pyenv/versions/*/bin "$HOME"/.local/share/uv/python/*/bin \
        "$HOME"/miniconda3/bin "$HOME"/miniforge3/bin "$HOME"/anaconda3/bin \
        /opt/python*/bin /opt/python/*/bin /home/linuxbrew/.linuxbrew/bin; do
        [ -d "$d" ] || continue
        for f in "$d"/python3 "$d"/python3.[0-9]*; do
            case "${f##*/}" in
                python3|python3.[0-9]|python3.[0-9][0-9]) ;;
                *) continue ;;
            esac
            [ -x "$f" ] && [ ! -d "$f" ] || continue
            python_info "$f" || true
        done
    done | sort -t. -k1,1nr -k2,2nr -k3,3nr | awk -F '\t' '!seen[$2]++'
}

if [ "$LIST_PYTHONS" -eq 1 ]; then
    list_pythons
    exit 0
fi

# Root is only used through sudo, so the Nakbox folder stays owned by the
# user who plays (Nakbox writes saves and settings into its own folder).
SUDO=
if [ "$MODE" = standard ]; then
    if [ "$(id -u)" -ne 0 ]; then
        command -v sudo >/dev/null 2>&1 \
            || die "the standard install needs sudo. Use --portable to install without root."
        SUDO=sudo
    elif [ -n "${SUDO_USER:-}" ]; then
        die "run this without sudo; it asks for the password when it needs root."
    fi
fi

if [ "$MODE" = portable ]; then DEFAULT_DIR=$HOME/Nakbox; else DEFAULT_DIR=/opt/nakbox; fi

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" -eq 1 ]; then
    if [ -z "$DIR" ]; then
        ask "Folder Nakbox is installed in" "$DEFAULT_DIR"
        DIR=$REPLY
    fi
    DIR=$(absolute_dir "$DIR")
    if [ "$MODE" = standard ]; then
        $SUDO rm -f "$DESKTOP_FILE" "$COMMAND_FILE"
        say "Removed the app menu entry and the nakbox command."
    fi
    if [ -f "$DIR/main.py" ] && [ -f "$DIR/run_linux.sh" ]; then
        ask "Delete $DIR too, including saves, games and settings? (yes/no)" "no"
        case "$REPLY" in
            y|Y|yes|YES|Yes)
                if [ -w "$DIR" ] && [ -w "$(dirname "$DIR")" ]; then rm -rf "$DIR"; else $SUDO rm -rf "$DIR"; fi
                say "Deleted $DIR."
                ;;
            *) say "Kept $DIR." ;;
        esac
    else
        say "No Nakbox found in $DIR; left it alone."
    fi
    exit 0
fi

# ------------------------------------------------------------------ install
say "Nakbox installer ($MODE)"
if grep -qi microsoft /proc/version 2>/dev/null; then
    say "WSL detected: Nakbox will open on the Windows desktop through WSLg."
fi

if [ -z "$DIR" ]; then
    ask "Install folder" "$DEFAULT_DIR"
    DIR=$REPLY
fi
DIR=$(absolute_dir "$DIR")

# --- which Python builds the environment
if [ -n "$PY" ]; then
    FOUND=$(command -v "$PY" 2>/dev/null) || die "--python: not found: $PY"
    PY=$FOUND
    python_info "$PY" >/dev/null || die "--python: $PY does not run or is older than Python 3.10."
elif have_tty; then
    FOUND=$(list_pythons)
    COUNT=$(printf '%s' "$FOUND" | grep -c . || true)
    if [ "$COUNT" -gt 1 ]; then
        say "Python installs found:"
        printf '%s\n' "$FOUND" | awk -F '\t' '{ printf "  %d) Python %-8s %s\n", NR, $1, $2 }'
        ask "Which Python should Nakbox use? (number)" 1
        case "$REPLY" in
            ''|*[!0-9]*) die "not a number from the list: $REPLY" ;;
        esac
        PY=$(printf '%s\n' "$FOUND" | awk -F '\t' -v n="$REPLY" 'NR == n { print $2 }')
        [ -n "$PY" ] || die "not a number from the list: $REPLY"
    elif [ "$COUNT" -eq 1 ]; then
        PY=$(printf '%s\n' "$FOUND" | awk -F '\t' '{ print $2 }')
    fi
fi
[ -z "$PY" ] || say "Python: $PY"

# --- system requirements
python_ok() {
    command -v "${PY:-python3}" >/dev/null 2>&1 \
        && "${PY:-python3}" -c 'import sys, venv, ensurepip; sys.exit(sys.version_info < (3, 10))' 2>/dev/null
}
portaudio_ok() {
    for d in /usr/lib /usr/lib64 /usr/local/lib /lib; do
        if find "$d" -maxdepth 2 -name 'libportaudio.so*' 2>/dev/null | grep -q .; then return 0; fi
    done
    return 1
}

if [ "$MODE" = standard ] && command -v apt-get >/dev/null 2>&1; then
    if ! command -v curl >/dev/null 2>&1 || ! python_ok || ! portaudio_ok; then
        say "Installing system packages (curl, python3-venv, libportaudio2)..."
        $SUDO apt-get install -y curl python3 python3-venv libportaudio2
    fi
    # RPCS3 (PS3) AppImage: optional, so a missing package must not stop the install
    for package in libopengl0 libasound2t64 libxcb-cursor0 libsm6 libice6; do
        dpkg -s "$package" >/dev/null 2>&1 \
            || $SUDO apt-get install -y "$package" >/dev/null 2>&1 \
            || warn "Could not install $package (only needed for PS3 games)."
    done
fi
command -v curl >/dev/null 2>&1 || die "curl is missing. Install it and run the installer again."
command -v tar >/dev/null 2>&1 || die "tar is missing. Install it and run the installer again."
if [ -n "$PY" ]; then
    python_ok || die "$PY has no venv module (Debian/Ubuntu: sudo apt install python3-venv, or pythonX.Y-venv for that version)."
fi
python_ok || die "Python 3.10+ with the venv module is missing (Debian/Ubuntu: sudo apt install python3 python3-venv)."
portaudio_ok || warn "libportaudio was not found; calls in Nakbox Network have no sound until it is installed (Debian/Ubuntu: sudo apt install libportaudio2)."

# --- token
# Updating an install: the token saved last time still works in most cases.
TOKEN_FILE=$DIR/config/update_token
SAVED_TOKEN=0
if [ -z "$TOKEN" ] && [ -r "$TOKEN_FILE" ]; then
    TOKEN=$(tr -d '\r\n' <"$TOKEN_FILE")
    [ -z "$TOKEN" ] || { SAVED_TOKEN=1; say "Using the GitHub token saved in $TOKEN_FILE."; }
fi
if [ -z "$TOKEN" ]; then
    say "The Nakbox repository is private. Paste a GitHub token that can read"
    say "$REPO (leave empty if the repository is public)."
    ask_secret "GitHub token"
    TOKEN=$REPLY
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/nakbox-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

# The token goes into a private curl config file, not onto the command line
# where other users could read it from the process list.
CURL_CFG=$TMP/curl.cfg
(
    umask 077
    {
        printf 'silent\nshow-error\nlocation\n'
        printf 'user-agent = "nakbox-installer"\n'
        printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
        if [ -n "$TOKEN" ]; then
            printf 'header = "Authorization: Bearer %s"\n' "$TOKEN"
        fi
    } >"$CURL_CFG"
)

# --- find the release
if [ "$VERSION" = latest ]; then
    RELEASE_URL=$API/repos/$REPO/releases/latest
else
    RELEASE_URL=$API/repos/$REPO/releases/tags/$VERSION
fi
say "Looking up the release on GitHub..."
CODE=$(curl -K "$CURL_CFG" -H 'Accept: application/vnd.github+json' \
    -o "$TMP/release.json" -w '%{http_code}' "$RELEASE_URL") \
    || die "could not reach GitHub. Check the internet connection."
case "$CODE" in
    200) ;;
    401)
        if [ "$SAVED_TOKEN" -eq 1 ]; then
            die "GitHub rejected the saved token (401); it has probably expired. Delete $TOKEN_FILE and run the installer again to give a new one."
        fi
        die "GitHub rejected the token (401). Check that it was copied whole and has not expired."
        ;;
    403|429) die "GitHub refused the request ($CODE): rate limit, or the token has no access to $REPO." ;;
    404)
        if [ -n "$TOKEN" ]; then
            die "no release found (404). Check that the token can read $REPO and that a release has been published."
        fi
        die "no release found (404). The repository is private: a GitHub token is needed."
        ;;
    *) die "GitHub answered with HTTP $CODE." ;;
esac

INFO=$("${PY:-python3}" - "$TMP/release.json" <<'EOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
for asset in release.get("assets", []):
    name = asset["name"]
    if name.startswith("Nakbox-") and name.endswith(".tar.gz"):
        print(release["tag_name"], asset["id"])
        break
else:
    sys.exit(3)
EOF
) || die "the release has no Nakbox-*.tar.gz package."
TAG=${INFO%% *}
ASSET_ID=${INFO##* }

# --- download and unpack
say "Downloading Nakbox $TAG..."
curl -K "$CURL_CFG" --fail -H 'Accept: application/octet-stream' \
    -o "$TMP/nakbox.tar.gz" "$API/repos/$REPO/releases/assets/$ASSET_ID" \
    || die "downloading the package failed."

STAGE=$TMP/stage
mkdir "$STAGE"
tar -xzf "$TMP/nakbox.tar.gz" -C "$STAGE"
[ -f "$STAGE/main.py" ] && [ -f "$STAGE/run_linux.sh" ] || die "the package does not look like Nakbox."

if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR" 2>/dev/null || $SUDO mkdir -p "$DIR"
fi
if [ ! -w "$DIR" ]; then
    [ "$MODE" = standard ] || die "cannot write to $DIR. Pick another folder with --dir."
    $SUDO chown "$(id -u):$(id -g)" "$DIR"
fi

# Updating an existing install: keep the settings the user may have changed.
# Saves, games and profiles are not in the package at all, so they stay.
for f in "$STAGE"/catalog.json "$STAGE"/config/*; do
    [ -f "$f" ] || continue
    rel=${f#"$STAGE"/}
    if [ -e "$DIR/$rel" ]; then rm -f "$f"; fi
done
cp -Rp "$STAGE"/. "$DIR"/
printf '%s\n' "$TAG" >"$DIR/VERSION"
chmod +x "$DIR/run_linux.sh"
# Nakbox's updater (updater.py) reads the token from here.
if [ -n "$TOKEN" ]; then
    mkdir -p "$DIR/config"
    ( umask 077; printf '%s\n' "$TOKEN" >"$TOKEN_FILE" )
    chmod 600 "$TOKEN_FILE"
fi
say "Nakbox $TAG is in $DIR"

# --- Python environment
if [ "$SETUP" -eq 1 ]; then
    VENV=$DIR/.venv-linux
    # A Python was picked: an environment built from another one is rebuilt.
    if [ -n "$PY" ] && [ -x "$VENV/bin/python" ]; then
        BASE='import sys; print(sys.base_prefix, sys.version_info[:2])'
        WANT=$("$PY" -c "$BASE" 2>/dev/null) || WANT=
        HAVE=$("$VENV/bin/python" -c "$BASE" 2>/dev/null) || HAVE=
        if [ "$WANT" != "$HAVE" ]; then
            say "Rebuilding the Python environment with $PY..."
            rm -rf "$VENV"
        fi
    fi
    say "Setting up the Python environment. This takes a few minutes the first time..."
    if ! PYTHON=${PY:-${PYTHON:-python3}} "$DIR/run_linux.sh" --setup-only; then
        warn "the Python environment is not ready. Nakbox tries again when it starts."
    fi
fi

# --- app menu entry and command (standard install only)
if [ "$MODE" = standard ]; then
    cat >"$TMP/nakbox.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Nakbox
Comment=Console-style game launcher
Exec="$DIR/run_linux.sh"
Path=$DIR
Terminal=false
Categories=Game;
EOF
    cat >"$TMP/nakbox" <<EOF
#!/bin/sh
exec "$DIR/run_linux.sh" "\$@"
EOF
    $SUDO mkdir -p "$(dirname "$DESKTOP_FILE")" "$(dirname "$COMMAND_FILE")"
    $SUDO install -m 644 "$TMP/nakbox.desktop" "$DESKTOP_FILE"
    $SUDO install -m 755 "$TMP/nakbox" "$COMMAND_FILE"
    say "Done. Start Nakbox from the app menu or with the command: nakbox"
else
    say "Done. Start Nakbox with: $DIR/run_linux.sh"
fi
