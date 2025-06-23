#!/bin/sh
# shellcheck disable=SC2034 # unused variables - expected in common source script
# shellcheck disable=SC2059 # color variables are used
# shellcheck disable=SC2145 # no concatenating, keeping as-is is intended due to variables

# Some scripts might be in subdirectories. Due to POSIX Shell quirks, it is not
# possible to differenciate. In that case, set BASE_SCRIPTS_DIR.
scripts_dir=${BASE_SCRIPTS_DIR:-$(dirname "$0")}
# shellcheck source=./scripts/colors # allow for use of colors
. "$scripts_dir/colors"

# Git user.name / user.email
VPS_AUTHOR_NAME=vps
VPS_AUTHOR_EMAIL=vps@invalid
VPS_AUTHOR="$VPS_AUTHOR_NAME <${VPS_AUTHOR_EMAIL}>"

# Static files
# shellcheck source=./modules
MODULES_FILE_ROOTDIR="./modules"

# ------------------------------------------------------------------------------
# Printing
#
# *msg is for a message (with prefix)
# *indent is for message continuation (indent of the prefix w/o prefix)
# *f is like printf, but with the color
#
# They are used like printf

errormsg() {
    printf "$ERR --- Error: $@" >&2
    printf "$RT" >&2
}
errorf() {
    printf "$ERR$@" >&2
    printf "$RT" >&2
}

warnmsg() {
    printf "$WARN --- Warning: $@" >&2
    printf "$RT" >&2
}
warnindent() {
    printf "$WARN              $@" >&2
    printf "$RT" >&2
}
warnf() {
    printf "$ERR$@" >&2
    printf "$RT" >&2
}

infomsg() {
    printf " --- $@" >&2
}
# ------------------------------------------------------------------------------


# cd into + print root dir
rootdir() {
    vps_root_dir=$(realpath "$scripts_dir"/../)
    cd "$vps_root_dir" || { errormsg "cannot enter versioned patch system root directory\n"; exit 1; }
    printf "%s" "$vps_root_dir"
}
