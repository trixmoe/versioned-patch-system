#!/bin/sh
# shellcheck source=./scripts/common.sh
. "$(dirname "$0")/common.sh"

print_help()
{
    printf "Usage: test.sh\n"
    printf "Runs tests on vps to verify functionality.\n"
    warnf  "The tests will not run if modules are already cloned.\n"
}

quiet=false
while :; do
    case $1 in
        -\?|--help)
            print_help
            exit
            ;;
        -q)
            quiet=true
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

vps_root_dir=$(rootdir)

# ------------------------------------------------------------------------------
# Setup

# Cleanup trap if anything big fails
cleanup()
{
    if [ -n "$MODULES_FILE_ROOTDIR" ]; then
        for module in $MODULES; do
            directory="" # SC2154/SC2034
            eval directory="\$${module}_DIRECTORY"
            [ -d "$directory" ] && rm -fr "$directory"
            [ -d "patches/$directory" ] && rm -r "patches/$directory"
        done
        rm "$MODULES_FILE_ROOTDIR"
    fi
}

trap cleanup EXIT

# Helper functions
PASS='[✅]'
FAIL='[❌]'
FAILED_TESTS=0
PASSED_TESTS=0

# shellcheck disable=SC2059,SC2145
# Fails due to color variable inside printf
# + mixing string and array (needed for printf-like behaviour)
passmsg() {
    printf "$BOLD$COLOR_GREEN$PASS $@" >&2
    printf "$RT" >&2
}
# shellcheck disable=SC2059,SC2145
failmsg() {
    printf "$BOLD$COLOR_RED$FAIL $@" >&2
    printf "$RT" >&2
}

runtest() {
    if ! output=$($1 2>&1); then
        failmsg "%s failed. Given output:\n" "$1"
        echo "$output" | sed 's/\r//g; s/^/   /'
        FAILED_TESTS=$((FAILED_TESTS+1))
    else
        passmsg "%s passed.\n" "$1"
        [ "$quiet" = "false" ] && echo "$output" | sed 's/\r//g; s/^/   /'
        PASSED_TESTS=$((PASSED_TESTS+1))
    fi
}

# Create testing modules file
export MODULES_FILE_ROOTDIR="$vps_root_dir/testmodules"
cat << EOF > "$vps_root_dir/testmodules"
MODULES="GITHUBIGNORE CHEATSHEET"

GITHUBIGNORE_URL="https://github.com/github/gitignore.git"
GITHUBIGNORE_BRANCH="main"
GITHUBIGNORE_COMMIT="57208bef833f2f8286cd6dae5a2eeb3d314e3b31"
GITHUBIGNORE_DIRECTORY="github-ignore"

CHEATSHEET_URL="https://github.com/githubtraining/github-cheat-sheet"
CHEATSHEET_BRANCH="master"
CHEATSHEET_COMMIT="80dbfe09af7da6a1c5bb4b5bb7a89025675312a4"
CHEATSHEET_DIRECTORY="github-sheet"

EOF
infomsg "Created modules file for testing...\n"

. "$MODULES_FILE_ROOTDIR"

# ------------------------------------------------------------------------------
# Check before testing

for module in $MODULES; do
    directory="" # SC2154/SC2034
    eval directory="\$${module}_DIRECTORY"

    if [ -d "$directory" ]; then
        errormsg "Cancelling test. One of the test directories already exists: \"%s\".\n" "$directory"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# Testing

# Update modules
make_update() (
    make update
)

runtest make_update

# Make a single generic commit, tag it as such, and save it
generic_commit() (
    set -e
    
    cd github-ignore
    # Create commit incl. tag
    echo "test" >> README.md
    git add README.md
    git config user.name "test"
    git config user.email "test@example.org"
    git commit -m "test"
    git tag generic

    # Save commit as a patch
    cd ../
    make save-one

    # Check if commit exists
    ls patches/github-ignore/generic/0001-test.patch
)

runtest generic_commit

# Checks what happens if a commit is ammended, it should delete the old file(s) and re-create new one(s)
change_generic_commit() (
    set -e

    cd github-ignore
    # ammend existing commit
    echo nevermind >> README.md
    git add README.md
    git commit --amend -m "not"
    git tag -f generic

    # Save commit as a patch
    cd ../
    make save-one

    # Check if only 1 commit exists
    ls patches/github-ignore/generic/0001-not.patch
    infomsg "The following files are present:\n"
    ls patches/github-ignore/generic/
    files=$(find patches/github-ignore/generic/ -maxdepth 1 -type f  | wc -l)
    [ "$files" -eq 1 ] || { errormsg "There is more than 1 patch file (%s), it does not delete old patches on save\n" "$files"; exit 1; }
)

runtest change_generic_commit

# utility: get the top-most commit hash, useful to check if everything applies properly
get_ghignore_commit_hash() (
    set -e
    cd github-ignore
    git rev-parse HEAD
)
# Save the top-most commit in generic
GENERIC_COMMIT_HASH=$(get_ghignore_commit_hash)

# Create 2 specific commits and save them, tests if it can save on-top of pre-existing commits without breaking
specific_commits() (
    set -e

    cd github-ignore
    # Set Git identity for specific commits
    git config user.name "specific"
    git config user.email "test@example.com"

    # Commit 1
    echo "specific" > README.md
    git add README.md
    git commit -m "this is very specific"

    # Commit 2
    echo "empty" >> empty
    git add empty
    git commit -m "new empty file"

    # Tag
    git tag specific

    # Save commits
    cd ../
    make save

    # Check if patches exist
    ret_code=0
    ls -R patches/github-ignore/generic/*
    ls -R patches/github-ignore/specific/*
    files=$(find patches/github-ignore/specific/ -maxdepth 1 -type f  | wc -l)
    [ "$files" -eq 2 ] || { errormsg "There are not 2 patch files (%s), make save is not working as expected.\n" "$files"; ret_code=1; }

    # Try to save-one (only specific)
    rm -r patches/github-ignore
    make save-one
    ls -R patches/github-ignore/specific/*
    files=$(find patches/github-ignore/specific/ -maxdepth 1 -type f  | wc -l)
    [ "$files" -eq 2 ] || { errormsg "There are not 2 patch files (%s), make save-one is not working as expected.\n" "$files"; ret_code=1; }
    ls -R patches/github-ignore/generic/* 2>/dev/null && { errormsg "\"make save-one\" saves more than 1 patchset."; ret_code=1 ; }

    # Reset to save without pre-existing files
    rm -r patches/github-ignore
    make save
    ls -R patches/github-ignore/generic/*
    ls -R patches/github-ignore/specific/*
    exit $ret_code
)

runtest specific_commits

# Save the top-most commit in specific
SPECIFIC_COMMIT_HASH=$(get_ghignore_commit_hash)

# Reset the working dir (no patches) by using make update
reset_workingdir() (
    set -e
    make update
    cd github-ignore
    current_hash=$(git rev-parse HEAD)
    expected_hash="";
    eval expected_hash="\$GITHUBIGNORE_COMMIT"
    [ "$current_hash" = "$expected_hash" ] || { errormsg "Resetting modules didn't work, hash is not as-expected, \"%s\" instead of \"%s\"\n" "$current_hash" "$expected_hash"; exit 1; }
    # Check if backup branch was created
    git branch --list | tr -d ' ' | grep "vps-backup-" >/dev/null 2>&1 || { errormsg "'make update' didn't create a backup branch.\n"; exit 1; }
)

runtest reset_workingdir

# Test backup branch created with 'make update'
test_backup_branch() (
    set -e
    cd github-ignore
    # Make current state be the backup branch
    backup_branch=$(git branch --list | tr -d ' ' | grep "vps-backup-")
    [ -n "$backup_branch" ] || { errormsg "No backup branch found to test restore.\n"; exit 1; }
    git reset --hard "$backup_branch"
    # Check commit hash
    current_hash=$(git rev-parse HEAD)
    expected_hash="";
    eval expected_hash="\$SPECIFIC_COMMIT_HASH"
    [ "$current_hash" = "$expected_hash" ] || { errormsg "Restoring from backup didn't work, hash is not as-expected, \"%s\" instead of \"%s\"\n" "$current_hash" "$expected_hash"; exit 1; }
)

runtest test_backup_branch

# Test 'make nupdate'
reset_workingdir_without_backup() (
    set -e
    # Delete the backup branch first
    cd github-ignore
        if backup_branch=$(git branch --list | tr -d ' ' | grep "vps-backup-"); then
            [ -n "$backup_branch" ] || { errormsg "No backup branch found to delete.\n"; exit 1; }
            git branch -D "$backup_branch"
        fi
    cd ../
    # Reset the working directory
    make nupdate
    cd github-ignore
    # Check that it was reset as-expected
    current_hash=$(git rev-parse HEAD)
    expected_hash="";
    eval expected_hash="\$GITHUBIGNORE_COMMIT"
    [ "$current_hash" = "$expected_hash" ] || { errormsg "Resetting modules with no backup didn't work, hash is not as-expected, \"%s\" instead of \"%s\"\n" "$current_hash" "$expected_hash"; exit 1; }
    # Check if backup branch was NOT created
    if git branch --list | tr -d ' ' | grep "vps-backup-" >/dev/null 2>&1; then
        errormsg "'make nupdate' created a backup branch, but it shouldn't.\n"
        exit 1
    fi
)

runtest reset_workingdir_without_backup

# Apply the single generic commit
apply_generic_commit() (
    set -e

    make generic
    cd github-ignore
    current_hash=$(git rev-parse HEAD)
    [ "$current_hash" = "$GENERIC_COMMIT_HASH" ] || { errormsg "The applied commit does not have the same hash as the saved commit: \"%s\" instead of \"%s\"\n" "$current_hash" "$GENERIC_COMMIT_HASH"; exit 1; }
)

runtest apply_generic_commit

# Apply the many specific commits
apply_specific_commits() (
    set -e

    make specific
    cd github-ignore
    current_hash=$(git rev-parse HEAD)
    [ "$current_hash" = "$SPECIFIC_COMMIT_HASH" ] || { errormsg "The applied commit does not have the same hash as the saved commit: \"%s\" instead of \"%s\"\n" "$current_hash" "$SPECIFIC_COMMIT_HASH"; exit 1; }
)

infomsg "${COLOR_PURPLE}The following test runs on top of the existing generic commit, to see if it will only apply a single patchset$RT\n"
runtest apply_specific_commits

# Delete branches (if all tests run quickly, it might cause issues as branch names use seconds, so they would error out due to the same name)
delete_branches() (
    set -e
    cd github-ignore
    git branch --list | tr -d ' ' | grep "vps-" | xargs -I {} git branch -D {}
    cd ../github-sheet
    git branch --list | tr -d ' ' | grep "vps-" | xargs -I {} git branch -D {}
)

infomsg "${COLOR_PURPLE}Info: The working dir is reset for a proper specific commits application test with both patchsets$RT\n"
runtest delete_branches
runtest reset_workingdir
runtest apply_specific_commits

# ------------------------------------------------------------------------------
# Summary

total_tests=$((FAILED_TESTS+PASSED_TESTS))
# shellcheck disable=SC2059
printf "$RT---------------------------\n"
# shellcheck disable=SC2059
printf "          ${BOLD}SUMMARY${RT}\n"
printf "    Total tests  :   %s\n" "$total_tests"
printf "    Passed tests :   %s\n" "$PASSED_TESTS"
printf "    Failed tests :   %s\n" "$FAILED_TESTS"
printf "\n"

# shellcheck disable=SC2059
if [ $FAILED_TESTS -eq 0 ]; then
    printf "${BOLD}${UNDERLINE}${COLOR_GREEN}${PASS} All tests have passed.$RT\n"
else
    printf "${BOLD}${UNDERLINE}${COLOR_RED}${FAIL} %s tests failed !$RT\n" "$FAILED_TESTS"
    exit 1
fi
# ------------------------------------------------------------------------------
