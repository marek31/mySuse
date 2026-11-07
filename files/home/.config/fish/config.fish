if status is-interactive
    set -g fish_greeting
    command -v zoxide >/dev/null && zoxide init fish | source
    command -v starship >/dev/null && starship init fish | source

    alias ls 'eza -al --color=always --group-directories-first'
    alias la 'eza -a --color=always --group-directories-first'
    alias ll 'eza -l --color=always --group-directories-first'
    alias lt 'eza -aT --color=always --group-directories-first'
    alias cat 'bat --paging=never'

    # zypper abbreviations (snapper automatically creates pre/post snapshots via snapper-zypp-plugin)
    abbr zu 'sudo zypper dup'
    abbr zi 'sudo zypper in'
    abbr zr 'sudo zypper rm'
    abbr zq 'zypper se'
    abbr snaps 'snapper -c root list'
    abbr suse-update 'sudo ~/mySuse/setup.sh apps'

    # Auto-install MMAutoKey once mydata is downloaded from GitHub
    if not test -f ~/.config/autostart/mmautokey.desktop
        for d in ~/Github/mydata/code/MMAutoKey_linux ~/GitHub/mydata/code/MMAutoKey_linux
            if test -f "$d/install.sh"
                bash "$d/install.sh" >/dev/null 2>&1 &
                break
            end
        end
    end
end
