# -*- mode: shell-script -*-

# This is a port of Doug Hellmann's virtualenvwrapper for Python 3 venv
#
# Shell functions to act as wrapper for venv https://docs.python.org/3/library/venv.html
#
# Copyright Viraj Kanwade, All Rights Reserved
#
# Project home page: https://github.com/virajkanwade/venvwrapper
#
#
# Setup:
#
#  1. Add a line like "source /path/to/this/file/venvwrapper.sh"
#     to your .bashrc.
#  2. Run: source ~/.bashrc
#  3. Run: workonvenv
#  4. A list of environments, empty, is printed.
#  5. Run: mkvenv temp
#  6. Run: workonvenv
#  7. This time, the "temp" environment is included.
#  8. Run: workonvenv temp
#  9. The virtual environment is activated.
#

# Locate the global Python where VENVWRAPPER is installed.
if [ "${VENVWRAPPER_PYTHON:-}" = "" ]
then
    VENVWRAPPER_PYTHON="$(command \which python3)"
fi

# Set the name of the venv app to use.
if [ "${VENVWRAPPER_VENV:-}" = "" ]
then
    VENVWRAPPER_VENV="$VENVWRAPPER_PYTHON -m venv"
fi

: <<'end_long_comment'
# Set the name of the venv-clone app to use.
if [ "${VENVWRAPPER_VENV_CLONE:-}" = "" ]
then
    VENVWRAPPER_VENV_CLONE="venv-clone"
fi
end_long_comment

# Define script folder depending on the platorm (Win32/Unix)
VENVWRAPPER_ENV_BIN_DIR="bin"
if [ "${OS:-}" = "Windows_NT" ] && ([ "${MSYSTEM:-}" = "MINGW32" ] || [ "${MSYSTEM:-}" = "MINGW64" ])
then
    # Only assign this for msys, cygwin use standard Unix paths
    # and its own python installation
    VENVWRAPPER_ENV_BIN_DIR="Scripts"
fi

# Let the user override the name of the file that holds the project
# directory name.
if [ "${VENVWRAPPER_PROJECT_FILENAME:-}" = "" ]
then
    export VENVWRAPPER_PROJECT_FILENAME=".project"
fi

# Let the user tell us they never want to cd to projects
# automatically.
export VENVWRAPPER_WORKON_CD=${VENVWRAPPER_WORKON_CD:-1}

# Remember where we are running from.
if [ -z "${VENVWRAPPER_SCRIPT:-}" ]
then
    if [ -n "$BASH" ]
    then
        export VENVWRAPPER_SCRIPT="$BASH_SOURCE"
    elif [ -n "$ZSH_VERSION" ]
    then
        export VENVWRAPPER_SCRIPT="$0"
    else
        export VENVWRAPPER_SCRIPT="${.sh.file}"
    fi
fi

# Portable shell scripting is hard, let's go shopping.
#
# People insist on aliasing commands like 'cd', either with a real
# alias or even a shell function. Under bash and zsh, "builtin" forces
# the use of a command that is part of the shell itself instead of an
# alias, function, or external command, while "command" does something
# similar but allows external commands. Under ksh "builtin" registers
# a new command from a shared library, but "command" will pick up
# existing builtin commands. We need to use a builtin for cd because
# we are trying to change the state of the current shell, so we use
# "builtin" for bash and zsh but "command" under ksh.
function venvwrapper_cd {
    if [ -n "${BASH:-}" ]
    then
        builtin \cd "$@"
    elif [ -n "${ZSH_VERSION:-}" ]
    then
        builtin \cd -q "$@"
    else
        command \cd "$@"
    fi
}

function venvwrapper_expandpath {
    if [ "$1" = "" ]; then
        return 1
    else
        "$VENVWRAPPER_PYTHON" -c "import os,sys; sys.stdout.write(os.path.normpath(os.path.expanduser(os.path.expandvars(\"$1\")))+'\n')"
        return 0
    fi
}

function venvwrapper_absolutepath {
    if [ "$1" = "" ]; then
        return 1
    else
        "$VENVWRAPPER_PYTHON" -c "import os,sys; sys.stdout.write(os.path.abspath(\"$1\")+'\n')"
        return 0
    fi
}

function venvwrapper_derive_workon_home {
    typeset workon_home_dir="$VENV_WORKON_HOME"

    # Make sure there is a default value for WORKON_HOME.
    # You can override this setting in your .bashrc.
    if [ "$workon_home_dir" = "" ]
    then
        workon_home_dir="$HOME/.venvs"
    fi

    # If the path is relative, prefix it with $HOME
    # (note: for compatibility)
    if echo "$workon_home_dir" | (unset GREP_OPTIONS; command \grep '^[^/~]' > /dev/null)
    then
        workon_home_dir="$HOME/$VENV_WORKON_HOME"
    fi

    # Only call on Python to fix the path if it looks like the
    # path might contain stuff to expand.
    # (it might be possible to do this in shell, but I don't know a
    # cross-shell-safe way of doing it -wolever)
    if echo "$workon_home_dir" | (unset GREP_OPTIONS; command \egrep '([\$~]|//)' >/dev/null)
    then
        # This will normalize the path by:
        # - Removing extra slashes (e.g., when TMPDIR ends in a slash)
        # - Expanding variables (e.g., $foo)
        # - Converting ~s to complete paths (e.g., ~/ to /home/brian/ and ~arthur to /home/arthur)
        workon_home_dir="$(venvwrapper_expandpath "$workon_home_dir")"
    fi

    echo "$workon_home_dir"
    return 0
}

# Check if the VENV_WORKON_HOME directory exists,
# create it if it does not
# seperate from creating the files in it because this used to just error
# and maybe other things rely on the dir existing before that happens.
function venvwrapper_verify_workon_home {
    RC=0
    if [ ! -d "$VENV_WORKON_HOME/" ]
    then
        if [ "$1" != "-q" ]
        then
            echo "NOTE: Virtual environments directory $VENV_WORKON_HOME does not exist. Creating..." 1>&2
        fi
        mkdir -p "$VENV_WORKON_HOME"
        RC=$?
    fi
    return $RC
}

# Function to wrap mktemp so tests can replace it for error condition
# testing.
function venvwrapper_mktemp {
    command \mktemp "$@"
}

# Expects 1 argument, the suffix for the new file.
function venvwrapper_tempfile {
    # Note: the 'X's must come last
    typeset suffix=${1:-hook}
    typeset file

    file="$(venvwrapper_mktemp -t venvwrapper-$suffix-XXXXXXXXXX)"
    touch "$file"
    if [ $? -ne 0 ] || [ -z "$file" ] || [ ! -f "$file" ]
    then
        echo "ERROR: venvwrapper could not create a temporary file name." 1>&2
        return 1
    fi
    echo $file
    return 0
}

# Run the hooks
function venvwrapper_run_hook {
    # XXX
    return 0
    typeset hook_script
    typeset result

    hook_script="$(venvwrapper_tempfile ${1}-hook)" || return 1

    # Use a subshell to run the python interpreter with hook_loader so
    # we can change the working directory. This avoids having the
    # Python 3 interpreter decide that its "prefix" is the venv
    # if we happen to be inside the venv when we start.
    ( \
        venvwrapper_cd "$VENV_WORKON_HOME" &&
        "$VENVWRAPPER_PYTHON" -m 'venvwrapper.hook_loader' \
            ${VENV_HOOK_VERBOSE_OPTION:-} --script "$hook_script" "$@" \
    )
    result=$?

    if [ $result -eq 0 ]
    then
        if [ ! -f "$hook_script" ]
        then
            echo "ERROR: venvwrapper_run_hook could not find temporary file $hook_script" 1>&2
            command \rm -f "$hook_script"
            return 2
        fi
        # cat "$hook_script"
        source "$hook_script"
    elif [ "${1}" = "initialize" ]
    then
        cat - 1>&2 <<EOF
venvwrapper.sh: There was a problem running the initialization hooks.

If Python could not import the module venvwrapper.hook_loader,
check that venvwrapper has been installed for
VENVWRAPPER_PYTHON=$VENVWRAPPER_PYTHON and that PATH is
set properly.
EOF
    fi
    command \rm -f "$hook_script"
    return $result
}

# Set up tab completion.  (Adapted from Arthur Koziel's version at
# http://arthurkoziel.com/2008/10/11/virtualenvwrapper-bash-completion/)
function venvwrapper_setup_tab_completion {
    if [ -n "${BASH:-}" ] ; then
        _venvs () {
            local cur="${COMP_WORDS[COMP_CWORD]}"
            COMPREPLY=( $(compgen -W "`venvwrapper_show_workon_options`" -- ${cur}) )
        }
        _cdvenv_complete () {
            local cur="$2"
            COMPREPLY=( $(cdvenv && compgen -d -- "${cur}" ) )
        }
        _cdsitepackages_complete () {
            local cur="$2"
            COMPREPLY=( $(cdsitepackagesvenv && compgen -d -- "${cur}" ) )
        }
        complete -o nospace -F _cdvenv_complete -S/ cdvenv
        complete -o nospace -F _cdsitepackagesvenv_complete -S/ cdsitepackagesvenv
        complete -o default -o nospace -F _venvs workonvenv
        complete -o default -o nospace -F _venvs rmvenv
        complete -o default -o nospace -F _venvs cpvenv
        complete -o default -o nospace -F _venvs showvenv
    elif [ -n "$ZSH_VERSION" ] ; then
        _venvs () {
            reply=( $(venvwrapper_show_workon_options) )
        }
        _cdvenv_complete () {
            reply=( $(cdvenv && ls -d ${1}*) )
        }
        _cdsitepackagesvenv_complete () {
            reply=( $(cdsitepackagesenv && ls -d ${1}*) )
        }
        compctl -K _venvs workon rmvenv cpvenv showvenv
        compctl -K _cdvenv_complete cdvenv
        compctl -K _cdsitepackages_complete cdsitepackagesvenv
    fi
}

# Set up venvwrapper properly
function venvwrapper_initialize {
    export VENV_WORKON_HOME="$(venvwrapper_derive_workon_home)"

    venvwrapper_verify_workon_home -q || return 1

    # Set the location of the hook scripts
    if [ "$VENVWRAPPER_HOOK_DIR" = "" ]
    then
        VENVWRAPPER_HOOK_DIR="$VENV_WORKON_HOME"
    fi
    export VENVWRAPPER_HOOK_DIR

    mkdir -p "$VENVWRAPPER_HOOK_DIR"

    venvwrapper_run_hook "initialize"

    venvwrapper_setup_tab_completion

    return 0
}

: <<'end_long_comment'
# Verify that the passed resource is in path and exists
function venvwrapper_verify_resource {
    typeset exe_path="$(command \which "$1" | (unset GREP_OPTIONS; command \grep -v "not found"))"
    if [ "$exe_path" = "" ]
    then
        echo "ERROR: venvwrapper could not find $1 in your path" >&2
        return 1
    fi
    if [ ! -e "$exe_path" ]
    then
        echo "ERROR: Found $1 in path as \"$exe_path\" but that does not exist" >&2
        return 1
    fi
    return 0
}
end_long_comment

# Verify that venv is installed and visible
function venvwrapper_verify_venv {
    # venvwrapper_verify_resource $VENVWRAPPER_VENV
    typeset cmd_output="$(eval $VENVWRAPPER_VENV -h)"
    return $?
}

: <<'end_long_comment'
function venvwrapper_verify_venv_clone {
    venvwrapper_verify_resource $VENVWRAPPER_VENV_CLONE
}
end_long_comment

# Verify that the requested environment exists
function venvwrapper_verify_workon_environment {
    typeset env_name="$1"
    if [ ! -d "$VENV_WORKON_HOME/$env_name" ]
    then
       echo "ERROR: Environment '$env_name' does not exist. Create it with 'mkvenv $env_name'." >&2
       return 1
    fi
    return 0
}

# Verify that the active environment exists
function venvwrapper_verify_active_environment {
    if [ ! -n "${VIRTUAL_ENV}" ] || [ ! -d "${VIRTUAL_ENV}" ]
    then
        echo "ERROR: no venv active, or active venv is missing" >&2
        return 1
    fi
    return 0
}

# Help text for mkvenv
function venvwrapper_mkvenv_help {
    echo "Usage: mkvenv [-a project_path] [-i package] [-r requirements_file] [venv options] env_name"
    echo
    echo " -a project_path"
    echo
    echo "    Provide a full path to a project directory to associate with"
    echo "    the new environment."
    echo
    echo " -i package"
    echo
    echo "    Install a package after the environment is created."
    echo "    This option may be repeated."
    echo
    echo " -r requirements_file"
    echo
    echo "    Provide a pip requirements file to install a base set of packages"
    echo "    into the new environment."
    echo;
    echo 'venv help:';
    echo;
    eval "$VENVWRAPPER_VENV" $@;
}

# Create a new environment, in the VENV_WORKON_HOME.
#
# Usage: mkvenv [options] ENVNAME
# (where the options are passed directly to venv)
#
#:help:mkvenv: Create a new venv in $VENV_WORKON_HOME
function mkvenv {
    typeset -a in_args
    typeset -a out_args
    typeset -i i
    typeset tst
    typeset a
    typeset envname
    typeset requirements
    typeset packages
    typeset interpreter
    typeset project

    in_args=( "$@" )

    if [ -n "$ZSH_VERSION" ]
    then
        i=1
        tst="-le"
    else
        i=0
        tst="-lt"
    fi


    while [ $i $tst $# ]
    do
        a="${in_args[$i]}"
        # echo "arg $i : $a"
        case "$a" in
            -a)
                i=$(( $i + 1 ))
                project="${in_args[$i]}"
                if [ ! -d "$project" ]
                then
                    echo "Cannot associate project with $project, it is not a directory" 1>&2
                    return 1
                fi
                project="$(venvwrapper_absolutepath ${project})";;
            -h|--help)
                venvwrapper_mkvenv_help $a;
                return;;
            -i)
                i=$(( $i + 1 ));
                packages="$packages ${in_args[$i]}";;
            -p|--python*)
                if echo "$a" | grep -q "="
                then
                    interpreter="$(echo "$a" | cut -f2 -d=)"
                else
                    i=$(( $i + 1 ))
                    interpreter="${in_args[$i]}"
                fi;;
            -r)
                i=$(( $i + 1 ));
                requirements="${in_args[$i]}";
                requirements="$(venvwrapper_expandpath "$requirements")";;
            *)
                if [ ${#out_args} -gt 0 ]
                then
                    out_args=( "${out_args[@]-}" "$a" )
                else
                    out_args=( "$a" )
                fi;;
        esac
        i=$(( $i + 1 ))
    done

    if [ ! -z $interpreter ]
    then
        out_args=( "--python=$interpreter" ${out_args[@]} )
    fi;

    set -- "${out_args[@]}"

    eval "envname=\$$#"
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_venv || return 1
    (
        [ -n "$ZSH_VERSION" ] && setopt SH_WORD_SPLIT
        venvwrapper_cd "$VENV_WORKON_HOME" &&
        eval "$VENVWRAPPER_VENV $VENVWRAPPER_VENV_ARGS $@" &&
        [ -d "$VENV_WORKON_HOME/$envname" ] && \
            venvwrapper_run_hook "pre_mkvenv" "$envname"
    )
    typeset RC=$?
    [ $RC -ne 0 ] && return $RC

    # If they passed a help option or got an error from venv,
    # the environment won't exist.  Use that to tell whether
    # we should switch to the environment and run the hook.
    [ ! -d "$VENV_WORKON_HOME/$envname" ] && return 0

    # If they gave us a project directory, set it up now
    # so the activate hooks can find it.
    if [ ! -z "$project" ]
    then
        setvenvproject "$VENV_WORKON_HOME/$envname" "$project"
        RC=$?
        [ $RC -ne 0 ] && return $RC
    fi

    # Now activate the new environment
    workonvenv "$envname"

    if [ ! -z "$requirements" ]
    then
        pip install -r "$requirements"
    fi

    for a in $packages
    do
        pip install $a
    done

    venvwrapper_run_hook "post_mkvenv"
}

#:help:rmvenv: Remove a venv
function rmvenv {
    venvwrapper_verify_workon_home || return 1
    if [ ${#@} = 0 ]
    then
        echo "Please specify an environment." >&2
        return 1
    fi

    # support to remove several environments
    typeset env_name
    # Must quote the parameters, as environments could have spaces in their names
    for env_name in "$@"
    do
        echo "Removing $env_name..."
        typeset env_dir="$VENV_WORKON_HOME/$env_name"
        if [ "$VIRTUAL_ENV" = "$env_dir" ]
        then
            echo "ERROR: You cannot remove the active environment ('$env_name')." >&2
            echo "Either switch to another environment, or run 'deactivate'." >&2
            return 1
        fi

        if [ ! -d "$env_dir" ]; then
            echo "Did not find environment $env_dir to remove." >&2
        fi

        # Move out of the current directory to one known to be
        # safe, in case we are inside the environment somewhere.
        typeset prior_dir="$(pwd)"
        venvwrapper_cd "$VENV_WORKON_HOME"

        venvwrapper_run_hook "pre_rmvenv" "$env_name"
        command \rm -rf "$env_dir"
        venvwrapper_run_hook "post_rmvenv" "$env_name"

        # If the directory we used to be in still exists, move back to it.
        if [ -d "$prior_dir" ]
        then
            venvwrapper_cd "$prior_dir"
        fi
    done
}

# List the available environments.
function venvwrapper_show_workon_options {
    venvwrapper_verify_workon_home || return 1
    # NOTE: DO NOT use ls or cd here because colorized versions spew control
    #       characters into the output list.
    # echo seems a little faster than find, even with -depth 3.
    # Note that this is a little tricky, as there may be spaces in the path.
    #
    # 1. Look for environments by finding the activate scripts.
    #    Use a subshell so we can suppress the message printed
    #    by zsh if the glob pattern fails to match any files.
    #    This yields a single, space-separated line containing all matches.
    # 2. Replace the trailing newline with a space, so every
    #    possible env has a space following it.
    # 3. Strip the bindir/activate script suffix, replacing it with
    #    a slash, as that is an illegal character in a directory name.
    #    This yields a slash-separated list of possible env names.
    # 4. Replace each slash with a newline to show the output one name per line.
    # 5. Eliminate any lines with * on them because that means there
    #    were no envs.
    (venvwrapper_cd "$VENV_WORKON_HOME" && echo */$VENVWRAPPER_ENV_BIN_DIR/activate) 2>/dev/null \
        | command \tr "\n" " " \
        | command \sed "s|/$VENVWRAPPER_ENV_BIN_DIR/activate |/|g" \
        | command \tr "/" "\n" \
        | command \sed "/^\s*$/d" \
        | (unset GREP_OPTIONS; command \egrep -v '^\*$') 2>/dev/null
}

function _lsvenv_usage {
    echo "lsvenv [-blh]"
    echo "  -b -- brief mode"
    echo "  -l -- long mode"
    echo "  -h -- this help message"
}

#:help:lsvenv: list venvs
function lsvenv {

    typeset long_mode=true
    if command -v "getopts" >/dev/null 2>&1
    then
        # Use getopts when possible
        OPTIND=1
        while getopts ":blh" opt "$@"
        do
            case "$opt" in
                l) long_mode=true;;
                b) long_mode=false;;
                h)  _lsvenv_usage;
                    return 1;;
                ?) echo "Invalid option: -$OPTARG" >&2;
                    _lsvenv_usage;
                    return 1;;
            esac
        done
    else
        # fallback on getopt for other shell
        typeset -a args
        args=($(getopt blh "$@"))
        if [ $? != 0 ]
        then
            _lsvenv_usage
            return 1
        fi
        for opt in $args
        do
            case "$opt" in
                -l) long_mode=true;;
                -b) long_mode=false;;
                -h) _lsvenv_usage;
                    return 1;;
            esac
        done
    fi

    if $long_mode
    then
        allvenv showvenv "$env_name"
    else
        venvwrapper_show_workon_options
    fi
}

#:help:showvenv: show details of a single venv
function showvenv {
    typeset env_name="$1"
    if [ -z "$env_name" ]
    then
        if [ -z "$VIRTUAL_ENV" ]
        then
            echo "showvenv [env]"
            return 1
        fi
        env_name=$(basename "$VIRTUAL_ENV")
    fi

    venvwrapper_run_hook "get_env_details" "$env_name"
    echo
}

# Show help for workon
function venvwrapper_workon_help {
    echo "Usage: workonvenv env_name"
    echo ""
    echo "           Deactivate any currently activated venv"
    echo "           and activate the named environment, triggering"
    echo "           any hooks in the process."
    echo ""
    echo "       workonvenv"
    echo ""
    echo "           Print a list of available environments."
    echo "           (See also lsvenv -b)"
    echo ""
    echo "       workonvenv (-h|--help)"
    echo ""
    echo "           Show this help message."
    echo ""
    echo "       workonvenv (-c|--cd) envname"
    echo ""
    echo "           After activating the environment, cd to the associated"
    echo "           project directory if it is set."
    echo ""
    echo "       workonvenv (-n|--no-cd) envname"
    echo ""
    echo "           After activating the environment, do not cd to the"
    echo "           associated project directory."
    echo ""
}

#:help:workon: list or change working venvs
function workonvenv {
    typeset -a in_args
    typeset -a out_args

    in_args=( "$@" )

    if [ -n "$ZSH_VERSION" ]
    then
        i=1
        tst="-le"
    else
        i=0
        tst="-lt"
    fi
    typeset cd_after_activate=$VENVWRAPPER_WORKON_CD
    while [ $i $tst $# ]
    do
        a="${in_args[$i]}"
        case "$a" in
            -h|--help)
                venvwrapper_workon_help;
                return 0;;
            -n|--no-cd)
                cd_after_activate=0;;
            -c|--cd)
                cd_after_activate=1;;
            *)
                if [ ${#out_args} -gt 0 ]
                then
                    out_args=( "${out_args[@]-}" "$a" )
                else
                    out_args=( "$a" )
                fi;;
        esac
        i=$(( $i + 1 ))
    done

    set -- "${out_args[@]}"

    typeset env_name="$1"
    if [ "$env_name" = "" ]
    then
        lsvenv -b
        return 1
    elif [ "$env_name" = "." ]
    then
        # The IFS default of breaking on whitespace causes issues if there
        # are spaces in the env_name, so change it.
        IFS='%'
        env_name="$(basename $(pwd))"
        unset IFS
    fi

    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_workon_environment "$env_name" || return 1

    activate="$VENV_WORKON_HOME/$env_name/$VENVWRAPPER_ENV_BIN_DIR/activate"
    if [ ! -f "$activate" ]
    then
        echo "ERROR: Environment '$VENV_WORKON_HOME/$env_name' does not contain an activate script." >&2
        return 1
    fi

    # Deactivate any current environment "destructively"
    # before switching so we use our override function,
    # if it exists, but make sure it's the deactivate function
    # we set up
    type deactivate >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        type deactivate | grep 'typeset env_postdeactivate_hook' >/dev/null 2>&1
        if [ $? -eq 0 ]
        then
            deactivate
            unset -f deactivate >/dev/null 2>&1
        fi
    fi

    venvwrapper_run_hook "pre_activate" "$env_name"

    source "$activate"

    # Save the deactivate function from venv under a different name
    venvwrapper_original_deactivate=`typeset -f deactivate | sed 's/deactivate/venv_deactivate/g'`
    eval "$venvwrapper_original_deactivate"
    unset -f deactivate >/dev/null 2>&1

    # Replace the deactivate() function with a wrapper.
    eval 'deactivate () {
        typeset env_postdeactivate_hook
        typeset old_env

        # Call the local hook before the global so we can undo
        # any settings made by the local postactivate first.
        venvwrapper_run_hook "pre_deactivate"

        env_postdeactivate_hook="$VIRTUAL_ENV/$VENVWRAPPER_ENV_BIN_DIR/postdeactivate"
        old_env=$(basename "$VIRTUAL_ENV")

        # Call the original function.
        venv_deactivate $1

        venvwrapper_run_hook "post_deactivate" "$old_env"

        if [ ! "$1" = "nondestructive" ]
        then
            # Remove this function
            unset -f venv_deactivate >/dev/null 2>&1
            unset -f deactivate >/dev/null 2>&1
        fi

    }'

    VENVWRAPPER_PROJECT_CD=$cd_after_activate venvwrapper_run_hook "post_activate"

    return 0
}

# Prints the Python version string for the current interpreter.
function venvwrapper_get_python_version {
    # Uses the Python from the venv rather than
    # VENVWRAPPER_PYTHON because we're trying to determine the
    # version installed there so we can build up the path to the
    # site-packages directory.
    "$VIRTUAL_ENV/$VENVWRAPPER_ENV_BIN_DIR/python" -V 2>&1 | cut -f2 -d' ' | cut -f-2 -d.
}

# Prints the path to the site-packages directory for the current environment.
function venvwrapper_get_site_packages_dir {
    "$VIRTUAL_ENV/$VENVWRAPPER_ENV_BIN_DIR/python" -c "import distutils.sysconfig; print(distutils.sysconfig.get_python_lib())"
}

# Path management for packages outside of the venv.
# Based on a contribution from James Bennett and Jannis Leidel.
#
# add2venv directory1 directory2 ...
#
# Adds the specified directories to the Python path for the
# currently-active venv. This will be done by placing the
# directory names in a path file named
# "venv_path_extensions.pth" inside the venv's
# site-packages directory; if this file does not exist, it will be
# created first.
#
#:help:add2venv: add directory to the import path
function add2venv {
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_active_environment || return 1

    site_packages="`venvwrapper_get_site_packages_dir`"

    if [ ! -d "${site_packages}" ]
    then
        echo "ERROR: currently-active venv does not appear to have a site-packages directory" >&2
        return 1
    fi

    # Prefix with _ to ensure we are loaded as early as possible,
    # and at least before easy_install.pth.
    path_file="$site_packages/_venv_path_extensions.pth"

    if [ "$*" = "" ]
    then
        echo "Usage: add2venv dir [dir ...]"
        if [ -f "$path_file" ]
        then
            echo
            echo "Existing paths:"
            cat "$path_file" | grep -v "^import"
        fi
        return 1
    fi

    remove=0
    if [ "$1" = "-d" ]
    then
        remove=1
        shift
    fi

    if [ ! -f "$path_file" ]
    then
        echo "import sys; sys.__plen = len(sys.path)" > "$path_file" || return 1
        echo "import sys; new=sys.path[sys.__plen:]; del sys.path[sys.__plen:]; p=getattr(sys,'__egginsert',0); sys.path[p:p]=new; sys.__egginsert = p+len(new)" >> "$path_file" || return 1
    fi

    for pydir in "$@"
    do
        absolute_path="$(venvwrapper_absolutepath "$pydir")"
        if [ "$absolute_path" != "$pydir" ]
        then
            echo "Warning: Converting \"$pydir\" to \"$absolute_path\"" 1>&2
        fi

        if [ $remove -eq 1 ]
        then
            sed -i.tmp "\:^$absolute_path$: d" "$path_file"
        else
            sed -i.tmp '1 a\
'"$absolute_path"'
' "$path_file"
        fi
        rm -f "${path_file}.tmp"
    done
    return 0
}

# Does a ``cd`` to the site-packages directory of the currently-active
# venv.
#:help:cdsitepackagesvenv: change to the site-packages directory
function cdsitepackagesvenv {
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_active_environment || return 1
    typeset site_packages="`venvwrapper_get_site_packages_dir`"
    venvwrapper_cd "$site_packages/$1"
}

# Does a ``cd`` to the root of the currently-active venv.
#:help:cdvenv: change to the $VIRTUAL_ENV directory
function cdvenv {
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_active_environment || return 1
    venvwrapper_cd "$VIRTUAL_ENV/$1"
}

# Shows the content of the site-packages directory of the currently-active
# venv
#:help:lssitepackagesvenv: list contents of the site-packages directory
function lssitepackagesvenv {
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_active_environment || return 1
    typeset site_packages="`venvwrapper_get_site_packages_dir`"
    ls $@ "$site_packages"

    path_file="$site_packages/_venv_path_extensions.pth"
    if [ -f "$path_file" ]
    then
        echo
        echo "_venv_path_extensions.pth:"
        cat "$path_file"
    fi
}

# Toggles the currently-active venv between having and not having
# access to the global site-packages.
#:help:toggleglobalsitepackagesvenv: turn access to global site-packages on/off
function toggleglobalsitepackagesvenv {
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_active_environment || return 1
    typeset no_global_site_packages_file="`venvwrapper_get_site_packages_dir`/../no-global-site-packages.txt"
    if [ -f $no_global_site_packages_file ]; then
        rm $no_global_site_packages_file
        [ "$1" = "-q" ] || echo "Enabled global site-packages"
    else
        touch $no_global_site_packages_file
        [ "$1" = "-q" ] || echo "Disabled global site-packages"
    fi
}

: <<'end_long_comment'
#:help:cpvenv: duplicate the named venv to make a new one
function cpvenv {
    venvwrapper_verify_workon_home || return 1
    #venvwrapper_verify_venv_clone || return 1

    typeset src_name="$1"
    typeset trg_name="$2"
    typeset src
    typeset trg

    # without a source there is nothing to do
    if [ "$src_name" = "" ]; then
        echo "Please provide a valid venv to copy."
        return 1
    else
        # see if it\'s already in workon
        if [ ! -e "$VENV_WORKON_HOME/$src_name" ]; then
            # so it's a venv we are importing
            # make sure we have a full path
            # and get the name
            src="$(venvwrapper_expandpath "$src_name")"
            # final verification
            if [ ! -e "$src" ]; then
                echo "Please provide a valid venv to copy."
                return 1
            fi
            src_name="$(basename "$src")"
        else
           src="$VENV_WORKON_HOME/$src_name"
        fi
    fi

    if [ "$trg_name" = "" ]; then
        # target not given, assume
        # same as source
        trg="$VENV_WORKON_HOME/$src_name"
        trg_name="$src_name"
    else
        trg="$VENV_WORKON_HOME/$trg_name"
    fi
    trg="$(venvwrapper_expandpath "$trg")"

    # validate trg does not already exist
    # catch copying venv in workon home
    # to workon home
    if [ -e "$trg" ]; then
        echo "$trg_name venv already exists."
        return 1
    fi

    echo "Copying $src_name as $trg_name..."
    (
        [ -n "$ZSH_VERSION" ] && setopt SH_WORD_SPLIT
        venvwrapper_cd "$VENV_WORKON_HOME" &&
        "$VENVWRAPPER_VENV_CLONE" "$src" "$trg"
        [ -d "$trg" ] &&
            venvwrapper_run_hook "pre_cpvenv" "$src" "$trg_name" &&
            venvwrapper_run_hook "pre_mkvenv" "$trg_name"
    )
    typeset RC=$?
    [ $RC -ne 0 ] && return $RC

    [ ! -d "$VENV_WORKON_HOME/$trg_name" ] && return 1

    # Now activate the new environment
    workonvenv "$trg_name"

    venvwrapper_run_hook "post_mkvenv"
    venvwrapper_run_hook "post_cpvenv"
}
end_long_comment

#
# venvwrapper project functions
#

# Verify that the VENV_PROJECT_HOME directory exists
function venvwrapper_verify_project_home {
    if [ -z "$VENV_PROJECT_HOME" ]
    then
        echo "ERROR: Set the VENV_PROJECT_HOME shell variable to the name of the directory where projects should be created." >&2
        return 1
    fi
    if [ ! -d "$VENV_PROJECT_HOME" ]
    then
        [ "$1" != "-q" ] && echo "ERROR: Project directory '$VENV_PROJECT_HOME' does not exist.  Create it or set VENV_PROJECT_HOME to an existing directory." >&2
        return 1
    fi
    return 0
}

# Given a venv directory and a project directory,
# set the venv up to be associated with the
# project
#:help:setvenvproject: associate a project directory with a venv
function setvenvproject {
    typeset venv="$1"
    typeset prj="$2"
    if [ -z "$venv" ]
    then
        venv="$VIRTUAL_ENV"
    fi
    if [ -z "$prj" ]
    then
        prj="$(pwd)"
    else
        prj=$(venvwrapper_absolutepath "${prj}")
    fi

    # If what we were given isn't a directory, see if it is under
    # $WORKON_HOME.
    if [ ! -d "$venv" ]
    then
        venv="$VENV_WORKON_HOME/$venv"
    fi
    if [ ! -d "$venv" ]
    then
        echo "No venv $(basename $venv)" 1>&2
        return 1
    fi

    # Make sure we have a valid project setting
    if [ ! -d "$prj" ]
    then
        echo "Cannot associate venv with \"$prj\", it is not a directory" 1>&2
        return 1
    fi

    echo "Setting project for $(basename $venv) to $prj"
    echo "$prj" > "$venv/$VENVWRAPPER_PROJECT_FILENAME"
}

# Show help for mkprojectvenv
function venvwrapper_mkproject_help {
    echo "Usage: mkprojectvenv [-f|--force] [-t template] [venv options] project_name"
    echo
    echo "-f, --force    Create the venv even if the project directory"
    echo "               already exists"
    echo
    echo "Multiple templates may be selected.  They are applied in the order"
    echo "specified on the command line."
    echo
    echo "mkvenv help:"
    echo
    mkvenv -h
    echo
    echo "Available project templates:"
    echo
    # eval "$VENVWRAPPER_PYTHON" -c 'from venvwrapper.hook_loader import main; main()' -l project.template
}

#:help:mkprojectvenv: create a new project directory and its associated venv
function mkprojectvenv {
    typeset -a in_args
    typeset -a out_args
    typeset -i i
    typeset tst
    typeset a
    typeset t
    typeset force
    typeset templates

    in_args=( "$@" )
    force=0

    if [ -n "$ZSH_VERSION" ]
    then
        i=1
        tst="-le"
    else
        i=0
        tst="-lt"
    fi
    while [ $i $tst $# ]
    do
        a="${in_args[$i]}"
        case "$a" in
            -h|--help)
                venvwrapper_mkproject_help;
                return;;
            -f|--force)
                force=1;;
            -t)
                i=$(( $i + 1 ));
                templates="$templates ${in_args[$i]}";;
            *)
                if [ ${#out_args} -gt 0 ]
                then
                    out_args=( "${out_args[@]-}" "$a" )
                else
                    out_args=( "$a" )
                fi;;
        esac
        i=$(( $i + 1 ))
    done

    set -- "${out_args[@]}"

    # echo "templates $templates"
    # echo "remainder $@"
    # return 0

    eval "typeset envname=\$$#"
    venvwrapper_verify_project_home || return 1

    if [ -d "$VENV_PROJECT_HOME/$envname" -a $force -eq 0 ]
    then
        echo "Project $envname already exists." >&2
        return 1
    fi

    mkvenv "$@" || return 1

    venvwrapper_cd "$VENV_PROJECT_HOME"

    venvwrapper_run_hook "project.pre_mkproject" $envname

    echo "Creating $VENV_PROJECT_HOME/$envname"
    mkdir -p "$VENV_PROJECT_HOME/$envname"
    setvenvproject "$VIRTUAL_ENV" "$VENV_PROJECT_HOME/$envname"

    venvwrapper_cd "$VENV_PROJECT_HOME/$envname"

    for t in $templates
    do
        echo
        echo "Applying template $t"
        # For some reason zsh insists on prefixing the template
        # names with a space, so strip them out before passing
        # the value to the hook loader.
        venvwrapper_run_hook --name $(echo $t | sed 's/^ //') "project.template" "$envname" "$VENV_PROJECT_HOME/$envname"
    done

    venvwrapper_run_hook "project.post_mkproject"
}

#:help:cdprojectvenv: change directory to the active project
function cdprojectvenv {
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_active_environment || return 1
    if [ -f "$VIRTUAL_ENV/$VENVWRAPPER_PROJECT_FILENAME" ]
    then
        typeset project_dir="$(cat "$VIRTUAL_ENV/$VENVWRAPPER_PROJECT_FILENAME")"
        if [ ! -z "$project_dir" ]
        then
            venvwrapper_cd "$project_dir"
        else
            echo "Project directory $project_dir does not exist" 1>&2
            return 1
        fi
    else
        echo "No project set in $VIRTUAL_ENV/$VENVWRAPPER_PROJECT_FILENAME" 1>&2
        return 1
    fi
    return 0
}

#
# Temporary venv
#
# Originally part of venvwrapper.tmpvenv plugin
#
#:help:mktmpvenv: create a temporary venv
function mktmpvenv {
    typeset tmpenvname
    typeset RC
    typeset -a in_args
    typeset -a out_args

    in_args=( "$@" )

    if [ -n "$ZSH_VERSION" ]
    then
        i=1
        tst="-le"
    else
        i=0
        tst="-lt"
    fi
    typeset cd_after_activate=$VENVWRAPPER_WORKON_CD
    while [ $i $tst $# ]
    do
        a="${in_args[$i]}"
        case "$a" in
            -n|--no-cd)
                cd_after_activate=0;;
            -c|--cd)
                cd_after_activate=1;;
            *)
                if [ ${#out_args} -gt 0 ]
                then
                    out_args=( "${out_args[@]-}" "$a" )
                else
                    out_args=( "$a" )
                fi;;
        esac
        i=$(( $i + 1 ))
    done

    set -- "${out_args[@]}"

    # Generate a unique temporary name
    tmpenvname=$("$VENVWRAPPER_PYTHON" -c 'import uuid,sys; sys.stdout.write(uuid.uuid4()+"\n")' 2>/dev/null)
    if [ -z "$tmpenvname" ]
    then
        # This python does not support uuid
        tmpenvname=$("$VENVWRAPPER_PYTHON" -c 'import random,sys; sys.stdout.write(hex(random.getrandbits(64))[2:-1]+"\n")' 2>/dev/null)
    fi
    tmpenvname="tmp-$tmpenvname"

    # Create the environment
    mkvenv "$@" "$tmpenvname"
    RC=$?
    if [ $RC -ne 0 ]
    then
        return $RC
    fi

    # Change working directory
    [ "$cd_after_activate" = "1" ] && cdvenv

    # Create the tmpvenv marker file
    echo "This is a temporary environment. It will be deleted when you run 'deactivate'." | tee "$VIRTUAL_ENV/README.tmpenv"

    # Update the postdeactivate script
    cat - >> "$VIRTUAL_ENV/$VENVWRAPPER_ENV_BIN_DIR/postdeactivate" <<EOF
if [ -f "$VIRTUAL_ENV/README.tmpenv" ]
then
    echo "Removing temporary environment:" $(basename "$VIRTUAL_ENV")
    rmvenv $(basename "$VIRTUAL_ENV")
fi
EOF
}

#
# Remove all installed packages from the env
#
#:help:wipevenv: remove all packages installed in the current venv
function wipevenv {
    venvwrapper_verify_workon_home || return 1
    venvwrapper_verify_active_environment || return 1

    typeset req_file="$(venvwrapper_tempfile "requirements.txt")"
    pip freeze | egrep -v '(distribute|wsgiref|appdirs|packaging|pyparsing|six)' > "$req_file"
    if [ -n "$(cat "$req_file")" ]
    then
        echo "Uninstalling packages:"
        cat "$req_file"
        echo
        pip uninstall -y $(cat "$req_file" | grep -v '^-f' | sed 's/>/=/g' | cut -f1 -d=)
    else
        echo "Nothing to remove."
    fi
    rm -f "$req_file"
}

#
# Run a command in each venv
#
#:help:allvenv: run a command in all venvs
function allvenv {
    venvwrapper_verify_workon_home || return 1
    typeset d

    # The IFS default of breaking on whitespace causes issues if there
    # are spaces in the env_name, so change it.
    IFS='%'
    venvwrapper_show_workon_options | while read d
    do
        [ ! -d "$VENV_WORKON_HOME/$d" ] && continue
        echo "$d"
        echo "$d" | sed 's/./=/g'
        # Activate the environment, but not with workon
        # because we don't want to trigger any hooks.
        (source "$VENV_WORKON_HOME/$d/$VENVWRAPPER_ENV_BIN_DIR/activate";
            venvwrapper_cd "$VIRTUAL_ENV";
            "$@")
        echo
    done
    unset IFS
}

#:help:venvwrapper: show this help message
function venvwrapper {
	cat <<EOF

venvwrapper is a set of extensions to Ian Bicking's venv
tool.  The extensions include wrappers for creating and deleting
virtual environments and otherwise managing your development workflow,
making it easier to work on more than one project at a time without
introducing conflicts in their dependencies.

For more information please refer to the documentation:

    http://virtualenvwrapper.readthedocs.org/en/latest/command_ref.html

Commands available:

EOF

    typeset helpmarker="#:help:"
    cat  "$VENVWRAPPER_SCRIPT" \
        | grep "^$helpmarker" \
        | sed -e "s/^$helpmarker/  /g" \
        | sort \
        | sed -e 's/$/\'$'\n/g'
}

#
# Invoke the initialization functions
#
venvwrapper_initialize
