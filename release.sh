#!/bin/bash
#
# This script automates release into delivery branch from development branch:
# 1.) Applies chosen commits from current branch to local copy of the delivery
#     branch.
# 2.) Removes unwanted files (from .release_ignore file) and squashes all the commits.
# 3.) Pushes to the remote delivery branch.
#
# Command line arguments:
# $1 - first commit from which we start squashing up to HEAD.
# $2 - TAG name which will be added to the commits on development and delivery branches.
# $3 - optional '--continue' flag to continue execution after failed cherry-pick.

# Local development branch has to be named main.
development_branch="main"
delivery_branch="delivery"

# This function takes two arguments:
# $1 - cherry pick command output.
# $2 - cherry pick comand return code.
check_cherry_pick_and_push()
{
    if [[ "$2" -ne "0" ]]; then
        # Copy this script version from development to local delivery branch.
        git checkout --quiet current-copy release.sh
        git checkout --quiet current-copy .release_ignore

        >&2 echo "Error: Couldn't cherry pick release commit on the delivery branch."
        >&2 echo "Note: Please do further steps:"
        >&2 echo "  1.) Check git message below."
        >&2 echo "  2.) Reslove conflicts."
        >&2 echo "  3.) Add files to the staging area."
        >&2 echo "  4.) Re-run script with --continue flag as a third argument.\n"
        >&2 echo "Git error:"
        >&2 echo "$1"

        exit 1
    else
        # Remove script and ignore file from the delviery branch before final push.
        git rm --quiet release.sh
        git rm --quiet .release_ignore
        git commit --quiet --amend --no-edit

        # Change to: git push origin delivery
        git tag "$release_tag-dev" $development_branch
        git tag $release_tag HEAD

        git push origin HEAD:$delivery_branch
        git push origin tag $release_tag
        git push origin tag "$release_tag-dev"

        git checkout --quiet $development_branch
        git branch --quiet -D delivery-local current-copy
        exit 0
    fi
}

# Abort if there is any cherry-pick currently in progress
if [[ ! -f ".release_ignore" ]]; then
    >&2 echo "Error: Cannot find .release_ignore file in the current directory."
    exit 1
fi

if [[ -z "$1" ]]; then
    >&2 echo "Error: Pass SHA of the first release commit as a command line argument."
    exit 1
fi

if [[ -z "$2" ]]; then
    >&2 echo "Error: Pass TAG name for the release as the second command line argument."
    exit 1
fi

first_commit=$1
release_tag=$2

if [[ "$3" = "--continue" ]]; then
    git rm --quiet -f release.sh
    git rm --quiet -f .release_ignore

    cherry_pick_out=$(git cherry-pick --continue --no-edit)
    check_cherry_pick_and_push "$cherry_pick_out" "$?"
fi

if [[ $(git status --porcelain) ]]; then
    >&2 echo "Error: Please commit or stash all your local changes before running the script."
    exit 1
fi

current_branch=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD)

if [[ "$current_branch" != "main" ]]; then
    echo "Error: Current local development branch has to be named $development_branch."
    exit 1
fi

readarray -t ignore_files < .release_ignore

git fetch --quiet
git branch --quiet current-copy
git branch --quiet delivery-local "origin/$delivery_branch"

git checkout --quiet current-copy

for i in "${ignore_files[@]}"
    do
        git rm $i
done

git reset --quiet --soft $first_commit~1

# Let the user type in commit message for the release commit.
git commit

# Abort if there is any cherry-pick currently in progress
if [[ -f ".git/CHERRY_PICK_HEAD" ]]; then
    >&2 echo "Error: There is already cherry pick in progress."
    exit 1
fi

git checkout --quiet delivery-local
cherry_pick_out=$(git cherry-pick current-copy 2>&1)

check_cherry_pick_and_push "$cherry_pick_out" "$?"
