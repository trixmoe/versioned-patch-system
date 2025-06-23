#!/bin/sh
# shellcheck source=./scripts/common.sh
. "$(dirname "$0")/common.sh"

# cd into project root
rootdir >/dev/null

. $MODULES_FILE_ROOTDIR

print_help()
{
    printf "Usage: cleandir.sh\n"
    printf "This script loops through the modules and deletes all directories.\n\n"

    printf "  --one    Only save a single tag (generic)\n"
    printf "  --help   Show this help menu\n"
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


for module in $MODULES; do
    infomsg "Removing module: %s\n" "$module"

    # Get module information
    module_dir="" # SC2154/SC2034
    eval module_dir="\$${module}_DIRECTORY"

    # Remove module, if it exists
    if [ -d "$module_dir" ]; then
        rm -rf "$module_dir" || { errormsg "failed to remove existing module directory\n"; exit 1; }
    fi
done
