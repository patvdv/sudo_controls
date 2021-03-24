#!/usr/bin/env ksh
#******************************************************************************
# @(#) manage_sudo.sh
#******************************************************************************
# @(#) Copyright (C) 2014 by KUDOS BVBA (info@kudos.be).  All rights reserved.
#
# This program is a free software; you can redistribute it and/or modify
# it under the same terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details
#******************************************************************************
#
# DOCUMENTATION (MAIN)
# -----------------------------------------------------------------------------
# @(#) MAIN: manage_sudo.sh
# DOES: performs basic functions for SUDO controls: update SUDOers files locally
#       or remote, validate SUDO syntax, distribute the SUDO fragment files.
# EXPECTS: (see --help for more options)
# REQUIRES: check_config(), check_logging(), check_params(), check_root_user(),
#           check_setup(), check_syntax(), count_fields(), die(), display_usage(),
#           distribute2host(), distribute2slave(), do_cleanup(), fix2host(),
#           fix2slave(), get_linux_name(), get_linux_version(), log(), logc(),
#           resolve_alias(), resolve_host(), resolve_targets(), sftp_file(),
#           start_ssh_agent(), stop_ssh_agent(), update2host(), update2slave(),
#           validate_syntax(), wait_for_children(), warn()
#           For other pre-requisites see the documentation in display_usage()
#
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

#******************************************************************************
# DATA structures
#******************************************************************************

# ------------------------- CONFIGURATION starts here -------------------------
# Below configuration values should not be changed. Use the GLOBAL_CONFIG_FILE
# or LOCAL_CONFIG_FILE instead

# define the version (YYYY-MM-DD)
typeset -r SCRIPT_VERSION="2021-03-24"
# name of the global configuration file (script)
typeset -r GLOBAL_CONFIG_FILE="manage_sudo.conf"
# name of the local configuration file (script)
typeset -r LOCAL_CONFIG_FILE="manage_ssh.conf.local"
# maxiumum depth of recursion for alias resolution
typeset -r MAX_RECURSION=5
# location of temporary working storage
typeset -r TMP_DIR="/var/tmp"
# ------------------------- CONFIGURATION ends here ---------------------------
# configuration file values
typeset SUDO_TRANSFER_USER=""
typeset SUDO_OWNER_GROUP=""
typeset SUDO_UPDATE_USER=""
typeset SUDO_UPDATE_OPTS=""
typeset SSH_KEYSCAN_BIN=""
typeset SSH_KEYSCAN_ARGS=""
typeset BACKUP_DIR=""
typeset LOCAL_DIR=""
typeset LOG_DIR=""
typeset REMOTE_DIR=""
typeset DO_SFTP_CHMOD=""
typeset SFTP_ARGS=""
typeset DO_SSH_AGENT=""
typeset SSH_ARGS=""
typeset SSH_PRIVATE_KEY=""
typeset VISUDO_BIN=""
typeset MAX_BACKGROUND_PROCS=""
# miscelleaneous
typeset PATH=${PATH}:/usr/bin:/usr/local/bin
typeset SCRIPT_NAME=$(basename "$0")
typeset SCRIPT_DIR=$(dirname "$0")
typeset LOG_FILE=""
typeset OS_NAME="$(uname -s)"
typeset HOST_NAME="$(hostname)"
typeset FRAGS_FILE=""
typeset FRAGS_DIR=""
typeset TARGETS_FILE=""
typeset DO_SLAVE=0
typeset FIX_CREATE=0
typeset CAN_DISCOVER_KEYS=0
typeset CAN_START_AGENT=1
typeset TMP_FILE="${TMP_DIR}/.${SCRIPT_NAME}.$$"
typeset TMP_RC_FILE="${TMP_DIR}/.${SCRIPT_NAME}.rc.$$"
# command-line parameters
typeset ARG_ACTION=0            # default is nothing
typeset ARG_ALIAS=""            # alias to resolve
typeset ARG_FIX_DIR=""          # location of SUDO controls directory
typeset ARG_FIX_USER=""         # user to own SUDO controls files
typeset ARG_LOG_DIR=""          # location of the log directory (~root etc)
typeset ARG_LOCAL_DIR=""        # location of the local SSH control files
typeset ARG_REMOTE_DIR=""       # location of the remote SSH control files
typeset ARG_TARGETS=""          # list of remote targets
typeset ARG_LOG=1               # logging is on by default
typeset ARG_VERBOSE=1           # STDOUT is on by default
typeset ARG_DEBUG=0             # debug is off by default


#******************************************************************************
# FUNCTION routines
#******************************************************************************

# -----------------------------------------------------------------------------
function check_config
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"

# SUDO_TRANSFER_USER
if [[ -z "${SUDO_TRANSFER_USER}" ]]
then
    SUDO_TRANSFER_USER="${LOGNAME}"
    if [[ -z "${SUDO_TRANSFER_USER}" ]]
    then
        print -u2 "ERROR: no value for the SUDO_TRANSFER_USER setting in the configuration file"
        exit 1
    fi
fi
# LOCAL_DIR
if [[ -z "${LOCAL_DIR}" ]]
then
    print -u2 "ERROR: no value for the LOCAL_DIR setting in the configuration file"
    exit 1
fi
# REMOTE_DIR
if [[ -z "${REMOTE_DIR}" ]]
then
    print -u2 "ERROR: no value for the REMOTE_DIR setting in the configuration file"
    exit 1
fi
# DO_SFTP_CHMOD
if [[ -z "${DO_SFTP_CHMOD}" ]]
then
    print -u2 "ERROR: no value for the DO_SFTP_CHMOD setting in the configuration file"
    exit 1
fi
# SUDO_UPDATE_USER
if [[ -z "${SUDO_UPDATE_USER}" ]]
then
    SUDO_UPDATE_USER="${LOGNAME}"
    if [[ -z "${SUDO_UPDATE_USER}" ]]
    then
        print -u2 "ERROR: no value for the SUDO_UPDATE_USER setting in the configuration file"
        exit 1
    fi
fi
# VISUDO_BIN
if [[ -z "${VISUDO_BIN}" ]]
then
    print -u2 "ERROR: no value for the VISUDO_BIN setting in the configuration file"
    exit 1
fi
# SSH_KEYSCAN_BIN
if [[ -z "${SSH_KEYSCAN_BIN}" ]]
then
    print -u2 "ERROR: no value for the SSH_KEYSCAN_BIN setting in the configuration file"
    exit 1
fi
# DO_SSH_AGENT
if [[ -z "${DO_SSH_AGENT}" ]]
then
    print -u2 "ERROR:no value for the DO_SSH_AGENT setting in the configuration file"
    exit 1
else
    if (( DO_SSH_AGENT > 0 )) && [[ -z "${SSH_PRIVATE_KEY}" ]]
    then
        print -u2 "ERROR:no value for the SSH_PRIVATE_KEY setting in the configuration file"
        exit 1
    fi
fi
# MAX_BACKGROUND_PROCS
if [[ -z "${MAX_BACKGROUND_PROCS}" ]]
then
    print -u2 "ERROR: no value for the MAX_BACKGROUND_PROCS setting in the configuration file"
    exit 1
fi
# BACKUP_DIR
if [[ -z "${BACKUP_DIR}" ]]
then
    print -u2 "ERROR: no value for the BACKUP_DIR setting in the configuration file"
    exit 1
fi

return 0
}

# -----------------------------------------------------------------------------
function check_logging
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"

if (( ARG_LOG > 0 ))
then
    if [[ ! -d "${LOG_DIR}" ]]
    then
        if [[ ! -w "${LOG_DIR}" ]]
        then
            # switch off logging intelligently when needed for permission problems
            # since this script may run with root/non-root actions
            print -u2 "ERROR: unable to write to the log directory at ${LOG_DIR}, disabling logging"
            ARG_LOG=0
        fi
    else
        if [[ ! -w "${LOG_FILE}" ]]
        then
            # switch off logging intelligently when needed for permission problems
            # since this script may run with root/non-root actions
            print -u2 "ERROR: unable to write to the log file at ${LOG_FILE}, disabling logging"
            ARG_LOG=0
        fi
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
function check_params
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"

# -- ALL
if (( ARG_ACTION < 1 || ARG_ACTION > 11 ))
then
    display_usage
    exit 0
fi
# --fix-local + --fix-dir
if (( ARG_ACTION == 5 ))
then
    if [[ -z "${ARG_FIX_DIR}" ]]
    then
        print -u2 "ERROR: you must specify a value for parameter '--fix-dir"
        exit 1
    else
        FIX_DIR="${ARG_FIX_DIR}"
    fi
    if [[ -z "${ARG_FIX_USER}" ]]
    then
        SUDO_FIX_USER="${LOGNAME}"
    else
        SUDO_FIX_USER="${ARG_FIX_USER}"
    fi
fi
# --local-dir
if [[ -n "${ARG_LOCAL_DIR}" ]]
then
    if [[ ! -d "${ARG_LOCAL_DIR}" ]] || [[ ! -r "${ARG_LOCAL_DIR}" ]]
    then
        print -u2 "ERROR: unable to read directory ${ARG_LOCAL_DIR}"
        exit 1
    else
        LOCAL_DIR="${ARG_LOCAL_DIR}"
    fi
fi
# --log-dir
[[ -z "${ARG_LOG_DIR}" ]] || LOG_DIR="${ARG_LOG_DIR}"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
# --remote-dir
if (( ARG_ACTION == 1 || ARG_ACTION == 2 ))
then
    if [[ -n "${ARG_REMOTE_DIR}" ]]
    then
        REMOTE_DIR="${ARG_REMOTE_DIR}"
    fi
fi
# --slave
if (( DO_SLAVE ))
then
    # requires a list of targets (=slave servers)
    [[ -n "${ARG_TARGETS}" ]] || {
        print -u2 "ERROR: you must specify a list of targets with the --slave option"
        exit 1
    }
fi
# --targets
if [[ -n "${ARG_TARGETS}" ]]
then
    : > "${TMP_FILE}"
    # write comma-separated target list to the temporary file
    print "${ARG_TARGETS}" | tr -s ',' '\n' | while read -r TARGET_HOST
    do
        print "${TARGET_HOST}" >>"${TMP_FILE}"
    done
fi
# --update + --fix-local + --resolve-alias
if (( ARG_ACTION == 4 || ARG_ACTION == 5 || ARG_ACTION == 11 ))
then
    if [[ -n "${ARG_TARGETS}" ]]
    then
        print -u2 "ERROR: you cannot specify '--targets' in this context"
        exit 1
    fi
fi
# --resolve-alias
if (( ARG_ACTION == 11 ))
then
    if [[ -z "${ARG_ALIAS}" ]]
    then
        print -u2 "ERROR: you must specify an alias with the '--resolve-alias' option"
        exit 1
    fi
fi
if (( ARG_ACTION < 11 ))
then
    if [[ -n "${ARG_ALIAS}" ]]
    then
        print -u2 "ERROR: you cannot specify '--alias' in this context"
        exit 1
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
function check_root_user
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset UID=""

# shellcheck disable=SC2046
(IFS='()'; set -- $(id); print "$2") | read -r UID
if [[ "${UID}" = "root" ]]
then
    return 0
else
    return 1
fi
}

# -----------------------------------------------------------------------------
function check_setup
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset FILE=""

# use added fall back for LOCAL_DIR (the default script directory)
[[ -d "${LOCAL_DIR}" ]] || LOCAL_DIR="${SCRIPT_DIR}"

# check for basic SUDO control files: grants/alias
for FILE in "${LOCAL_DIR}/grants" "${LOCAL_DIR}/alias"
do
    if [[ ! -r "${FILE}" ]]
    then
        print -u2 "ERROR: cannot read file ${FILE}"
        exit 1
    fi
done
# check for basic SUDO control file(s): targets (or $TMP_FILE)
if (( ARG_ACTION == 1 || ARG_ACTION == 2 || ARG_ACTION == 6 || ARG_ACTION == 10 ))
then
    if [[ -z "${ARG_TARGETS}" ]]
    then
        TARGETS_FILE="${LOCAL_DIR}/targets"
        if [[ ! -r "${TARGETS_FILE}" ]]
        then
            print -u2 "ERROR: cannot read file ${TARGETS_FILE}"
            print -u2 "ERROR: possibly this is not a master or slave server"
            exit 1
        fi
    else
        TARGETS_FILE=${TMP_FILE}
    fi
fi
# check for basic SUDO control file(s): fragments, fragments.d/*
if [[ -d "${LOCAL_DIR}/fragments.d" && -f "${LOCAL_DIR}/fragments" ]]
then
    print -u2 "WARN: found both a 'fragments' file (${LOCAL_DIR}/fragments) and a 'fragments.d' directory (${LOCAL_DIR}/fragments.d). Ignoring the 'fragments' file"
fi
if [[ -d "${LOCAL_DIR}/fragments.d" ]]
then
    FRAGS_DIR="${LOCAL_DIR}/fragments.d"
    if [[ ! -r "${FRAGS_DIR}" ]]
    then
        print -u2 "ERROR: unable to read directory ${FRAGS_DIR}"
        exit 1
    fi
elif [[ -f "${LOCAL_DIR}/fragments" ]]
then
    FRAGS_FILE="${LOCAL_DIR}/fragments"
    if [[ ! -r "${FRAGS_FILE}" ]]
    then
        print -u2 "ERROR: cannot read file ${FRAGS_FILE}"
        exit 1
    fi
else
    print -u2 "ERROR: could not found any SUDO fragment files in ${LOCAL_DIR}!"
    exit 1
fi
# check for SUDO control scripts & configurations (not .local)
if (( ARG_ACTION == 1 || ARG_ACTION == 2 || ARG_ACTION == 4 ))
then
    for FILE in "${LOCAL_DIR}/update_sudo.pl" \
                "${LOCAL_DIR}/update_sudo.conf" \
                "${SCRIPT_DIR}/${SCRIPT_NAME}" \
                "${SCRIPT_DIR}/${GLOBAL_CONFIG_FILE}"
    do
        if [[ ! -r "${FILE}" ]]
        then
            print -u2 "ERROR: cannot read file ${FILE}"
            exit 1
        fi
    done
fi
# check if 'visudo' exists
if [[ ! -x "${VISUDO_BIN}" ]]
then
    print -u2 "WARN: 'visudo' tool not found, syntax checking is not available"
    CAN_CHECK_SYNTAX=0
fi
# check if 'ssh-keyscan' exists
if [[ ! -x "${SSH_KEYSCAN_BIN}" ]]
then
    print -u2 "WARN: 'ssh-keyscan' tool not found, host key discovery is not possible"
    CAN_DISCOVER_KEYS=0
fi
# check for SSH agent pre-requisites
if (( DO_SSH_AGENT ))
then
    # ssh-agent
    which ssh-agent >/dev/null 2>/dev/null
    # shellcheck disable=SC2181
    if (( $? > 0 ))
    then
        print -u2 "WARN: ssh-agent not available on ${HOST_NAME}"
        CAN_START_AGENT=0
    fi
    # private key
    if [[ ! -r "${SSH_PRIVATE_KEY}" ]]
    then
        print -u2 "WARN: SSH private key not found ${SSH_PRIVATE_KEY}, ssh-agent disabled"
        CAN_START_AGENT=0
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
function check_syntax
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset GRANTS_LINE=""
typeset GRANTS_FIELDS=""
typeset ALIASES_LINE=""
typeset ALIAS_FIELDS=""
typeset ALIAS=""
typeset CHECK_ALIAS=""

# grants should have 2 fields
grep -v -E -e '^#|^$' "${LOCAL_DIR}/grants" 2>/dev/null | while read -r GRANTS_LINE
do
    GRANTS_FIELDS=$(count_fields "${GRANTS_LINE}" ":")
    (( GRANTS_FIELDS != 2 )) && die "line '${GRANTS_LINE}' in grants file has missing or too many field(s) (should be 2)"
done

# alias should have 2 fields
grep -v -E -e '^#|^$' "${LOCAL_DIR}/alias" 2>/dev/null | while read -r ALIAS_LINE
do
    ALIAS_FIELDS=$(count_fields "${ALIAS_LINE}" ":")
    (( ALIAS_FIELDS != 2 )) && die "line '${ALIAS_LINE}' in alias file has missing or too many field(s) (should be 2)"
done

# resolve aliases in grants
awk 'BEGIN { needle="@[a-zA-Z0-9_-]+" }
        {
            if ($0 ~ /^#/) { next; }
            while (match($0, needle)) {
                print substr ($0, RSTART, RLENGTH);
                $0 = substr ($0, RSTART + RLENGTH);
        }
    }' "${LOCAL_DIR}/grants" 2>/dev/null | sort -u 2>/dev/null |\
while read -r ALIAS
do
    CHECK_ALIAS=$(resolve_alias "${ALIAS}" 0)
    if [[ -z "${CHECK_ALIAS}" ]] || (( RC > 0 ))
    then
        die "unable to resolve alias ${ALIAS} in the grants file"
    fi
done

# resolve aliases in alias
awk 'BEGIN { needle="@[a-zA-Z0-9_-]+" }
        {
            if ($0 ~ /^#/) { next; }
            while (match($0, needle)) {
                print substr ($0, RSTART, RLENGTH);
                $0 = substr ($0, RSTART + RLENGTH);
        }
    }' "${LOCAL_DIR}/alias" 2>/dev/null | sort -u 2>/dev/null |\
while read -r ALIAS
do
    CHECK_ALIAS=$(resolve_alias "${ALIAS}" 0)
    if [[ -z "${CHECK_ALIAS}" ]] || (( RC > 0 ))
    then
        die "unable to resolve alias ${ALIAS} in the alias file"
    fi
done

return 0
}

# -----------------------------------------------------------------------------
function count_fields
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset CHECK_LINE="$1"
typeset CHECK_DELIM="$2"
typeset NUM_FIELDS=0

case "${OS_NAME}" in
    HP-UX)
        # wark around old awk's limit on input of max 3000 bytes
        NUM_FIELDS=$(print "${CHECK_LINE}" | tr "${CHECK_DELIM}" '\n' 2>/dev/null | wc -l 2>/dev/null)
        ;;
    *)
        NUM_FIELDS=$(print "${CHECK_LINE}" | awk -F "${CHECK_DELIM}" '{ print NF }' 2>/dev/null)
        ;;
esac

print "${NUM_FIELDS}"

return 0
}

# -----------------------------------------------------------------------------
function die
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset NOW="$(date '+%d-%h-%Y %H:%M:%S')"
typeset LOG_LINE=""
typeset LOG_SIGIL=""

if [[ -n "$1" ]]
then
    if (( ARG_LOG > 0 ))
    then
        print - "$*" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*)
                    LOG_LINE="${LOG_LINE#INFO: *}"
                    LOG_SIGIL="INFO"
                    ;;
                WARN:*)
                    LOG_LINE="${LOG_LINE#WARN: *}"
                    LOG_SIGIL="WARN"
                    ;;
                ERROR:*)
                    LOG_LINE="${LOG_LINE#ERROR: *}"
                    LOG_SIGIL="ERROR"
                    ;;
                *)
                    LOG_SIGIL="ERROR"
                    ;;
            esac
            print "${NOW}: ${LOG_SIGIL}: [$$]:" "${LOG_LINE}" >>"${LOG_FILE}"
        done
    fi
    print - "$*" | while read -r LOG_LINE
    do
        # check for leading log sigils and retain them
        case "${LOG_LINE}" in
            INFO:*|WARN:*|ERROR*)
                print "${LOG_LINE}"
                ;;
            *)
                print "ERROR:" "${LOG_LINE}"
                ;;
        esac
    done
fi

exit 1
}

# -----------------------------------------------------------------------------
function display_usage
{
cat << EOT

**** ${SCRIPT_NAME} ****
**** (c) KUDOS BVBA - Patrick Van der Veken ****

Performs basic functions for SUDO controls: update SUDOers files locally or
remote, validate SUDO syntax or copy/distribute the SUDO controls files

Syntax: ${SCRIPT_DIR}/${SCRIPT_NAME} [--help] | (--backup | --check-syntax | --check-sudo | --preview-global | --update) |
            (--apply [--slave] [--remote-dir=<remote_directory>] [--targets=<host1>,<host2>,...]) |
                ((--copy|--distribute) [--slave] [--remote-dir=<remote_directory> [--targets=<host1>,<host2>,...]]) |
                    (--discover [--targets=<host1>,<host2>,...]) | (--resolve-alias --alias=<alias_name>)
                        ([--fix-local --fix-dir=<repository_dir> [--fix-user=<unix_account>] [--create-dir]] | [--fix-remote [--slave] [--create-dir] [--targets=<host1>,<host2>,...]])
                            [--local-dir=<local_directory>] [--no-log] [--log-dir=<log_directory>] [--debug]

Parameters:

--alias             : name of the alias to process
--apply|-a          : apply SUDO controls remotely (~targets)
--backup|-b         : create a backup of the SUDO controls repository (SUDO master)
--check-syntax|-s   : do basic syntax checking on SUDO controls configuration
                      (grants & alias files)
--check-sudo        : validate the SUDO fragments in the holding directory
--copy|-c           : copy SUDO control files to remote host (~targets)
--create-dir        : also create missing directories when fixing the SUDO controls
                      repository (see also --fix-local/--fix-remote)
--debug             : print extra status messages on STDERR
--discover|-d       : discover SSH host keys (STDOUT)
--distribute        : same as --copy
--fix-dir           : location of the local SUDO controls client repository
--fix-local         : fix permissions on the local SUDO controls repository
                      (local SUDO controls repository given by --fix-dir)
--fix-remote        : fix permissions on the remote SUDO controls repository
--fix-user          : UNIX account to own SUDO controls files [default: current user]
--help|-h           : this help text
--local-dir         : location of the SUDO control files on the local filesystem.
                      [default: see LOCAL_DIR setting]
--log-dir           : specify a log directory location.
--no-log            : do not log any messages to the script log file.
--preview-global|-p : dump the global grants namespace (after alias resolution)
--remote-dir        : directory where SUDO control files are/should be
                      located/copied on/to the target host
                      [default: see REMOTE_DIR setting]
--resolve-alias|-r  : resolve an alias into its individual components
--slave             : perform actions in master->slave mode
--targets           : comma-separated list of target hosts or @groups to operate on.
                      Overrides hosts/@groups contained in the 'targets' file.
--update|-u         : apply SUDO controls locally
--version|-V        : show the script version/release/fix

Note 1: copy and apply actions are run in parallel across a maximum of clients
        at the same time [default: see MAX_BACKGROUND_PROCS setting]

Note 2: for fix and apply actions: make sure correct 'sudo' rules are setup
        on the target systems to allow the SSH controls script to run with
        elevated privileges.

Note 3: only GLOBAL configuration files will be distributed to target hosts.

EOT

return 0
}

# -----------------------------------------------------------------------------
# distribute SUDO controls to a single host/client
function distribute2host
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset SERVER="$1"
typeset ERROR_COUNT=0
typeset FILE=""
typeset COPY_RC=0
typeset TMP_WORK_DIR=""

# convert line to hostname
SERVER="${SERVER%%;*}"
resolve_host "${SERVER}"
# shellcheck disable=SC2181
if (( $? > 0 ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi

# specify copy objects as 'filename!permissions'
# 1) config files & scripts
for FILE in "${LOCAL_DIR}/grants!660" \
            "${LOCAL_DIR}/alias!660" \
            "${LOCAL_DIR}/update_sudo.pl!770" \
            "${LOCAL_DIR}/update_sudo.conf!660" \
            "${SCRIPT_DIR}/${SCRIPT_NAME}!770" \
            "${SCRIPT_DIR}/${GLOBAL_CONFIG_FILE}!660"
do
    # sftp transfer
    sftp_file "${FILE}" "${SERVER}"
    COPY_RC=$?
    if (( COPY_RC == 0 ))
    then
        log "transferred ${FILE%!*} to ${SERVER}:${REMOTE_DIR}"
    else
        warn "failed to transfer ${FILE%!*} to ${SERVER}:${REMOTE_DIR} [RC=${COPY_RC}]"
        ERROR_COUNT=$(( ERROR_COUNT + 1 ))
    fi
done
# 2) fragments files
# are fragments stored in a file or a directory?
if [[ -n "${FRAGS_DIR}" ]]
then
    TMP_WORK_DIR="${TMP_DIR}/$0.${RANDOM}"
    mkdir -p "${TMP_WORK_DIR}"
    # shellcheck disable=SC2181
    if (( $? > 0 ))
    then
        die "unable to create temporary directory ${TMP_WORK_DIR} for mangling of 'fragments' file"
    fi
    # merge fragments file(s) before copy (in a temporary location)
    merge_fragments "${TMP_WORK_DIR}"
    # shellcheck disable=SC2181
    if (( $? > 0 ))
    then
        die "failed to merge fragments into the temporary file ${TMP_MERGE_FILE}"
    fi
    # sftp transfer
    sftp_file "${TMP_MERGE_FILE}!640" "${SERVER}"
    COPY_RC=$?
    if (( COPY_RC == 0 ))
    then
        # shellcheck disable=SC2086
        log "transferred ${TMP_MERGE_FILE} to ${SERVER}:${REMOTE_DIR}"
    else
        warn "failed to transfer ${TMP_MERGE_FILE%!*} to ${SERVER}:${REMOTE_DIR} [RC=${COPY_RC}]"
        ERROR_COUNT=$(( ERROR_COUNT + 1 ))
    fi
    [[ -d "${TMP_WORK_DIR}" ]] && rm -rf "${TMP_WORK_DIR}" 2>/dev/null
else
    sftp_file "${FRAGS_FILE}!640" "${SERVER}"
    COPY_RC=$?
    if (( COPY_RC == 0 ))
    then
        log "transferred ${FRAGS_FILE} to ${SERVER}:${REMOTE_DIR}"
    else
        warn "failed to transfer ${FRAGS_FILE} to ${SERVER}:${REMOTE_DIR} [RC=${COPY_RC}]"
        ERROR_COUNT=$(( ERROR_COUNT + 1 ))
    fi
fi

return ${ERROR_COUNT}
}

# -----------------------------------------------------------------------------
# distribute SUDO controls to a single host in slave mode
function distribute2slave
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset SERVER="$1"
typeset DISTRIBUTE_OPTS=""
typeset RC=0

# convert line to hostname
SERVER="${SERVER%%;*}"
resolve_host "${SERVER}"
# shellcheck disable=SC2181
if (( $? > 0 ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi
# propagate the --debug flag
if (( ARG_DEBUG > 0 ))
then
    DISTRIBUTE_OPTS="${DISTRIBUTE_OPTS} --debug"
fi

log "copying SUDO controls on ${SERVER} in slave mode, this may take a while ..."
# shellcheck disable=SC2029
( RC=0; ssh -A ${SSH_ARGS} "${SERVER}" "${REMOTE_DIR}/${SCRIPT_NAME} --copy ${DISTRIBUTE_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
) 2>&1 | logc ""

# fetch return code from subshell
RC=$(< "${TMP_RC_FILE}")

# shellcheck disable=SC2086
return ${RC}
}

# -----------------------------------------------------------------------------
function do_cleanup
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
log "performing cleanup ..."

# remove temporary file(s)
[[ -f "${TMP_FILE}" ]] && rm -f "${TMP_FILE}" >/dev/null 2>&1
[[ -f "${TMP_MERGE_FILE}" ]] && rm -f "${TMP_MERGE_FILE}" >/dev/null 2>&1
[[ -f "${TMP_RC_FILE}" ]] && rm -f "${TMP_RC_FILE}" >/dev/null 2>&1
# temporary scan file (syntax check)
if (( CAN_REMOVE_TEMP > 0 ))
then
    [[ -f "${TMP_SCAN_FILE}" ]] && rm -f "${TMP_SCAN_FILE}" >/dev/null 2>&1
fi

log "*** finish of ${SCRIPT_NAME} [${CMD_LINE}] /$$@${HOST_NAME}/ ***"

return 0
}

# -----------------------------------------------------------------------------
# fix SUDO controls on a single host/client (permissions/ownerships)
# !! requires appropriate 'sudo' rules on remote client for privilege elevation
function fix2host
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset SERVER="$1"
typeset SERVER_DIR="$2"
typeset SERVER_USER="$3"
typeset FIX_OPTS=""
typeset RC=0

# convert line to hostname
SERVER="${SERVER%%;*}"
resolve_host "${SERVER}"
# shellcheck disable=SC2181
if (( $? > 0 ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi
# propagate the --create-dir flag
if (( FIX_CREATE > 0 ))
then
    FIX_OPTS="${FIX_OPTS} --create-dir"
fi
# propagate the --debug flag
if (( ARG_DEBUG > 0 ))
then
    FIX_OPTS="${FIX_OPTS} --debug"
fi

log "fixing SUDO controls on ${SERVER} ..."
if [[ -z "${SUDO_UPDATE_USER}" ]]
then
    # own user w/ sudo
    # shellcheck disable=SC2029
    ( RC=0; ssh ${SSH_ARGS} "${SERVER}" "sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --fix-local --fix-dir=${SERVER_DIR} --fix-user=${SERVER_USER} ${FIX_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
    ) 2>&1 | logc ""
elif [[ "${SUDO_UPDATE_USER}" != "root" ]]
then
    # other user w/ sudo
    # shellcheck disable=SC2029
    ( RC=0; ssh ${SSH_ARGS} "${SUDO_UPDATE_USER}@${SERVER}" "sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --fix-local --fix-dir=${SERVER_DIR} --fix-user=${SERVER_USER} ${FIX_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
    ) 2>&1 | logc ""
else
    # root user w/o sudo
    # shellcheck disable=SC2029
    ( RC=0; ssh ${SSH_ARGS} "root@${SERVER}" "${REMOTE_DIR}/${SCRIPT_NAME} --fix-local --fix-dir=${SERVER_DIR} --fix-user=root ${FIX_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
    ) 2>&1 | logc ""
fi

# fetch return code from subshell
RC=$(< "${TMP_RC_FILE}")

# shellcheck disable=SC2086
return ${RC}
}

# -----------------------------------------------------------------------------
# fix SUDO controls on a single host/client in slave mode (permissions/ownerships)
# !! requires appropriate 'sudo' rules on remote client for privilege elevation
function fix2slave
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset SERVER="$1"
typeset SERVER_DIR="$2"
typeset SERVER_USER="$3"
typeset FIX_OPTS=""
typeset RC=0

# convert line to hostname
SERVER="${SERVER%%;*}"
resolve_host "${SERVER}"
# shellcheck disable=SC2181
if (( $? > 0 ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi
# propagate the --create-dir flag
if (( FIX_CREATE > 0 ))
then
    FIX_OPTS="${FIX_OPTS} --create-dir"
fi
# propagate the --debug flag
if (( ARG_DEBUG > 0 ))
then
    FIX_OPTS="${FIX_OPTS} --debug"
fi

log "fixing SUDO controls on ${SERVER} in slave mode, this may take a while ..."
# shellcheck disable=SC2029
( RC=0; ssh -A ${SSH_ARGS} "${SERVER}" "${REMOTE_DIR}/${SCRIPT_NAME} --fix-remote --fix-dir=${SERVER_DIR} --fix-user=${SERVER_USER} ${FIX_OPTS}";
    print "$?" > "${TMP_RC_FILE}"; exit
) 2>&1 | logc ""

# fetch return code from subshell
RC=$(< "${TMP_RC_FILE}")

# shellcheck disable=SC2086
return ${RC}
}

# -----------------------------------------------------------------------------
function get_linux_name
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset LSB_NAME="$(lsb_release -is 2>/dev/null | cut -f2 -d':' 2>/dev/null)"

print "${LSB_NAME}"

return 0
}

# -----------------------------------------------------------------------------
function get_linux_version
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset LSB_VERSION
typeset RELEASE_STRING=""
typeset RHEL_VERSION=""

LSB_VERSION="$(lsb_release -rs 2>/dev/null | cut -f1 -d'.' 2>/dev/null)"

if [[ -z "${LSB_VERSION}" ]]
then
    RELEASE_STRING="$(grep -i 'release' /etc/redhat-release 2>/dev/null)"

    case "${RELEASE_STRING}" in
        *release\ 5*)
            RHEL_VERSION=5
            ;;
        *release\ 6*)
            RHEL_VERSION=6
            ;;
        *release\ 7*)
            RHEL_VERSION=7
            ;;
        *release\ 8*)
            RHEL_VERSION=7
            ;;
        *)
            RHEL_VERSION=""
            ;;
    esac
    print "${RHEL_VERSION}"
else
    print "${LSB_VERSION}"
fi

return 0
}

# -----------------------------------------------------------------------------
# log an INFO: message (via ARG).
function log
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset NOW="$(date '+%d-%h-%Y %H:%M:%S')"
typeset LOG_LINE=""
typeset LOG_SIGIL=""

# log an INFO: message (via ARG).
if [[ -n "$1" ]]
then
    if (( ARG_LOG > 0 ))
    then
        print - "$*" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*)
                    LOG_LINE="${LOG_LINE#INFO: *}"
                    LOG_SIGIL="INFO"
                    ;;
                WARN:*)
                    LOG_LINE="${LOG_LINE#WARN: *}"
                    LOG_SIGIL="WARN"
                    ;;
                ERROR:*)
                    LOG_LINE="${LOG_LINE#ERROR: *}"
                    LOG_SIGIL="ERROR"
                    ;;
                *)
                    LOG_SIGIL="INFO"
                    ;;
            esac
            print "${NOW}: ${LOG_SIGIL}: [$$]:" "${LOG_LINE}" >>"${LOG_FILE}"
        done
    fi
    if (( ARG_VERBOSE > 0 ))
    then
        print - "$*" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*|WARN:*|ERROR*)
                    print "${LOG_LINE}"
                    ;;
                *)
                    print "INFO:" "${LOG_LINE}"
                    ;;
            esac
        done
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
# log an INFO: message (via STDIN). Do not use when STDIN is still open
# shellcheck disable=SC2120
function logc
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset NOW="$(date '+%d-%h-%Y %H:%M:%S')"
typeset LOG_STDIN=""
typeset LOG_LINE=""
typeset LOG_SIGIL=""

# process STDIN (if any)
[[ ! -t 0 ]] && LOG_STDIN="$(cat)"
if [[ -n "${LOG_STDIN}" ]]
then
    if (( ARG_LOG > 0 ))
    then
        print - "${LOG_STDIN}" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*)
                    LOG_LINE="${LOG_LINE#INFO: *}"
                    LOG_SIGIL="INFO"
                    ;;
                WARN:*)
                    LOG_LINE="${LOG_LINE#WARN: *}"
                    LOG_SIGIL="WARN"
                    ;;
                ERROR:*)
                    LOG_LINE="${LOG_LINE#ERROR: *}"
                    LOG_SIGIL="ERROR"
                    ;;
                *)
                    LOG_SIGIL="INFO"
                    ;;
            esac
            print "${NOW}: ${LOG_SIGIL}: [$$]:" "${LOG_LINE}" >>"${LOG_FILE}"
        done
    fi
    if (( ARG_VERBOSE > 0 ))
    then
        print - "${LOG_STDIN}" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*|WARN:*|ERROR*)
                    print "${LOG_LINE}"
                    ;;
                *)
                    print "INFO:" "${LOG_LINE}"
                    ;;
            esac
        done
    fi
fi

# process ARG (if any)
if [[ -n "$1" ]]
then
    if (( ARG_LOG > 0 ))
    then
        print - "$*" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*)
                    LOG_LINE="${LOG_LINE#INFO: *}"
                    LOG_SIGIL="INFO"
                    ;;
                WARN:*)
                    LOG_LINE="${LOG_LINE#WARN: *}"
                    LOG_SIGIL="WARN"
                    ;;
                ERROR:*)
                    LOG_LINE="${LOG_LINE#ERROR: *}"
                    LOG_SIGIL="ERROR"
                    ;;
                *)
                    LOG_SIGIL="INFO"
                    ;;
            esac
            print "${NOW}: ${LOG_SIGIL}: [$$]:" "${LOG_LINE}" >>"${LOG_FILE}"
        done
    fi
    if (( ARG_VERBOSE > 0 ))
    then
        print - "$*" | while read -r LOG_LINE
        do
            case "${LOG_LINE}" in
                INFO:*|WARN:*|ERROR*)
                    print "${LOG_LINE}"
                    ;;
                *)
                    print "INFO:" "${LOG_LINE}"
                    ;;
            esac
        done
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
# resolve an alias
function resolve_alias
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset NEEDLE="$1"
typeset RECURSION_COUNT=$2
typeset ALIASES_LINE=""
typeset ALIAS_LIST=""
typeset ALIAS=""
typeset IS_ALIAS=0
typeset EXPANDED_ALIASES=""

# check MAX_RECURSION to avoid segmentation faults
if (( RECURSION_COUNT > MAX_RECURSION ))
then
    # don't scramble function output with warn(), only use for ARG_LOG
    # go back up in the recursion tree or exit resolution call
    print -u2 "WARN: resolving alias for ${NEEDLE} has exceeded a recursion depth of ${MAX_RECURSION}"
    ARG_VERBOSE=0 warn "resolving alias for ${NEEDLE} has exceeded a recursion depth of ${MAX_RECURSION}"
    return 1
fi

# get aliases from alias line
ALIASES_LINE=$(grep -E -e "^${NEEDLE}.*:" "${LOCAL_DIR}/alias" 2>/dev/null | cut -f2 -d':' 2>/dev/null)

if [[ -z "${ALIASES_LINE}" ]]
then
    # don't scramble function output with warn(), only use for ARG_LOG
    # go back up in the recursion tree or exit resolution call
    print -u2 "WARN: alias ${NEEDLE} does not resolve or is empty"
    ARG_VERBOSE=0 warn "alias ${NEEDLE} does not resolve or is empty"
    return 1
fi

# expand alias line into individual aliases
# do not use variable substition (>=ksh93) instead use the uglier while loop solution
# (hint: don't use a for loop as aliases may contain spaces!)
print "${ALIASES_LINE}"| while IFS=',' read -r ALIAS
do
    # recurse if the alias is a group
    IS_ALIAS=$(print "${ALIAS}" | grep -c -E -e '^\@' 2>/dev/null)
    if (( IS_ALIAS > 0 ))
    then
        RECURSION_COUNT=$(( RECURSION_COUNT + 1 ))
        EXPANDED_ALIASES=$(resolve_alias "${ALIAS}" ${RECURSION_COUNT})
        RECURSION_COUNT=$(( RECURSION_COUNT - 1 ))
        # shellcheck disable=SC2181
        if (( $? == 0 ))
        then
            if [[ -z "${ALIAS_LIST}" ]]
            then
            	ALIAS_LIST="${EXPANDED_ALIASES}"
            else
            	ALIAS_LIST="${ALIAS_LIST}\n${EXPANDED_ALIASES}"
            fi
        # if the recursion fails, return the current output list
        # and go back up into the recursion tree
        else
            print "${ALIAS_LIST}"
            return 1
        fi
    # if the alias is not a group, just add it to the output list
    else
        if [[ -z "${ALIAS_LIST}" ]]
        then
            ALIAS_LIST="${ALIAS}"
        else
            ALIAS_LIST="${ALIAS_LIST}\n${ALIAS}"
        fi
    fi
done

# sort final output and hand it back to the caller
print "${ALIAS_LIST}" | sort -u 2>/dev/null

return 0
}

# -----------------------------------------------------------------------------
# merge fragments into a temporary file
function merge_fragments
{
# initialize temporary working copy (need be different for each background job)
# do not use 'mktemp' here as we need a fixed file name
TMP_MERGE_FILE="$1/fragments"
: > "${TMP_MERGE_FILE}"
# shellcheck disable=SC2181
(( $? > 0 )) && die "unable to create temporary file for mangling of 'fragments' file"

log "fragments are stored in a DIRECTORY, first merging all fragments into ${TMP_MERGE_FILE}"
# merge fragments with '%%%<file_name>' headers
# shellcheck disable=SC2012
ls -1 "${FRAGS_DIR}"/* | while read -r FILE
do
    # header first, file base name without extension
    BASE_FILE="${FILE##*/}"
    print "%%%${BASE_FILE%%.*}" >>"${TMP_MERGE_FILE}"
    # content next
    cat "${FILE}" >>"${TMP_MERGE_FILE}"
done

# merge file should not be empty
[[ -s ${TMP_MERGE_FILE} ]] || return 1

return 0
}

# -----------------------------------------------------------------------------
# resolve a host (check)
function resolve_host
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
nslookup "$1" 2>/dev/null | grep -q -E -e 'Address:.*([0-9]{1,3}[\.]){3}[0-9]{1,3}' 2>/dev/null

return $?
}

# -----------------------------------------------------------------------------
# resolve targets (file)
function resolve_targets
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset TARGETS_LIST=""
typeset EXPANDED_TARGETS=""
typeset TARGET=""
typeset IS_TARGET=0

grep -v -E -e '^#' -e '^$' "${TARGETS_FILE}" 2>/dev/null | while read -r TARGET
do
    # resolve group target
    IS_TARGET=$(print "${TARGET}" | grep -c -E -e '^\@' 2>/dev/null)
    if (( IS_TARGET > 0 ))
    then
        EXPANDED_TARGETS=$(resolve_alias "${TARGET}" 0)
        # shellcheck disable=SC2181
        if (( $? == 0 ))
        then
            if [[ -z "${TARGETS_LIST}" ]]
            then
                TARGETS_LIST="${EXPANDED_TARGETS}"
            else
                TARGETS_LIST="${TARGETS_LIST}\n${EXPANDED_TARGETS}"
            fi
        fi
    # add individual target
    else
        if [[ -z "${TARGETS_LIST}" ]]
        then
            TARGETS_LIST="${TARGET}"
        else
            TARGETS_LIST="${TARGETS_LIST}\n${TARGET}"
        fi
    fi
done

# sort final output and hand it back to the caller
print "${TARGETS_LIST}" | grep -v '^$' 2>/dev/null | sort -u 2>/dev/null

# shellcheck disable=SC2086
return $0
}

# -----------------------------------------------------------------------------
# transfer a file using sftp
function sftp_file
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset TRANSFER_FILE="$1"
typeset TRANSFER_HOST="$2"
typeset TRANSFER_DIR=""
typeset TRANSFER_PERMS=""
typeset SOURCE_FILE=""
typeset OLD_PWD=""
typeset SFTP_RC=0

# find the local directory & permission bits
TRANSFER_DIR=$(dirname "${TRANSFER_FILE%%!*}")
TRANSFER_PERMS="${TRANSFER_FILE##*!}"
# cut out the permission bits and the directory path
TRANSFER_FILE="${TRANSFER_FILE%!*}"
SOURCE_FILE="${TRANSFER_FILE##*/}"
# shellcheck disable=SC2164
OLD_PWD=$(pwd)
cd "${TRANSFER_DIR}" || return 1

# transfer, (possibly) chmod the file to/on the target server (keep STDERR)
if (( DO_SFTP_CHMOD > 1 ))
then
    sftp ${SFTP_ARGS} "${SUDO_TRANSFER_USER}@${TRANSFER_HOST}" >/dev/null <<EOT
cd ${REMOTE_DIR}
put ${SOURCE_FILE}
chmod ${TRANSFER_PERMS} ${SOURCE_FILE}
EOT
    SFTP_RC=$?
else
    sftp ${SFTP_ARGS} "${SUDO_TRANSFER_USER}@${TRANSFER_HOST}" >/dev/null <<EOT
cd ${REMOTE_DIR}
put ${SOURCE_FILE}
EOT
    SFTP_RC=$?
fi

cd "${OLD_PWD}" || return 1

return ${SFTP_RC}
}

# -----------------------------------------------------------------------------
# start a SSH agent
function start_ssh_agent
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"

log "requested to start an SSH agent on ${HOST_NAME} ..."

# is there one still running, then we re-use it
if [[ -n "${SSH_AGENT_PID}" ]]
then
    log "SSH agent already running on ${HOST_NAME} with PID: ${SSH_AGENT_PID}"
else
    # start the SSH agent
    eval "$(ssh-agent)" >/dev/null 2>/dev/null

    if [[ -z "${SSH_AGENT_PID}" ]]
    then
        warn "unable to start SSH agent on ${HOST_NAME}"
        return 1
    else
        log "SSH agent started on ${HOST_NAME}:"
        # shellcheck disable=SC2086
        log "$(ps -fp ${SSH_AGENT_PID})"
    fi
fi

# add the private key
log "adding private key ${SSH_PRIVATE_KEY} to SSH agent on ${HOST_NAME} ..."
log "$(ssh-add ${SSH_PRIVATE_KEY} 2>&1)"
if (( $(ssh-add -l 2>/dev/null | wc -l 2>/dev/null) == 0 ))
then
    warn "unable to add SSH private key to SSH agent on ${HOST_NAME}"
    return 1
fi

return 0
}

# -----------------------------------------------------------------------------
function stop_ssh_agent
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"

# stop the SSH agent
log "stopping SSH agent (if needed) on ${HOST_NAME} ..."

if [[ -n "${SSH_AGENT_PID}" ]]
then
    # SIGTERM
    log "stopping (TERM) process on ${HOST_NAME} with PID: ${SSH_AGENT_PID}"
    # shellcheck disable=SC2086
    log "$(ps -fp ${SSH_AGENT_PID})"
    # shellcheck disable=SC2086
    kill -s TERM ${SSH_AGENT_PID}
    sleep 3

    # SIGKILL
    if (( $(pgrep -u "${USER}" ssh-agent | grep -c "${SSH_AGENT_PID}") ))
    then
        log "stopping (KILL) process on ${HOST_NAME} with PID: ${SSH_AGENT_PID}"
        # shellcheck disable=SC2086
        log "$(ps -fp ${SSH_AGENT_PID})"
        # shellcheck disable=SC2086
        kill -s kill ${SSH_AGENT_PID}
    fi
    sleep 3
else
    log "no SSH agent running on ${HOST_NAME}"
fi

# process check
if (( $(pgrep -u "${USER}" ssh-agent | grep -c "${SSH_AGENT_PID}" 2>/dev/null) ))
then
    warn "unable to stop running SSH agent on ${HOST_NAME} [PID=${SSH_AGENT_PID}]"
    return 1
fi

return 0
}

# -----------------------------------------------------------------------------
# update SUDO controls on a single host/client
# !! requires appropriate 'sudo' rules on remote client for privilege elevation
function update2host
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset SERVER="$1"
typeset UPDATE_OPTS=""
typeset RC=0

# convert line to hostname
SERVER="${SERVER%%;*}"
resolve_host "${SERVER}"
# shellcheck disable=SC2181
if (( $? > 0 ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi
# propagate the --debug flag
if (( ARG_DEBUG > 0 ))
then
    UPDATE_OPTS="${UPDATE_OPTS} --debug"
fi

log "setting SUDO controls on ${SERVER} ..."
if [[ -z "${SUDO_UPDATE_USER}" ]]
then
    # own user w/ sudo
    # shellcheck disable=SC2029
    ( RC=0; ssh ${SSH_ARGS} "${SERVER}" "sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --update ${UPDATE_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
    ) 2>&1 | logc ""
elif [[ "${SUDO_UPDATE_USER}" != "root" ]]
then
    # other user w/ sudo
    # shellcheck disable=SC2029
    ( RC=0; ssh ${SSH_ARGS} "${SUDO_UPDATE_USER}@${SERVER}" "sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --update ${UPDATE_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
    ) 2>&1 | logc ""
else
    # root user w/o sudo
    # shellcheck disable=SC2029
    ( RC=0; ssh ${SSH_ARGS} "root@${SERVER} ${REMOTE_DIR}/${SCRIPT_NAME} --update ${UPDATE_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
    ) 2>&1 | logc ""
fi

# fetch return code from subshell
RC=$(< "${TMP_RC_FILE}")

# shellcheck disable=SC2086
return ${RC}
}

# -----------------------------------------------------------------------------
# update SUDO controls on a single host/client in slave mode
function update2slave
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset SERVER="$1"
typeset UPDATE_OPTS=""
typeset RC=0

# convert line to hostname
SERVER="${SERVER%%;*}"
resolve_host "${SERVER}"
# shellcheck disable=SC2181
if (( $? > 0 ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi
# propagate the --debug flag
if (( ARG_DEBUG > 0 ))
then
    UPDATE_OPTS="${UPDATE_OPTS} --debug"
fi

log "applying SUDO controls on ${SERVER} in slave mode, this may take a while ..."
# shellcheck disable=SC2029
( RC=0; ssh -A ${SSH_ARGS} "${SERVER}" "${REMOTE_DIR}/${SCRIPT_NAME} --apply ${UPDATE_OPTS}";
      print "$?" > "${TMP_RC_FILE}"; exit
) 2>&1 | logc ""

# fetch return code from subshell
RC=$(< "${TMP_RC_FILE}")

# shellcheck disable=SC2086
return ${RC}
}

# -----------------------------------------------------------------------------
# wait for child processes to exit
function wait_for_children
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset WAIT_ERRORS=0
typeset PID=""
typeset RC=0

# 'endless' loop :-)
while :
do
    (( ARG_DEBUG > 0 )) && print -u2 "child processes remaining: $*"
    for PID in "$@"
    do
        shift
        # child is still alive?
        # shellcheck disable=SC2086
        if kill -0 ${PID} 2>/dev/null
        then
            (( ARG_DEBUG > 0 )) && print -u2 "DEBUG: ${PID} is still alive"
            set -- "$@" "${PID}"
        # wait for sigchild, catching child exit codes is unreliable because
        # the child might have already ended before we get here (caveat emptor)
        else
            # shellcheck disable=SC2086
            wait ${PID}
            RC=$?
            if (( RC > 0 ))
            then
                warn "child process ${PID} exited [RC=${RC}]"
                WAIT_ERRORS=$(( WAIT_ERRORS + 1 ))
            else
                log "child process ${PID} exited [RC=${RC}]"
            fi
        fi
    done
    # break loop if we have no child PIDs left
    (( $# > 0 )) || break
    sleep 1     # required to avoid race conditions
done

return ${WAIT_ERRORS}
}

# -----------------------------------------------------------------------------
function warn
{
(( ARG_DEBUG > 0 )) && set "${DEBUG_OPTS}"
typeset NOW="$(date '+%d-%h-%Y %H:%M:%S')"
typeset LOG_LINE=""
typeset LOG_SIGIL=""

if [[ -n "$1" ]]
then
    if (( ARG_LOG > 0 ))
    then
        print - "$*" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*)
                    LOG_LINE="${LOG_LINE#INFO: *}"
                    LOG_SIGIL="INFO"
                    ;;
                WARN:*)
                    LOG_LINE="${LOG_LINE#WARN: *}"
                    LOG_SIGIL="WARN"
                    ;;
                ERROR:*)
                    LOG_LINE="${LOG_LINE#ERROR: *}"
                    LOG_SIGIL="ERROR"
                    ;;
                *)
                    LOG_SIGIL="WARN"
                    ;;
            esac
            print "${NOW}: ${LOG_SIGIL}: [$$]:" "${LOG_LINE}" >>"${LOG_FILE}"
        done
    fi
    if (( ARG_VERBOSE > 0 ))
    then
        print - "$*" | while read -r LOG_LINE
        do
            # check for leading log sigils and retain them
            case "${LOG_LINE}" in
                INFO:*|WARN:*|ERROR*)
                    print "${LOG_LINE}"
                    ;;
                *)
                    print "WARN:" "${LOG_LINE}"
                    ;;
            esac
        done
    fi
fi

return 0
}


#******************************************************************************
# MAIN routine
#******************************************************************************

# parse arguments/parameters
CMD_LINE="$*"
for PARAMETER in ${CMD_LINE}
do
    case ${PARAMETER} in
        -a|-apply|--apply)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=1
            ;;
        -b|-backup|--backup)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=9
            ;;
        -c|-copy|--copy)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=2
            ;;
        -debug|--debug)
            ARG_DEBUG=1
            ;;
        -distribute|--distribute)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=2
            ;;
        -d|-discover|--discover)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=10
            ARG_LOG=0
            ARG_VERBOSE=0
            CAN_DISCOVER_KEYS=1
            ;;
        -p|--preview-global|-preview-global)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=7
            ;;
        -fix-local|--fix-local)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=5
            ;;
        -fix-remote|--fix-remote)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=6
            ;;
        -r|-resolve-alias|--resolve-alias)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=11
            ;;
        -s|-check-syntax|--check-syntax)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=8
            ;;
        -check-sudo|--check-sudo)
            (( ARG_ACTION )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=3
            ARG_LOG=0
            CAN_CHECK_SYNTAX=1
            CAN_REMOVE_TEMP=1
            ;;
        -u|-update|--update)
            (( ARG_ACTION > 0 )) && {
                print -u2 "ERROR: multiple actions specified"
                exit 1
            }
            ARG_ACTION=4
            ;;
        -alias=*)
            ARG_ALIAS="${PARAMETER#-alias=}"
            ;;
        --alias=*)
            ARG_ALIAS="${PARAMETER#--alias=}"
            ;;
        -create-dir|--create-dir)
            FIX_CREATE=1
            ;;
        -fix-dir=*)
            ARG_FIX_DIR="${PARAMETER#-fix-dir=}"
            ;;
        --fix-dir=*)
            ARG_FIX_DIR="${PARAMETER#--fix-dir=}"
            ;;
        -fix-user=*)
            ARG_FIX_USER="${PARAMETER#-fix-user=}"
            ;;
        --fix-user=*)
            ARG_FIX_USER="${PARAMETER#--fix-user=}"
            ;;
        -local-dir=*)
            ARG_LOCAL_DIR="${PARAMETER#-local-dir=}"
            ;;
        --local-dir=*)
            ARG_LOCAL_DIR="${PARAMETER#--local-dir=}"
            ;;
        -log-dir=*)
            ARG_LOG_DIR="${PARAMETER#-log-dir=}"
            ;;
        --log-dir=*)
            ARG_LOG_DIR="${PARAMETER#--log-dir=}"
            ;;
        -no-log|--no-log)
            ARG_LOG=0
            ;;
        -remote-dir=*)
            ARG_REMOTE_DIR="${PARAMETER#-remote-dir=}"
            ;;
        --remote-dir=*)
            ARG_REMOTE_DIR="${PARAMETER#--remote-dir=}"
            ;;
        -slave|--slave)
            DO_SLAVE=1
            ;;
        -targets=*)
            ARG_TARGETS="${PARAMETER#-targets=}"
            ;;
        --targets=*)
            ARG_TARGETS="${PARAMETER#--targets=}"
            ;;
        -V|-version|--version)
            print "INFO: $0: ${SCRIPT_VERSION}"
            exit 0
            ;;
        \? | -h | -help | --help)
            display_usage
            exit 0
            ;;
        *)
            display_usage
            exit 0
            ;;
    esac
done

# check for configuration files (local overrides local)
if [[ -r "${SCRIPT_DIR}/${GLOBAL_CONFIG_FILE}" || -r "${SCRIPT_DIR}/${LOCAL_CONFIG_FILE}" ]]
then
    if [[ -r "${SCRIPT_DIR}/${GLOBAL_CONFIG_FILE}" ]]
    then
        # shellcheck source=/dev/null
        . "${SCRIPT_DIR}/${GLOBAL_CONFIG_FILE}"
    fi
    if [[ -r "${SCRIPT_DIR}/${LOCAL_CONFIG_FILE}" ]]
    then
        # shellcheck source=/dev/null
        . "${SCRIPT_DIR}/${LOCAL_CONFIG_FILE}"
    fi
else
    print -u2 "ERROR: could not find global or local configuration file"
fi

# startup checks
check_params && check_config && check_setup && check_logging

# catch shell signals
trap 'do_cleanup; exit 0' 0
trap 'do_cleanup; exit 1' 1 2 3 15

# set debugging options
if (( ARG_DEBUG > 0 ))
then
    DEBUG_OPTS='-vx'
    set "${DEBUG_OPTS}"
fi

log "*** start of ${SCRIPT_NAME} [${CMD_LINE}] /$$@${HOST_NAME}/ ***"
(( ARG_LOG > 0 )) && log "logging takes places in ${LOG_FILE}"

log "runtime info: LOCAL_DIR is set to: ${LOCAL_DIR}"

case ${ARG_ACTION} in
    1)  # apply SUDO controls remotely
        log "ACTION: apply SUDO controls remotely"
        # check for root or non-root model
        if [[ "${SUDO_UPDATE_USER}" != "root" ]]
        then
            check_root_user && die "must NOT be run as user 'root'"
        fi

        # build clients list
        CLIENTS=$(resolve_targets)
        if [[ -z "${CLIENTS}" ]]
        then
            die "no targets to process"
        else
            # shellcheck disable=SC2086
            log "processing targets: $(print ${CLIENTS} | tr -s '\n' ' ' 2>/dev/null)"
        fi

        # start SSH agent (if needed)
        if (( DO_SSH_AGENT > 0 && CAN_START_AGENT > 0 ))
        then
            start_ssh_agent
            # shellcheck disable=SC2181
            if (( $? > 0 ))
            then
                die "problem with launching an SSH agent, bailing out"
            fi
        fi

        # set max updates in background
        COUNT=${MAX_BACKGROUND_PROCS}
        print "${CLIENTS}" | while read -r CLIENT
        do
            if (( DO_SLAVE > 0 ))
            then
                update2slave "${CLIENT}" &
            else
                update2host "${CLIENT}" &
            fi
            PID=$!
            log "updating ${CLIENT} in background [PID=${PID}] ..."
            # add PID to list of all child PIDs
            PIDS="${PIDS} ${PID}"
            COUNT=$(( COUNT - 1 ))
            if (( COUNT <= 0 ))
            then
                # wait until all background processes are completed
                # shellcheck disable=SC2086
                wait_for_children ${PIDS} || \
                    warn "$? background jobs (possibly) failed to complete correctly"
                PIDS=''
                # reset max updates in background
                COUNT=${MAX_BACKGROUND_PROCS}
            fi
        done
        # final wait for background processes to be finished completely
        # shellcheck disable=SC2086
        wait_for_children ${PIDS} || \
            warn "$? background jobs (possibly) failed to complete correctly"
        # stop SSH agent if needed
        (( DO_SSH_AGENT > 0 && CAN_START_AGENT > 0 )) && \
            stop_ssh_agent
        log "finished applying SUDO controls remotely"
        ;;
    2)  # copy/distribute SUDO controls
        log "ACTION: copy/distribute SUDO controls"
        # check for root or non-root model
        if [[ "${SUDO_UPDATE_USER}" != "root" ]]
        then
            check_root_user && die "must NOT be run as user 'root'"
        fi

        # build clients list
        CLIENTS=$(resolve_targets)
        if [[ -z "${CLIENTS}" ]]
        then
            die "no targets to process"
        else
            # shellcheck disable=SC2086
            log "processing targets: $(print ${CLIENTS} | tr -s '\n' ' ' 2>/dev/null)"
        fi

        # start SSH agent (if needed)
        if (( DO_SSH_AGENT > 0 && CAN_START_AGENT > 0 ))
        then
            start_ssh_agent
            # shellcheck disable=SC2181
            if (( $? > 0 ))
            then
                die "problem with launching an SSH agent, bailing out"
            fi
        fi

        # set max updates in background
        COUNT=${MAX_BACKGROUND_PROCS}
        print "${CLIENTS}" | while read -r CLIENT
        do
            if (( DO_SLAVE ))
            then
                distribute2slave "${CLIENT}" &
            else
                distribute2host "${CLIENT}" &
            fi
            PID=$!
            log "copying/distributing to ${CLIENT} in background [PID=${PID}] ..."
            # add PID to list of all child PIDs
            PIDS="${PIDS} ${PID}"
            COUNT=$(( COUNT - 1 ))
            if (( COUNT <= 0 ))
            then
                # wait until all background processes are completed
                # shellcheck disable=SC2086
                wait_for_children ${PIDS} || \
                    warn "$? background jobs (possibly) failed to complete correctly"
                PIDS=''
                # reset max updates in background
                COUNT=${MAX_BACKGROUND_PROCS}
            fi
        done
        # final wait for background processes to be finished completely
        # shellcheck disable=SC2086
        wait_for_children ${PIDS} || \
            warn "$? background jobs (possibly) failed to complete correctly"
        # stop SSH agent if needed
        (( DO_SSH_AGENT > 0 && CAN_START_AGENT > 0 )) && \
            stop_ssh_agent
        log "finished copying/distributing SUDO controls"
        ;;
    3)  # perform syntax checking
        log "ACTION: validating SUDO fragments"
        # are fragments stored in a file or a directory?
        if [[ -n "${FRAGS_DIR}" ]]
        then
            TMP_WORK_DIR="${TMP_DIR}/$0.${RANDOM}"
            mkdir -p "${TMP_WORK_DIR}"
            # shellcheck disable=SC2181
            if (( $? > 0 ))
            then
                die "unable to create temporary directory ${TMP_WORK_DIR} for mangling of 'fragments' file"
            fi
            merge_fragments "${TMP_WORK_DIR}"
        fi
        # remove '%%%' headers
        TMP_SCAN_FILE=$(mktemp)
        # shellcheck disable=SC2181
        (( $? > 0 )) && die "unable to create temporary file for validation of 'fragments' file(s)"
        if [[ -n "${FRAGS_DIR}" ]]
        then
            grep -v '^%%%' "${TMP_MERGE_FILE}" 2>/dev/null >"${TMP_SCAN_FILE}"
            [[ -d "${TMP_WORK_DIR}" ]] && rm -rf "${TMP_WORK_DIR}" 2>/dev/null
        else
            grep -v '^%%%' "${FRAGS_FILE}" 2>/dev/null >"${TMP_SCAN_FILE}"
        fi
        # run syntax check
        if (( CAN_CHECK_SYNTAX ))
        then
            # shellcheck disable=SC2086
            CHECK_RESULT="$(${VISUDO_BIN} -c -f ${TMP_SCAN_FILE} 2>/dev/null)"
            # shellcheck disable=SC2181
            if (( $? > 0 ))
            then
                warn "SUDO syntax check: FAILED: ${CHECK_RESULT})"
                CAN_REMOVE_TEMP=0
            else
                log "SUDO syntax check: PASSED"
            fi
        fi
        log "finished validating SUDO fragments"
        ;;
    4)  # apply SUDO controls locally (root user)
        log "ACTION: apply SUDO controls locally"
        ( RC=0; "${LOCAL_DIR}/update_sudo.pl" ${SUDO_UPDATE_OPTS};
          print "$?" > "${TMP_RC_FILE}"; exit
        ) 2>&1 | logc ""
        # fetch return code from subshell
        RC=$(< "${TMP_RC_FILE}")
        if (( RC > 0 ))
        then
            die "failed to apply SUDO controls locally [RC=${RC}]"
        else
            log "finished applying SUDO controls locally [RC=${RC}]"
        fi
        ;;
    5)  # fix directory structure/perms/ownerships
        log "ACTION: fix local SUDO controls repository"
        check_root_user || die "must be run as user 'root'"
        log "resetting ownerships to UNIX user ${SUDO_FIX_USER}"
        if [[ ${SUDO_FIX_USER} = "root" ]]
        then
            warn "!!! resetting ownerships to user root !!!"
        fi
        if (( FIX_CREATE > 0 ))
        then
            log "you requested to create directories (if needed)"
        else
            log "you requested NOT to create directories (if needed)"
        fi

        # check if the SUDO control repo is already there
        if (( FIX_CREATE > 0 )) && [[ ! -d "${FIX_DIR}" ]]
        then
            # create stub directories
            mkdir -p "${FIX_DIR}/holding" 2>/dev/null || \
                warn "failed to create directory ${FIX_DIR}/holding"
            mkdir -p "${FIX_DIR}/sudoers.d" 2>/dev/null || \
                warn "failed to create directory ${FIX_DIR}/sudoers.d"
        fi
        # fix permissions & ownerships
        if [[ -d "${FIX_DIR}" ]]
        then
            # updating default directories
            chmod 755 "${FIX_DIR}" 2>/dev/null && \
                chown root:sys "${FIX_DIR}" 2>/dev/null
            if [[ -d "${FIX_DIR}/holding" ]]
            then
                chmod 2775 "${FIX_DIR}/holding" 2>/dev/null && \
                    chown ${SUDO_FIX_USER}:${SUDO_OWNER_GROUP} "${FIX_DIR}/holding" 2>/dev/null
            fi
            if [[ -d "${FIX_DIR}/sudoers.d" ]]
            then
                case ${OS_NAME} in
                    *HP-UX*)
                        # sudo >v1.8
                        chmod 755 "${FIX_DIR}/sudoers.d" 2>/dev/null && \
                            chown bin:bin "${FIX_DIR}/sudoers.d" 2>/dev/null
                        ;;
                    *)
                        chmod 755 "${FIX_DIR}/sudoers.d" 2>/dev/null && \
                            chown root:sys "${FIX_DIR}/sudoers.d" 2>/dev/null
                        ;;
                esac
            fi
            # checking files (sudoers.d/* are fixed by update_sudo.pl)
            for FILE in grants alias fragments ${GLOBAL_CONFIG_FILE} update_sudo.conf
            do
                if [[ -f "${FIX_DIR}/holding/${FILE}" ]]
                then
                    chmod 660 "${FIX_DIR}/holding/${FILE}" 2>/dev/null && \
                        chown ${SUDO_FIX_USER}:${SUDO_OWNER_GROUP} "${FIX_DIR}/holding/${FILE}" 2>/dev/null
                fi
            done
            for FILE in manage_sudo.sh update_sudo.pl
            do
                if [[ -f "${FIX_DIR}/holding/${FILE}" ]]
                then
                    chmod 770 "${FIX_DIR}/holding/${FILE}" 2>/dev/null && \
                        chown ${SUDO_FIX_USER}:${SUDO_OWNER_GROUP} "${FIX_DIR}/holding/${FILE}" 2>/dev/null
                fi
            done
            # log file
            if [[ -f "${LOG_FILE}" ]]
            then
                chmod 664 "${LOG_FILE}" 2>/dev/null && \
                    chown ${SUDO_FIX_USER}:${SUDO_OWNER_GROUP} "${LOG_FILE}" 2>/dev/null
            fi
            # check for SELinux labels
            case ${OS_NAME} in
                *Linux*)
                    LINUX_NAME="$(get_linux_name)"
                    LINUX_VERSION="$(get_linux_version)"
                    case ${LINUX_NAME} in
                        *Centos*|*RHEL*)
                            case "$(getenforce 2>/dev/null)" in
                                *Permissive*|*Enforcing*)
                                    case "${LINUX_VERSION}" in
                                        5|6|7 )
                                            chcon -R -t etc_t "${FIX_DIR}/sudoers.d"
                                            ;;
                                    esac
                                    ;;
                                *Disabled*)
                                    :
                                    ;;
                            esac
                            ;;
                    esac
                    ;;
                *)
                    :
                    ;;
            esac
        else
            die "SUDO controls repository at ${FIX_DIR} does not exist?"
        fi
        log "finished applying fixes to the local SUDO control repository"
        ;;
    6)  # fix remote directory structure/perms/ownerships
        log "ACTION: fix remote SUDO controls repository"
        check_root_user && die "must NOT be run as user 'root'"
        # check for root or non-root model
        if [[ "${SUDO_UPDATE_USER}" != "root" ]]
        then
            check_root_user && die "must NOT be run as user 'root'"
        fi

        # derive SUDO controls repo from $REMOTE_DIR:
        # /etc/sudo_controls/holding -> /etc/sudo_controls
        FIX_DIR="$(print ${REMOTE_DIR%/*})"
        [[ -z "${FIX_DIR}" ]] && \
            die "could not determine SUDO controls repo path from \$REMOTE_DIR?"

        # build clients list
        CLIENTS=$(resolve_targets)
        if [[ -z "${CLIENTS}" ]]
        then
            die "no targets to process"
        else
            # shellcheck disable=SC2086
            log "processing targets: $(print ${CLIENTS} | tr -s '\n' ' ' 2>/dev/null)"
        fi

        # start SSH agent (if needed)
        if (( DO_SSH_AGENT > 0 && CAN_START_AGENT > 0 ))
        then
            start_ssh_agent
            # shellcheck disable=SC2181
            if (( $? > 0 ))
            then
                die "problem with launching an SSH agent, bailing out"
            fi
        fi

        # set max updates in background
        COUNT=${MAX_BACKGROUND_PROCS}
        print "${CLIENTS}" | while read -r CLIENT
        do
            if (( DO_SLAVE > 0 ))
            then
                fix2slave "${CLIENT}" "${FIX_DIR}" "${SUDO_UPDATE_USER}" &
            else
                fix2host "${CLIENT}" "${FIX_DIR}" "${SUDO_UPDATE_USER}" &
            fi
            PID=$!
            log "fixing SUDO controls on ${CLIENT} in background [PID=${PID}] ..."
            # add PID to list of all child PIDs
            PIDS="${PIDS} ${PID}"
            COUNT=$(( COUNT - 1 ))
            if (( COUNT <= 0 ))
            then
                # wait until all background processes are completed
                # shellcheck disable=SC2086
                wait_for_children ${PIDS} || \
                    warn "$? background jobs (possibly) failed to complete correctly"
                PIDS=''
                # reset max updates in background
                COUNT=${MAX_BACKGROUND_PROCS}
            fi
        done
        # final wait for background processes to be finished completely
        wait_for_children ${PIDS} || \
            warn "$? background jobs (possibly) failed to complete correctly"
        # stop SSH agent if needed
        (( DO_SSH_AGENT > 0 && CAN_START_AGENT > 0 )) && \
            stop_ssh_agent
        log "finished applying fixes to the remote SUDO control repository"
        ;;
    7)  # dump the configuration namespace
        log "ACTION: dumping the global grants namespace with resolved aliases ..."
        "${LOCAL_DIR}/update_sudo.pl" --preview --global
        log "finished dumping the global namespace"
        ;;
    8)  # check syntax of the grants/alias files
        log "ACTION: syntax-checking the configuration files ..."
        check_syntax
        log "finished syntax-checking the configuration files"
        ;;
    9)  # make backup copy of configuration & fragment files
        log "ACTION: backing up the current configuration & fragment files ..."
        if [[ -d ${BACKUP_DIR} ]]
        then
            TIMESTAMP="$(date '+%Y%m%d-%H%M')"
            BACKUP_TAR_FILE="${BACKUP_DIR}/backup_repo_${TIMESTAMP}.tar"
            if [[ -f ${BACKUP_TAR_FILE} ]] || [[ -f "${BACKUP_TAR_FILE}.gz" ]]
            then
                die "backup file ${BACKUP_TAR_FILE}(.gz) already exists"
            fi
            # fragments files
            if [[ -n "${FRAGS_DIR}" ]]
            then
                # shellcheck disable=SC2086
                log "$(tar -cvf ${BACKUP_TAR_FILE} ${FRAGS_DIR} 2>/dev/null)"
            else
                # shellcheck disable=SC2086
                log "$(tar -cvf ${BACKUP_TAR_FILE} ${FRAGS_FILE} 2>/dev/null)"
            fi
            # configuration files
            for FILE in "${LOCAL_DIR}/grants" "${LOCAL_DIR}/alias ${LOCAL_DIR}/targets"
            do
                # shellcheck disable=SC2086
                log "$(tar -rvf ${BACKUP_TAR_FILE} ${FILE} 2>/dev/null)"
            done
            # shellcheck disable=SC2086
            log "$(gzip ${BACKUP_TAR_FILE} 2>/dev/null)"
            # shellcheck disable=SC2086
            log "resulting backup file is: $(ls -1 ${BACKUP_TAR_FILE}* 2>/dev/null)"
        else
            die "could not find backup directory ${BACKUP_DIR}. Host is not an SUDO master?"
        fi
        log "finished backing up the current configuration & fragment files"
        ;;
    10) # gather SSH host keys
        log "ACTION: gathering SSH host keys ..."
        if (( CAN_DISCOVER_KEYS > 0 ))
        then
            CLIENTS=$(resolve_targets)
            if [[ -z "${CLIENTS}" ]]
            then
                die "no targets to process"
            else
                # shellcheck disable=SC2086
                log "processing targets: $(print ${CLIENTS} | tr -s '\n' ' ' 2>/dev/null)"
            fi
            print "${CLIENTS}" | ${SSH_KEYSCAN_BIN} ${SSH_KEYSCAN_ARGS} -f - 2>/dev/null
        fi
        log "finished gathering SSH host keys"
        ;;
    11) # resolve an alias
        log "ACTION: resolving alias ${ARG_ALIAS} ..."
        RESOLVE_ALIAS=$(resolve_alias "${ARG_ALIAS}" 0)
        # shellcheck disable=SC2181
        if (( $? > 0 )) && [[ -z "${RESOLVE_ALIAS}" ]]
        then
            die "alias ${ARG_ALIAS} did not resolve correctly"
        else
            # shellcheck disable=SC2086
            log "alias ${ARG_ALIAS} resolves to: $(print ${RESOLVE_ALIAS} | tr -s '\n' ' ' 2>/dev/null)"
        fi
        log "finished resolving alias"
        ;;
esac

exit 0

#******************************************************************************
# END of script
#******************************************************************************
