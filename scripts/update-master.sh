#!/bin/bash
#
# clones PeeringDB projects, limited to the installed release tag, to be
# translated.  Adds to the translation files.  Meant to be run on beta and
# prod master and NOT meant to have results committed to upstream repo, since
# the upstream repo is expected to be based later tags.
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

function clean_up() {
    error_code=$?  # this needs to be here to catch the intended exit code
    set +x
    rm -r -f peeringdb
    rm -r -f django-peeringdb
    rm -r -f django-oauth-toolkit
    echo
    echo exiting with $error_code
    exit $error_code
}

trap clean_up EXIT

if [ -d "/srv/translate.peeringdb.com" ]; then
    echo This script is only meant to be run on production and beta masters.
    echo Run \"update-locale.sh\" on translation server \(trans0\).
    exit 1
fi

# Determine peeringdb.git version currently deployed:
PDB_DJANGO_ADMIN="/home/pdb/bin/pdb-container"
PDB_TAG=`docker image inspect pdb:server-latest | grep peeringdb:server | tr -d '\"' | cut -f 2 -d '-'`

# 20190602: Caputo hasn't figured out how to determine version of
# django-peeringdb.git installed, so using latest.  Is this determinable?
# If yes, then duplicate section above for a django_tag and apply below.

(
git clone https://github.com/peeringdb/peeringdb.git && cd peeringdb && git checkout $PDB_TAG || exit 1
git clone https://github.com/peeringdb/django-peeringdb.git || exit 1
git clone https://github.com/jazzband/django-oauth-toolkit.git || exit 1
)

echo
echo If \"duplicate message definition\" errors in the below, edit indicated file by removing duplicate that _does_not_ already have a translation, even if commented out.  Then re-run $0 manually.
echo

set -x
$PDB_DJANGO_ADMIN makemessages $MAKEMSG_OPTIONS || exit 1
$PDB_DJANGO_ADMIN makemessages $MAKEMSG_OPTIONS --domain djangojs || exit 1
$PDB_DJANGO_ADMIN compilemessages || exit 1
set +x

