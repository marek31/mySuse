#!/bin/sh
# Git pull and push for mydata
MYDATA="${HOME}/GitHub/mydata"
[ -d "$MYDATA" ] || MYDATA="${HOME}/Github/mydata"

GPP="$MYDATA/code/gitpullpush/gitpullpush"
if [ -x "$GPP" ]; then
    exec "$GPP" "$@"
fi

if [ -d "$MYDATA" ]; then
    echo "Syncing $MYDATA..."
    cd "$MYDATA"
    git pull --rebase || git pull || true
    git push || true
    echo "Done."
fi
