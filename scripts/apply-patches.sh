#!/bin/sh
# shellcheck source=./scripts/common.sh
. "$(dirname "$0")/common.sh"

print_help()
{
    printf "Usage: apply-patches.sh [patch set]\n"
    printf "This script applies the patch files in a way that allows for future saving.\n\n"

    warnmsg "This is not a utility to be used directly.\n"
    warnindent "Make use of this utility through the existing Make targets\n"
    warnindent "generic should always be applied first, followed by 1 specific target.\n"
}

while :; do
    case $1 in
        -\?|-help|--help)
            print_help
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -?*)
            warnmsg 'Ignored unknown parameter: %s\n' "$1"
            ;;
        *)
            break
    esac

    shift
done

patch_set=$1
[ -z "$patch_set" ] && { errormsg "no patch set provided\n"; print_help; exit 1; }
will_tag=1

vps_root_dir=$(rootdir)

. $MODULES_FILE_ROOTDIR

for module in $MODULES; do
    module_dir="" # SC2154/SC2034
    eval module_dir="\$${module}_DIRECTORY"
    patches_dir=$vps_root_dir/patches/$module_dir/$patch_set

    ! [ -d "$patches_dir" ] && { warnmsg "patches \"%s\" do not exist for module \"%s\"\n" "$patch_set" "$module_dir"; continue; }

    cd "$vps_root_dir/$module_dir" || { errormsg "cannot enter module \"%s\"\n" "$vps_root_dir/$module_dir"; exit 1; }

    # check if part of repo -> then check if part of branch -> if both true, error out
    git rev-parse -q --verify --end-of-options "$patch_set" > /dev/null && git merge-base --is-ancestor "$patch_set" HEAD > /dev/null && { warnmsg "patch set \"%s\" was previously applied. Skipping.\n" "$patch_set"; exit 0; }
    # TODO: add Git notes to each commit based on patchset (e.g. vps-patchset)

    infomsg "Applying patch set \"%s\"\n" "$patch_set"
    GIT_COMMITTER_NAME="$VPS_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$VPS_AUTHOR_EMAIL" git am --committer-date-is-author-date "$patches_dir"/*

    if [ -n "$will_tag" ]; then
        git tag -f "$patch_set"
    fi
done
