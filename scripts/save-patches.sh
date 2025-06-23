#!/bin/sh
# shellcheck source=./scripts/common.sh
. "$(dirname "$0")/common.sh"

# cd into + save project root
vps_root_dir=$(rootdir)

. $MODULES_FILE_ROOTDIR

print_help()
{
    printf "Usage: save-patches.sh\n"
    printf "This script takes commits on modules and saves them as patch files.\n\n"

    printf "  --one    Only save a single tag (generic)\n"
    printf "  --help   Show this help menu\n"
}

while :; do
    case $1 in
        --one)
            one_tag=1
            ;;
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

save_patches()
{
    git rev-parse "$including_commit" >/dev/null 2>&1 || { errormsg "\"%s\" is missing from module \"%s\"\n" "$including_commit" "$module_dir"; return 1; }
    git format-patch --zero-commit -k --patience -o "$vps_output_dir" "$before_commit..$including_commit"
}

for module in $MODULES; do
    infomsg "Saving patches for module: %s\n" "$module"

    # cd into module directory
    cd "$vps_root_dir" || { errormsg "cannot enter versioned patch system root directory\n"; exit 1; }
    module_dir="" # SC2154/SC2034
    eval module_dir="\$${module}_DIRECTORY"
    cd "$module_dir" || { warnmsg "cannot enter module directory \"%s\"\n" "$module_dir"; continue; }

    # create patch directory for module
    vps_output_dir=$vps_root_dir/patches/$module_dir/
    mkdir -p "$vps_output_dir"

    # Need to stash changes -> filter-branch fails otherwise
    unset stash_ref
    stash_ref="$(git stash create -q)"
    git reset --hard -q

    # Set committer and commit date -> consistent commit hashes
    upstream_commit="" # SC2154/SC2034
    eval upstream_commit="\$${module}_COMMIT"
    # shellcheck disable=SC2016
    FILTER_BRANCH_SQUELCH_WARNING=1 git -c user.name='vps' -c user.email='vps@invalid' -c commit.gpgsign=false filter-branch -f --tag-name-filter cat --env-filter 'export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"; export GIT_COMMITTER_NAME="vps"; export GIT_COMMITTER_EMAIL="vps@invalid"' "$upstream_commit..HEAD"

    # Unstash (from previous) if required
    [ -n "${stash_ref}" ] && git stash apply -q "${stash_ref}"

    # TODO: if missing patchset tags, add them based on Git notes (see apply-patches)

    # Saving commits top to bottom
    # Upstream, Generic, Specific
    # ..U..G....S...
    #       ........ - specific commits
    #    ...         - generic commits
    most_recent_tag=$(git describe --tags --abbrev=0)
    git merge-base --is-ancestor "$upstream_commit" "$most_recent_tag" || { errormsg "The patchset tags for \"%s\" are before upstream commit. Skipping.\n" "$module_dir" ; continue; }
    vps_output_dir=$vps_root_dir/patches/$module_dir/$most_recent_tag
    mkdir -p "$vps_output_dir"
    including_commit=HEAD
    second_most_recent_tag=$(git describe --tags --abbrev=0 "$most_recent_tag^1")
    if [ -z "$one_tag" ]; then
        before_commit=$second_most_recent_tag
    else
        before_commit=$upstream_commit
    fi
    save_patches || exit 1

    [ -z "$one_tag" ] || continue
    vps_output_dir=$vps_root_dir/patches/$module_dir/$second_most_recent_tag
    mkdir -p "$vps_output_dir"
    including_commit=$before_commit
    before_commit=$upstream_commit
    save_patches || exit 1
done
