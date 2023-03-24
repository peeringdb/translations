#!/bin/bash
#
# - Pushes updated translations to GitHub.
# - Clones latest PeeringDB projects in order to update translation files.
# - Pushes new translation files.
# - Makes it so Weblate uses the new translation files.
#
# Meant to only be run on the trans0 instance.
#
# As user weblate, can be run from command line or from cron, ala:
#
#   59 * * * * chronic nice -n 19 flock -x -w 240 /tmp/update-local.lock /srv/translate.peeringdb.com/data/vcs/peeringdb/server/scripts/update-locale.sh
#

TMP_DIR=`mktemp -d /tmp/pdblocale.XXXXXXXX`
#MAKEMSG_OPTIONS="--all --symlinks --no-wrap --keep-pot"
MAKEMSG_OPTIONS="--all --symlinks --no-wrap --no-location --keep-pot"
WLC="/srv/translate.peeringdb.com/venv/bin/wlc"
WLC_LOCKED="false"
WORK_DIR="/srv/translate.peeringdb.com/data/vcs/peeringdb/server"

function clean_up() {
    error_code=$?  # this needs to be here to catch the intended exit code
    set +x
    if [ "$WLC_LOCKED" == "true" ]; then
        $WLC unlock peeringdb/server
        $WLC unlock peeringdb/javascript
    fi
    rm -rf "$TMP_DIR"
    rm -f peeringdb_server
    rm -f django_peeringdb
    echo
    echo exiting with $error_code
    exit $error_code
}

trap clean_up EXIT

PDB_TREE="/srv/translate.peeringdb.com"
if [ ! -d $PDB_TREE ]; then
    echo This script is only meant to be run on trans0.peeringdb.com.
    echo Instead run \"update-master.sh\" on production and beta masters.
    exit 1
fi
PDB_BIN="$PDB_TREE/venv/bin"

cd $WORK_DIR || exit 1

(
cd $TMP_DIR
git clone https://github.com/peeringdb/peeringdb.git
git clone https://github.com/peeringdb/django-peeringdb.git
git clone https://github.com/jazzband/django-oauth-toolkit.git
)

server_head=`git --git-dir=$TMP_DIR/peeringdb/.git rev-parse --short HEAD`
django_head=`git --git-dir=$TMP_DIR/django-peeringdb/.git rev-parse --short HEAD`
django_auth_head=`git --git-dir=$TMP_DIR/django-oauth-toolkit/.git rev-parse --short HEAD`

rm -f peeringdb django-peeringdb django-oauth-toolkit # remove symlinks, if any, from failed previous run
ln -s $TMP_DIR/peeringdb || exit 1
ln -s $TMP_DIR/django-peeringdb || exit 1
ln -s $TMP_DIR/django-oauth-toolkit || exit 1

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

# Push new translations from Weblate to upstream repository, in advance of any
# changes as a result of the makemessages integration of sourcecode update.
$WLC push || exit 1 

echo
echo If \"duplicate message definition\" errors in the below, edit indicated file by removing duplicate that _does_not_ already have a translation, even if commented out.  Then re-run $0 manually.
echo

set -x
$PDB_BIN/django-admin makemessages $MAKEMSG_OPTIONS || exit 1
set +x

# 20210716: Specific exception for peeringdb.js regarding "unterminated string" due to:
#  https://code.djangoproject.com/ticket/29175
#  https://github.com/django/django/commit/c3437f734d03d93f798151f712064394652cabed
#  - Since string extraction is done by the ``xgettext`` command, only
#    syntaxes supported by ``gettext`` are supported by Django. Python
#    f-strings_ and `JavaScript template strings`_ are not yet supported by
#    ``xgettext``.
#
#    .. _f-strings: https://docs.python.org/3/reference/lexical_analysis.html#f-strings
#    .. _JavaScript template strings: https://savannah.gnu.org/bugs/?50920
set -x
$PDB_BIN/django-admin makemessages $MAKEMSG_OPTIONS --domain djangojs | grep -v -E "peeringdb.js.*warning: unterminated string|bootstrap/js.*warning: unterminated string" || exit 1
set +x

# Remove these since no longer needed and we don't want them accidentally added to the repo.
rm -f peeringdb
rm -f django-peeringdb
rm -f django-oauth-toolkit

# Remove "POT-Creation-Date:" lines from both .po and .pot files, so that we don't have a diff every run.
find $WORK_DIR -name *.po* -print0 | xargs -0 sed -i /^\"POT-Creation-Date:/d || exit 1

echo
echo Fix any compilemessages messages errors indicated below on the https://translate.peeringdb.com/ site and then re-run $0 manually.
echo
$PDB_BIN/django-admin compilemessages || exit 1

git add locale || exit 1
# Deduce whether to perfom a commit:
[[ -z $(git status --untracked-files=no --porcelain) ]] || git commit -m "new translations (server:$server_head django:$django_head django-oauth-toolkit:$django_auth_head)" || exit 1

$WLC push || exit 1 # Push the result of the git-commit above.
$WLC pull || exit 1 # Tell Weblate to pull changes so it is aware of sourcecode-inspired updates.

# Weblate unlocks are done as part of exit routine auto-cleanup.

