#! /bin/sh

set -e

BACKUPDIR="$1"
if [ ! -d "$BACKUPDIR" ]; then
    echo "Backup path '$BACKUPDIR' is not a directory :-(" >&2
    exit 1
fi

BOLTDB="$2"
if [ ! -f "$BOLTDB" ]; then
    echo "BoltDB file '$BOLTDB' not found :-(" >&2
    exit 1
fi

DATE="$(date "+%Y-%m-%d.%H:%M")"
BACKUPFILE="$BACKUPDIR/sp0rkle.boltdb.$DATE.gz"

# The bot performs periodic internal backups using tx.Copy() which is safer
# for a live database. This script provides a manual way to backup the file.

gzip -c "$BOLTDB" > "$BACKUPFILE"

echo "Wrote backup to $BACKUPFILE"
