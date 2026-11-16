import Foundation

/// The shell script that swaps the running app for the new one. It must run
/// after the app has quit, so the app starts it detached and then exits.
///
/// Arguments are passed positionally, never spliced into the script text, so a
/// path cannot inject commands:
///   $1 pid of the running app   $2 new app   $3 installed app   $4 backup path
///   $5 command used to relaunch (normally /usr/bin/open)
public enum UpdateScript {
    public static let text = """
    #!/bin/sh
    pid="$1"; new="$2"; target="$3"; backup="$4"; relaunch="$5"

    # Wait up to 20 seconds for the app to quit. If it never does, change nothing.
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 100 ]; do
        sleep 0.2
        i=$((i + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then exit 1; fi

    rm -rf "$backup"
    mv "$target" "$backup" || exit 1
    if /usr/bin/ditto "$new" "$target"; then
        /usr/bin/xattr -cr "$target" 2>/dev/null
        rm -rf "$backup" "$new"
        "$relaunch" "$target"
        exit 0
    fi

    # The copy failed: put the old app back so nothing is lost.
    rm -rf "$target"
    mv "$backup" "$target"
    "$relaunch" "$target"
    exit 1
    """
}
