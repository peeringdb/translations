#!/bin/bash
#
# takes arugments `--wlc` and `--commit`
#
# --wlc: use wlc to lock and unlock the projects
#   requires a config file with API key at `~/.config/weblate`
#
# --commit: commit the changes to the translations repo
#
# This clones PeeringDB projects, limited to the installed release tag, to be
# translated.  Adds to the translation files.  Meant to be run on beta and
# prod master and NOT meant to have results committed to upstream repo, since
# the upstream repo is expected to be based later tags.
#
# More docs are available in the deploy repo.
#
# This is best run with a fresh "git clone https://github.com/peeringdb/translations.git"
# of the latest translations from the weblate server.  The idea is this:
#
# As root, one time:
# cd /efs && mkdir -p translations.new && chown pdb:pdb translations.new
#
# As pdb, regularly:
# cd /efs/translations.new                                          && \
#   rm -r -f translations                                           && \
#   chronic git clone https://github.com/peeringdb/translations.git && \
#   cd translations                                                 && \
#   chronic ./scripts/update-master.sh                              && \
#   chronic rsync --dry-run --delete --archive --verbose /efs/translations.new/translations/ /efs/translations
#
# Then if the above proves good/safe, remove the "--dry-run" from the rsync line.
#
# The slave servers will then begin using the updated translations automatically.
#

MAKEMSG_OPTIONS="--all --symlinks --no-wrap --no-location --keep-pot"
# use the pdb-container, which will mount $PWD to /mnt
PDB_DJANGO_ADMIN="/home/pdb/bin/pdb-container"
USE_WLC=false
COMMIT=false
WLC="wlc"
WLC_LOCKED="false"

# reset git repo to be origin default branch
function reset_repository() {
    dir="$1"
    branch=$(git -C "$dir" remote show origin | sed -n '/HEAD branch/s/.*: //p')
    git -C "$dir" checkout "$branch"
    git -C "$dir" fetch origin --prune
    git -C "$dir" reset --hard origin/"$branch"
    git -C "$dir" clean -fdx
}

function clean_up() {
    error_code=$? # this needs to be here to catch the intended exit code
    if [ "$WLC_LOCKED" == "true" ]; then
        $WLC unlock peeringdb/server
        $WLC unlock peeringdb/javascript
    fi
    set +e
    set +x
    echo
    echo exiting with $error_code
    exit $error_code
}

function wlc_lock() {
    # Guidance from https://docs.weblate.org/en/latest/admin/continuous.html
    #
    # Exit if already locked:
    echo
    echo If locked, connect to trans0.peeringdb.com and figure out why. Unlock with:
    echo "    $WLC unlock peeringdb/server"
    echo "    $WLC unlock peeringdb/javascript"
    $WLC lock-status peeringdb/server | grep True && exit 1
    $WLC lock-status peeringdb/javascript | grep True && exit 1

    # Lock weblate components:  (mild race condition here since not atomic)
    WLC_LOCKED="true"
    $WLC lock peeringdb/server || exit 1
    $WLC lock peeringdb/javascript || exit 1

    # tell weblate to push any changes to the repo
    $WLC push
}

function commit_changes() {

    server_head=$(git --git-dir=peeringdb/.git rev-parse --short HEAD)
    django_head=$(git --git-dir=django-peeringdb/.git rev-parse --short HEAD)
    django_auth_head=$(git --git-dir=django-oauth-toolkit/.git rev-parse --short HEAD)

    # Remove "POT-Creation-Date:" lines from both .po and .pot files, so that we don't have a diff every run.
    find $WORK_DIR -name *.po* -print0 | xargs -0 sed -i /^\"POT-Creation-Date:/d || exit 1

    msg="new translations (server:$server_head django:$django_head django-oauth-toolkit:$django_auth_head)"

    git add locale
    # Deduce whether to perfom a commit:
    [[ -z $(git status --untracked-files=no --porcelain) ]] || git commit -m "$msg"

    echo $msg
    git push
}

# Parse optional arguments

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --wlc) USE_WLC=true ;;
    --commit) COMMIT=true ;;
    *)
        echo "Unknown parameter passed: $1"
        exit 1
        ;;
    esac
    shift
done

# load local env if it exists
if [ -f ~/.local/bin/env ]; then
    source ~/.local/bin/env
fi

# committing without lock can cause conflicts
if [ "$COMMIT" == true ] && [ "$USE_WLC" != true ]; then
    echo "--commit requires --wlc to be enabled"
    exit 1
fi

# check for django-admin in path
if ! command -v $PDB_DJANGO_ADMIN &>/dev/null; then
    echo "django-admin could not be found"
    exit 1
fi

# check for wlc requirements
if [ "$USE_WLC" == true ]; then
    if ! command -v $WLC &>/dev/null; then
        echo "wlc could not be found"
        exit 1
    fi
    if [ ! -f ~/.config/weblate ]; then
        echo "wlc config file not found"
        exit 1
    fi
fi

trap clean_up EXIT

echo "Running update-master.sh with WLC=$WLC, COMMIT=$COMMIT"

# exit on error
set -e

if [ -d "/srv/translate.peeringdb.com" ]; then
    echo This script is only meant to be run on production and beta masters.
    echo Run \"update-locale.sh\" on translation server \(trans0\).
    exit 1
fi

# Determine peeringdb.git version currently deployed:
PDB_TAG=$(docker image inspect peeringdb_server:latest | grep -o "peeringdb_server:[0-9][^,]*" | cut -d ':' -f2 | sed 's/["|,]//g')

# 20190602: Caputo hasn't figured out how to determine version of
# django-peeringdb.git installed, so using latest.  Is this determinable?
# If yes, then duplicate section above for a django_tag and apply below.

# if dir does not exist, clone it
if [ ! -d "peeringdb" ]; then
    git clone https://github.com/peeringdb/peeringdb.git
else
    reset_repository "peeringdb"
fi
git -C peeringdb checkout $PDB_TAG

if [ ! -d "django-peeringdb" ]; then
    git clone https://github.com/peeringdb/django-peeringdb.git
else
    reset_repository "django-peeringdb"
fi

if [ ! -d "django-oauth-toolkit" ]; then
    git clone https://github.com/jazzband/django-oauth-toolkit.git
else
    reset_repository "django-oauth-toolkit"
fi

if [ "$USE_WLC" == true ]; then
    wlc_lock
fi

echo
echo If \"duplicate message definition\" errors in the below, edit indicated file by removing duplicate that _does_not_ already have a translation, even if commented out. Then re-run $0 manually.
echo

set -x
$PDB_DJANGO_ADMIN makemessages $MAKEMSG_OPTIONS
$PDB_DJANGO_ADMIN makemessages $MAKEMSG_OPTIONS --domain djangojs
$PDB_DJANGO_ADMIN compilemessages
set +x

if [ "$COMMIT" == true ]; then
    commit_changes
    # tell weblate to pull changes
    $WLC pull
fi
