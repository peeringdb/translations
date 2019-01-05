#!/bin/bash
# clones PeeringDB projects to be translated and adds to the translation files

TMP_DIR=`mktemp -d /tmp/pdblocale.XXXXXXXX`
#MAKEMSG_OPTIONS="--all --symlinks --no-wrap --keep-pot"
MAKEMSG_OPTIONS="--all --symlinks --no-wrap --no-location --keep-pot"


function clean_up() {
    rm -rf "$TMP_DIR"
    rm -f peeringdb_server
    rm -f django_peeringdb

    error_code=$?
    echo exiting with $error_code
    exit $error_code
}

trap clean_up EXIT


(
cd $TMP_DIR
git clone https://github.com/peeringdb/peeringdb.git
git clone https://github.com/peeringdb/django-peeringdb.git
)

server_head=`git --git-dir=$TMP_DIR/peeringdb/.git rev-parse --short HEAD`
django_head=`git --git-dir=$TMP_DIR/django-peeringdb/.git rev-parse --short HEAD`

if test -e peeringdb_server; then
    echo peeringdb_server exists
    exit 1
fi
if test -e django_peeringdb; then
    echo django_peeringdb exists
    exit 1
fi
 
ln -s $TMP_DIR/peeringdb/peeringdb_server
ln -s $TMP_DIR/django-peeringdb/django_peeringdb

django-admin makemessages $MAKEMSG_OPTIONS
django-admin makemessages $MAKEMSG_OPTIONS --domain djangojs

echo please review and commit with
echo git commit -a -S -m \"update from server:$server_head django:$django_head\"
