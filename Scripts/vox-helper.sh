#!/bin/sh
# Runs tmux and ps outside the App Sandbox for Vox's "vox pi" / "vox claude" commands, and the
# voice command templates from Settings → Comandos de voz.
# Sandboxed apps can only run user-installed scripts via NSUserUnixTask, so install with:
#   mkdir -p ~/Library/Application\ Scripts/dev.pplanel.vox
#   cp Scripts/vox-helper.sh ~/Library/Application\ Scripts/dev.pplanel.vox/
#   chmod +x ~/Library/Application\ Scripts/dev.pplanel.vox/vox-helper.sh
# Only tmux, ps, folder listings and confirmed templates ("vox sim") are allowed.

user="$(id -un)"
home="${HOME:-$(eval echo "~$user")}"
export PATH="/etc/profiles/per-user/$user/bin:/run/current-system/sw/bin:$home/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

case "$1" in
    tmux) shift; exec tmux "$@" ;;
    ps) shift; exec /bin/ps "$@" ;;
    # Folders inside a directory, for filling an entity's values; "~" means the real home.
    subfolders)
        dir="$2"
        case "$dir" in "~"*) dir="$home${dir#\~}" ;; esac
        for sub in "$dir"/*/; do
            [ -d "$sub" ] && printf '%s\n' "${sub%/}"
        done
        exit 0 ;;
    # A template with "Segundo plano", detached; output goes to ~/Library/Logs/vox-commands.log.
    run)
        mkdir -p "$home/Library/Logs"
        cd "$home" && nohup /bin/sh -c "$2" >>"$home/Library/Logs/vox-commands.log" 2>&1 </dev/null &
        exit 0 ;;
    *) echo "vox-helper: comando não permitido: $1" >&2; exit 64 ;;
esac
