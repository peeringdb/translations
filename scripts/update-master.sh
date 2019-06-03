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
# cd /efs                                                   && \
#   cd translations.new                                     && \
#   rm -r -f translations                                   && \
#   git clone https://github.com/peeringdb/translations.git && \
#   cd translations                                         && \
#   ./scripts/update-master.sh                              && \
#   rsync --dry-run --delete --archive --verbose /efs/translations.new/translations /efs/translations
#
# Then if the above proves good/safe, remove the "--dry-run" from the rsync line.
#
# The slave servers will then begin using the updated translations automatically.
#

TMP_DIR=`mktemp -d /tmp/pdblocale.XXXXXXXX`
MAKEMSG_OPTIONS="--all --symlinks --no-wrap --no-location --keep-pot"

function clean_up() {
    error_code=$?  # this needs to be here to catch the intended exit code
    set +x
    rm -rf "$TMP_DIR"
    rm -f peeringdb_server
    rm -f django_peeringdb
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
PDB_TAG="NULL"
PDB_TREE="/srv/www.peeringdb.com"
PDB_VERSION="$PDB_TREE/etc/peeringdb.version"
if [ $PDB_TAG = "NULL" ] && [ -f $PDB_VERSION ]; then
    PDB_TAG=`cat $PDB_VERSION`
    PDB_BIN="$PDB_TREE/venv/bin"
fi
PDB_TREE="/srv/beta.peeringdb.com"
PDB_VERSION="$PDB_TREE/etc/peeringdb.version"
if [ $PDB_TAG = "NULL" ] && [ -f $PDB_VERSION ]; then
    PDB_TAG=`cat $PDB_VERSION`
    PDB_BIN="$PDB_TREE/venv/bin"
fi
if [ $PDB_TAG = "NULL" ]; then
    echo Was not able to determine peeringdb version.
    exit 1
fi

# 20190602: Caputo hasn't figured out how to determine version of
# django-peeringdb.git installed, so using latest.  Is this determinable?
# If yes, then duplicate section above for a django_tag and apply below.

(
cd $TMP_DIR && git clone https://github.com/peeringdb/peeringdb.git && cd peeringdb && git checkout $PDB_TAG || exit 1
cd $TMP_DIR && git clone https://github.com/peeringdb/django-peeringdb.git || exit 1
)

ln -s $TMP_DIR/peeringdb/peeringdb_server || exit 1
ln -s $TMP_DIR/django-peeringdb/django_peeringdb || exit 1

echo
echo If \"duplicate message definition\" errors in the below, edit indicated file by removing duplicate that _does_not_ already have a translation, even if commented out.  Then re-run $0 manually.
echo

set -x
$PDB_BIN/django-admin makemessages $MAKEMSG_OPTIONS || exit 1
$PDB_BIN/django-admin makemessages $MAKEMSG_OPTIONS --domain djangojs || exit 1
$PDB_BIN/django-admin compilemessages || exit 1
set +x

