#!/bin/sh
# shellcheck source=./scripts/common.sh
. "$(dirname "$0")/common.sh"

vps_root_dir=$(rootdir)

. "$MODULES_FILE_ROOTDIR"

print_help()
{
    printf "Usage: update.sh\n"
    printf "This script downloads modules, as specified in the modules file.\n\n"

    printf "  --help   Show this help menu\n"
}

unset no_backup
while :; do
    case $1 in
        -\?|-help|--help)
            print_help
            exit 0
            ;;
        -n)
            no_backup=1
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

update_module() {
    module=$1
    cd "$vps_root_dir" || { errormsg "cannot return to versioned patch system root directory\n"; exit 1; }
    infomsg "Updating module: %s\n" "$module"
    
    # Get module information
    url=""; branch=""; commit=""; directory="" # SC2154/SC2034
    eval url="\$${module}_URL"
    eval branch="\$${module}_BRANCH"
    eval commit="\$${module}_COMMIT"
    eval directory="\$${module}_DIRECTORY"

    # Download/Update the module
    if [ -d "$directory" ]; then
        cd "$directory" || { errormsg "cannot enter module directory \"%s\"\n" "$directory"; exit 1; }
        git rev-parse --is-inside-work-tree > /dev/null 2>&1 || { errormsg "module directory \"%s\" is not a git repository\n" "$directory"; exit 1; }
        infomsg "Module already cloned.\n"

        if [ -z "$no_backup" ]; then
            # Backing up changes
            current_branch=$(git rev-parse --abbrev-ref HEAD)
            curr_date=$(date +%s)
            backup_branch=vps-$current_branch-$curr_date
            warnmsg "Any changes (uncommitted and committed) will be backed up into branch '%s'\n" "$backup_branch"
            number_of_uncommitted_filed=$(git status --porcelain | wc -l)

            git checkout -qb "$backup_branch" || { errormsg "cannot backup current branch \"%s\", skipping.\n" "$current_branch"; return; }
            if [ "$number_of_uncommitted_filed" -gt 0 ]; then
                # Commit every uncommited thing
                git add -A || { errormsg "cannot backup unsaved changes\n"; return; }
                GIT_COMMITTER_NAME="$VPS_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$VPS_AUTHOR_EMAIL" git commit --author="$VPS_AUTHOR" -m "Backup of $current_branch at $curr_date - staged / unstaged / untracked files / (EXCL. ignored)" || { errormsg "cannot backup unsaved changes\n"; return; }
                warnmsg "All uncommitted changes (excl. ignored) were saved on %s\n" "$backup_branch"
            fi
        else
            warnmsg "Any changes (uncommitted and committed) will be LOST\n"
            git reset -q --hard "origin/$branch"
        fi

        # Going back into root for the brach/commit checkout
        git checkout -q "$branch"
        git reset -q --hard "origin/$branch"
        git pull -q > /dev/null || { errormsg "cannot pull changes for \"%s\"\n" "$directory"; return; }
        cd "$vps_root_dir" || { errormsg "cannot return to versioned patch system root directory\n"; exit 1; }
    else
        infomsg "Cloning module...\n"
        git clone "$url" "$directory" || { errmsg "failed to clone module:%s\n" "$url" ; exit 1; }
    fi

    # Check out branch/commit
    cd "$directory" || { errmsg "cannot enter module directory\n"; exit 1; }
    git checkout -q "$branch"
    head_commit=$(git rev-parse HEAD)
    if [ "$head_commit" != "$commit" ]; then
        warnmsg "HEAD commit of branch \"%s\" does not match wanted commit\n" "$branch"
        warnindent "Wanted:   %s\n" "$commit"
        warnindent "Upstream: %s\n" "$head_commit"
        git checkout "$commit"
    fi
}

for module in $MODULES; do
    update_module "$module"
done
