#!/usr/bin/env ksh
#******************************************************************************
# @(#) manage_sudo.sh
#******************************************************************************
# @(#) Copyright (C) 2014 by KUDOS BVBA <info@kudos.be>.  All rights reserved.
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
#       or remote, validate SUDO syntax, distribute the SUDO fragment files
# EXPECTS: (see --help for more options)
# REQUIRES: check_config(), check_logging(), check_params(), check_root_user(),
#           check_setup(), check_syntax(), count_fields(), die(), display_usage(), 
#           distribute2host(), do_cleanup(), fix2host(), log(), logc(), 
#           resolve_host(), sftp_file(), update2host(), validate_syntax(), 
#           wait_for_children(), warn()
#           For other pre-requisites see the documentation in display_usage()
#
# @(#) HISTORY:
# @(#) 2014-12-16: initial version (VRF 1.0.0) [Patrick Van der Veken]
# @(#) 2014-12-20: updated SELinux contexts (VRF 1.0.1) [Patrick Van der Veken]
# @(#) 2015-01-05: added backup feature, see --backup (VRF 1.1.0) [Patrick Van der Veken]
# @(#) 2015-01-19: updated display_usage() (VRF 1.1.1) [Patrick Van der Veken]
# @(#) 2015-02-02: allow fragments files to have extensions in merge_fragments()
#                  use 'sudo -n' (VRF 1.1.2) [Patrick Van der Veken]
# @(#) 2015-04-10: fix in --fix-local routine (VRF 1.1.3) [Patrick Van der Veken]
# @(#) 2015-08-18: moved essential configuration items of the script into a
# @(#)             separate configuration file (global/local), fix in 
# @(#)             wait_for_children (VRF 1.2.0) [Patrick Van der Veken]
# @(#) 2015-08-26: added DO_SFTP_CHMOD configuration parameter to avoid
# @(#)             setstat failures with sftp_file() when remote file
# @(#)             permissions do not allow (VRF 1.2.1) [Patrick Van der Veken]
# @(#) 2015-08-27: smmall fix in sftp_file() (VRF 1.2.2) [Patrick Van der Veken]
# @(#) 2015-08-28: check_config() update (VRF 1.2.3) [Patrick Van der Veken]
# @(#) 2015-09-04: fix in wait_for_children (VRF 1.2.4) [Patrick Van der Veken]
# @(#) 2015-09-06: proper error checking in fix2host(), update2host() by using
# @(#)             logc() (VRF 1.3.0) [Patrick Van der Veken
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

#******************************************************************************
# DATA structures
#******************************************************************************

# ------------------------- CONFIGURATION starts here -------------------------
# Below configuration values should not be changed. Use the GLOBAL_CONFIG_FILE
# or LOCAL_CONFIG_FILE instead

# define the V.R.F (version/release/fix)
MY_VRF="1.3.0"
# name of the global configuration file (script)
GLOBAL_CONFIG_FILE="manage_sudo.conf"
# name of the local configuration file (script)
LOCAL_CONFIG_FILE="manage_sudo.conf.local"
# location of temporary working storage
TMP_DIR="/var/tmp"
# ------------------------- CONFIGURATION ends here ---------------------------
# miscelleaneous
PATH=${PATH}:/usr/bin:/usr/local/bin
SCRIPT_NAME=$(basename $0)
SCRIPT_DIR=$(dirname $0)
OS_NAME="$(uname)"
FRAGS_FILE=""
FRAGS_DIR=""
TARGETS_FILE=""
FIX_CREATE=0
CAN_CHECK_SYNTAX=1
CAN_REMOVE_TEMP=1
TMP_FILE="${TMP_DIR}/.${SCRIPT_NAME}.$$"
TMP_RC_FILE="${TMP_DIR}/.${SCRIPT_NAME}.rc.$$"
# command-line parameters
ARG_ACTION=0            # default is nothing
ARG_FIX_DIR=""          # location of SUDO controls directory
ARG_LOG_DIR=""          # location of the log directory (~root etc)
ARG_LOCAL_DIR=""        # location of the local SUDO control files
ARG_REMOTE_DIR=""       # location of the remote SUDO control files
ARG_TARGETS=""          # list of remote targets
ARG_LOG=1               # logging is on by default
ARG_VERBOSE=1           # STDOUT is on by default
ARG_DEBUG=0             # debug is off by default


#******************************************************************************
# FUNCTION routines
#******************************************************************************

# -----------------------------------------------------------------------------
function check_config
{
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
    print -u2 "ERROR:no value for the DO_SFTP_CHMOD setting in the configuration file"
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
if (( ARG_LOG ))
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
# -- ALL
if (( ARG_ACTION < 1 || ARG_ACTION > 9 ))
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
fi
# --local-dir
if [[ -n "${ARG_LOCAL_DIR}" ]]
then
    if [ \( ! -d "${ARG_LOCAL_DIR}" \) -o \( ! -r "${ARG_LOCAL_DIR}" \) ]
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
# --targets
if [[ -n "${ARG_TARGETS}" ]]
then
    > ${TMP_FILE}
    # write comma-separated target list to the temporary file
    print "${ARG_TARGETS}" | tr -s ',' '\n' | while read TARGET_HOST
    do
        print ${TARGET_HOST} >>${TMP_FILE}
    done
fi
# --update + --fix-local
if (( ARG_ACTION == 4 || ARG_ACTION == 5 ))
then
    if [[ -n "${TARGETS}" ]]
    then
        print -u2 "ERROR: you cannot specify '--targets' in this context!"
        exit 1
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
function check_root_user
{
(IFS='()'; set -- $(id); print $2) | read UID
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
# check for basic SUDO control file(s): targets, /var/tmp/targets.$USER (or $TMP_FILE)
if (( ARG_ACTION == 1 || ARG_ACTION == 2 || ARG_ACTION == 6 ))
then
    if [[ -z "${ARG_TARGETS}" ]]
    then
        TARGETS_FILE="${LOCAL_DIR}/targets"
        if [ \( ! -r "${TARGETS_FILE}" \) -a \( ! -r "/var/tmp/targets.${USER}" \) ]
        then
            print -u2 "ERROR: cannot read file ${TARGETS_FILE} nor /var/tmp/targets.${USER}"
            exit 1    
        fi
        # override default targets file
        [[ -r "/var/tmp/targets.${USER}" ]] && TARGETS_FILE="/var/tmp/targets.${USER}"
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

return 0
}

# -----------------------------------------------------------------------------
function check_syntax
{
# grants should have 2 fields
cat "${LOCAL_DIR}/grants" | grep -v -E -e '^#|^$' | while read GRANTS_LINE
do
    GRANTS_FIELDS=$(count_fields "${GRANTS_LINE}" ":")
    (( GRANTS_FIELDS != 2 )) && die "line '${GRANTS_LINE}' in grants file has missing or too many field(s) (should be 2)"
done

# alias should have 2 fields
cat "${LOCAL_DIR}/alias" | grep -v -E -e '^#|^$' | while read ALIAS_LINE
do
    ALIAS_FIELDS=$(count_fields "${ALIAS_LINE}" ":")
    (( ALIAS_FIELDS != 2 )) && die "line '${ALIAS_LINE}' in alias file has missing or too many field(s) (should be 2)"
done

return 0
}

# -----------------------------------------------------------------------------
function count_fields
{
CHECK_LINE="$1"
CHECK_DELIM="$2"

NUM_FIELDS=$(print "${CHECK_LINE}" | awk -F "${CHECK_DELIM}" '{ print NF }')

print $NUM_FIELDS

return ${NUM_FIELDS}
}

# -----------------------------------------------------------------------------
function die
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"

if [[ -n "$1" ]]
then
    if (( ARG_LOG ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'ERROR:'
            LOG_LINE="${LOG_LINE#ERROR: *}"
            print "${NOW}: ERROR: [$$]:" "${LOG_LINE}" >>${LOG_FILE}
        done
    fi
    print - "$*" | while read LOG_LINE
    do
        # filter leading 'ERROR:'
        LOG_LINE="${LOG_LINE#ERROR: *}"
        print -u2 "ERROR:" "${LOG_LINE}"
    done
fi

# finish up work
do_cleanup

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
            (--apply [--remote-dir=<remote_directory>] [--targets=<host1>,<host2>,...]) |
                ((--copy|--distribute) [--remote-dir=<remote_directory> [--targets=<host1>,<host2>,...]]) |
                    ([--fix-local --fix-dir=<repository_dir> [--create-dir]] | [--fix-remote [--create-dir] [--targets=<host1>,<host2>,...]])
                        [--preview-global] [--local-dir=<local_directory>]
                            [--no-log] [--log-dir=<log_directory>] [--debug]

Parameters:

--apply|-a          : apply SUDO controls remotely (~targets)
--backup|-b         : create a backup of the SUDO controls repository (SUDO master)
--check-syntax|-s   : do basic syntax checking on SUDO controls configuration
                      (grants & alias files) 
--check-sudo        : validate the SUDO fragments in the holding directory
--copy|-c           : copy SUDO control files to remote host (~targets)
--create-dir        : also create missing directories when fixing the SUDO controls
                      repository (see also --fix-local/--fix-remote)
--debug             : print extra status messages on STDERR
--distribute|-d     : same as --copy
--fix-dir           : location of the local SUDO controls client repository
--fix-local         : fix permissions on the local SUDO controls repository
                      (local SUDO controls repository given by --fix-dir)
--fix-remote        : fix permissions on the remote SUDO controls repository
--help|-h           : this help text
--local-dir         : location of the SUDO control files on the local filesystem.
                      [default: ${LOCAL_DIR}]
--log-dir           : specify a log directory location.
--no-log            : do not log any messages to the script log file.
--preview-global|-p : dump the global grant namespace (after alias resolution)
--remote-dir        : directory where SUDO control files are/should be 
                      located/copied on/to the target host
                      [default: ${REMOTE_DIR}]
--targets           : comma-separated list of target hosts to operate on. Override the 
                      hosts contained in the 'targets' configuration file.
--update|-u         : apply SUDO controls locally
--version|-V        : show the script version/release/fix

Note 1: distribute and update actions are run in parallel across a maximum of
        ${MAX_BACKGROUND_PROCS} clients at the same time.

Note 2: make sure correct 'sudo' rules are setup on the target systems to allow
        the SUDO controls script to run with elevated privileges.

Note 3: only GLOBAL configuration files will be distributed to target hosts.

EOT

return 0
}

# -----------------------------------------------------------------------------
# distribute SUDO controls to a single host/client 
function distribute2host
{
SERVER="$1"
ERROR_COUNT=0
# convert line to hostname
SERVER=${SERVER%%;*}
resolve_host ${SERVER}
if (( $? ))
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
    sftp_file ${FILE} ${SERVER}
    COPY_RC=$?
    if (( ! COPY_RC ))
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
    mkdir -p ${TMP_WORK_DIR}
    if (( $? ))
    then
        die "unable to create temporary directory ${TMP_WORK_DIR} for mangling of 'fragments' file"
    fi
    # merge fragments file(s) before copy (in a temporary location)
    merge_fragments ${TMP_WORK_DIR}
    if (( $? ))
    then
        die "failed to merge fragments into the temporary file ${TMP_MERGE_FILE}"
    fi
    # sftp transfer
    sftp_file "${TMP_MERGE_FILE}!640" ${SERVER}
    COPY_RC=$?
    if (( ! COPY_RC ))
    then
        log "transferred ${TMP_MERGE_FILE} to ${SERVER}:${REMOTE_DIR}"
    else
        warn "failed to transfer ${TMP_MERGE_FILE%!*} to ${SERVER}:${REMOTE_DIR} [RC=${COPY_RC}]"
        ERROR_COUNT=$(( ERROR_COUNT + 1 ))
    fi
    [[ -d ${TMP_WORK_DIR} ]] && rm -rf ${TMP_WORK_DIR} 2>/dev/null
else
    sftp_file "${FRAGS_FILE}!640" ${SERVER}
    COPY_RC=$?
    if (( ! COPY_RC ))
    then
        log "transferred ${FRAGS_FILE} to ${SERVER}:${REMOTE_DIR}"
    else
        warn "failed to transfer ${FRAGS_FILE} to ${SERVER}:${REMOTE_DIR} [RC=${COPY_RC}]"
        ERROR_COUNT = $(( ERROR_COUNT + 1 ))
    fi
fi

return ${ERROR_COUNT}
}

# -----------------------------------------------------------------------------
function do_cleanup
{
log "performing cleanup ..."

# remove temporary file(s)
[[ -f ${TMP_FILE} ]] && rm -f ${TMP_FILE} >/dev/null 2>&1
[[ -f ${TMP_MERGE_FILE} ]] && rm -f ${TMP_MERGE_FILE} >/dev/null 2>&1
[[ -f ${TMP_RC_FILE} ]] && rm -f ${TMP_RC_FILE} >/dev/null 2>&1
# temporary scan file (syntax check)
if (( CAN_REMOVE_TEMP ))
then
    [[ -f ${TMP_SCAN_FILE} ]] && rm -f ${TMP_SCAN_FILE} >/dev/null 2>&1
fi
    
log "*** finish of ${SCRIPT_NAME} [${CMD_LINE}] ***"

return 0
}

# -----------------------------------------------------------------------------
# fix SUDO controls on a single host/client (permissions/ownerships)
# !! requires appropriate 'sudo' rules on remote client for privilege elevation
function fix2host
{
SERVER="$1"
SERVER_DIR="$2"

# convert line to hostname
SERVER=${SERVER%%;*}
resolve_host ${SERVER}
if (( $? ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi
        
log "fixing sudo controls on ${SERVER} ..."
if [[ -z "${SUDO_UPDATE_USER}" ]]
then
    # own user w/ sudo
    ( RC=0; ssh ${SSH_ARGS} ${SERVER} sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --fix-local --fix-dir=${SERVER_DIR};
      print "$?" > ${TMP_RC_FILE}; exit
    ) 2>&1 | logc
elif [[ "${SUDO_UPDATE_USER}" != "root" ]]
then
    # other user w/ sudo
    ( RC=0; ssh ${SSH_ARGS} ${SUDO_UPDATE_USER}@${SERVER} sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --fix-local --fix-dir=${SERVER_DIR};
      print "$?" > ${TMP_RC_FILE}; exit
    ) 2>&1 | logc
else
    # root user w/o sudo
    ( RC=0; ssh ${SSH_ARGS} root@${SERVER} ${REMOTE_DIR}/${SCRIPT_NAME} --fix-local --fix-dir=${SERVER_DIR};
      print "$?" > ${TMP_RC_FILE}; exit
    ) 2>&1 | logc
fi

# fetch return code from subshell
RC="$(< ${TMP_RC_FILE})"

return ${RC}
}

# -----------------------------------------------------------------------------
# log an INFO: message (via ARG).
function log
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"

# log an INFO: message (via ARG).
if [[ -n "$1" ]]
then
    if (( ARG_LOG ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "${NOW}: INFO: [$$]:" "${LOG_LINE}" >>${LOG_FILE}
        done
    fi
    if (( ARG_VERBOSE ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "INFO:" "${LOG_LINE}"
        done
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
# log an INFO: message (via STDIN). Do not use when STDIN is still open
function logc
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"
LOG_STDIN=""

# process STDIN (if any)
[[ ! -t 0 ]] && LOG_STDIN="$(cat)"
if [[ -n "${LOG_STDIN}" ]]
then
    if (( ARG_LOG ))
    then
        print - "${LOG_STDIN}" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "${NOW}: INFO: [$$]:" "${LOG_LINE}" >> ${LOG_FILE}
        done
    fi
    if (( ARG_VERBOSE ))
    then
        print - "${LOG_STDIN}" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "INFO:" "${LOG_LINE}"
        done
    fi
fi

# process ARG (if any)
if [[ -n "$1" ]]
then
    if (( ARG_LOG != 0 ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "${NOW}: INFO: [$$]:" "${LOG_LINE}" >> ${LOG_FILE}
        done
    fi
    if (( ARG_VERBOSE != 0 ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'INFO:'
            LOG_LINE="${LOG_LINE#INFO: *}"
            print "INFO:" "${LOG_LINE}"
        done
    fi
fi

return 0
}

# -----------------------------------------------------------------------------
# merge fragments into a temporary file
function merge_fragments
{
# initialize temporary working copy (need be different for each background job)
# do not use 'mktemp' here as we need a fixed file name
TMP_MERGE_FILE="$1/fragments"
> ${TMP_MERGE_FILE}
(( $? )) && die "unable to create temporary file for mangling of 'fragments' file"

log "fragments are stored in a DIRECTORY, first merging all fragments into ${TMP_MERGE_FILE}"
# merge fragments with '%%%<file_name>' headers
ls -1 ${FRAGS_DIR}/* | while read FILE
do
    # header first, file base name without extension
    BASE_FILE=${FILE##*/}
    print "%%%${BASE_FILE%%.*}" >>${TMP_MERGE_FILE}
    # content next
    cat ${FILE} >>${TMP_MERGE_FILE}
done

# merge file should not be empty
[[ -s ${TMP_MERGE_FILE} ]] || return 1

return 0
}

# -----------------------------------------------------------------------------
# resolve a host (check)
function resolve_host
{
LOOKUP_HOST="$1"

nslookup $1 2>/dev/null | grep -q -E -e 'Address:.*([0-9]{1,3}[\.]){3}[0-9]{1,3}'

return $?
}

# -----------------------------------------------------------------------------
# transfer a file using sftp
function sftp_file 
{
TRANSFER_FILE="$1"
TRANSFER_HOST="$2"

# find the local directory & permission bits
TRANSFER_DIR="${TRANSFER_FILE%/*}"
TRANSFER_PERMS="${TRANSFER_FILE##*!}"
# cut out the permission bits and the directory path
TRANSFER_FILE="${TRANSFER_FILE%!*}"
SOURCE_FILE="${TRANSFER_FILE##*/}"
OLD_PWD=$(pwd) && cd ${TRANSFER_DIR}

# transfer, (possibly) chmod the file to/on the target server (keep STDERR)
if (( DO_SFTP_CHMOD ))
then
    sftp ${SFTP_ARGS} ${SUDO_TRANSFER_USER}@${TRANSFER_HOST} >/dev/null <<EOT
cd ${REMOTE_DIR}
put ${SOURCE_FILE}
chmod ${TRANSFER_PERMS} ${SOURCE_FILE}
EOT
    SFTP_RC=$?
else
    sftp ${SFTP_ARGS} ${SUDO_TRANSFER_USER}@${TRANSFER_HOST} >/dev/null <<EOT
cd ${REMOTE_DIR}
put ${SOURCE_FILE}
EOT
    SFTP_RC=$?
fi

cd ${OLD_PWD}

return ${SFTP_RC}
}

# -----------------------------------------------------------------------------
# update SUDO controls on a single host/client 
# !! requires appropriate 'sudo' rules on remote client for privilege elevation
function update2host
{
SERVER="$1"

# convert line to hostname
SERVER=${SERVER%%;*}
resolve_host ${SERVER}
if (( $? ))
then
    warn "could not lookup host ${SERVER}, skipping"
    return 1
fi

log "setting sudo controls on ${SERVER} ..."
if [[ -z "${SUDO_UPDATE_USER}" ]]
then
    # own user w/ sudo
    ( RC=0; ssh ${SSH_ARGS} ${SERVER} sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --update;
      print "$?" > ${TMP_RC_FILE}; exit
    ) 2>&1 | logc
elif [[ "${SUDO_UPDATE_USER}" != "root" ]]
then
    # other user w/ sudo
    ( RC=0; ssh ${SSH_ARGS} ${SUDO_UPDATE_USER}@${SERVER} sudo -n ${REMOTE_DIR}/${SCRIPT_NAME} --update;
      print "$?" > ${TMP_RC_FILE}; exit
    ) 2>&1 | logc
else
    # root user w/o sudo
    ( RC=0; ssh ${SSH_ARGS} root@${SERVER} ${REMOTE_DIR}/${SCRIPT_NAME} --update;
      print "$?" > ${TMP_RC_FILE}; exit
    ) 2>&1 | logc
fi

# fetch return code from subshell
RC="$(< ${TMP_RC_FILE})"

return ${RC}
}

# -----------------------------------------------------------------------------
# wait for child processes to exit
function wait_for_children
{
WAIT_ERRORS=0

# 'endless' loop :-)
while :
do
    (( ARG_DEBUG )) && print -u2 "child processes remaining: $*"
    for PID in "$@"
    do
        shift
        # child is still alive?
        if $(kill -0 ${PID} 2>/dev/null)
        then
            (( ARG_DEBUG )) && print -u2 "DEBUG: ${PID} is still alive"
            set -- "$@" "${PID}"
        # wait for sigchild, catching child exit codes is unreliable because
        # the child might have already ended before we get here (caveat emptor)
        else
            wait ${PID}
            RC=$?
            if (( ${RC} ))
            then
                log "child process ${PID} exited [RC=${RC}]"
                WAIT_ERRORS=$(( WAIT_ERRORS + 1 ))
            else
                log "child process ${PID} exited [RC=${RC}]"
            fi
        fi
    done
    # break loop if we have no child PIDs left
    (($# > 0)) || break
    sleep 1     # required to avoid race conditions
done

return ${WAIT_ERRORS}
}

# -----------------------------------------------------------------------------
function warn
{
NOW="$(date '+%d-%h-%Y %H:%M:%S')"

if [[ -n "$1" ]]
then
    if (( ARG_LOG ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'WARN:'
            LOG_LINE="${LOG_LINE#WARN: *}"
            print "${NOW}: WARN: [$$]:" "${LOG_LINE}" >>${LOG_FILE}
        done
    fi
    if (( ARG_VERBOSE ))
    then
        print - "$*" | while read LOG_LINE
        do
            # filter leading 'WARN:'
            LOG_LINE="${LOG_LINE#WARN: *}"
            print "WARN:" "${LOG_LINE}"
        done
    fi
fi

return 0
}


#******************************************************************************
# MAIN routine
#******************************************************************************

# parse arguments/parameters
CMD_LINE="$@"
for PARAMETER in ${CMD_LINE}
do
    case ${PARAMETER} in
        -a|-apply|--apply)
            ARG_ACTION=1
            ;;
        -b|-backup|--backup)
            ARG_ACTION=9
            ;;
        -c|-copy|--copy)
            ARG_ACTION=2
            ;;
        -debug|--debug)
            ARG_DEBUG=1
            ;;
        -d|-distribute|--distribute)
            ARG_ACTION=2
            ;;
        -p|--preview-global|-preview-global)
            ARG_ACTION=7
            ;;
        -fix-local|--fix-local)
            ARG_ACTION=5
            ;;
        -fix-remote|--fix-remote)
            ARG_ACTION=6
            ;;
        -s|-check-syntax|--check-syntax)
            ARG_ACTION=8
            ;;
        -check-sudo|--check-sudo)
            ARG_ACTION=3
            ARG_LOG=0
            CAN_CHECK_SYNTAX=1
            CAN_REMOVE_TEMP=1
            ;;
        -u|-update|--update)
            ARG_ACTION=4
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
        -targets=*)
            ARG_TARGETS="${PARAMETER#-targets=}"
            ;;
        --targets=*)
            ARG_TARGETS="${PARAMETER#--targets=}"
            ;;
        -V|-version|--version)
            print "INFO: $0: ${MY_VRF}"
            exit 0
            ;;
        \? | -h | -help | --help)
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
        . "${SCRIPT_DIR}/${GLOBAL_CONFIG_FILE}"
    fi
    if [[ -r "${SCRIPT_DIR}/${LOCAL_CONFIG_FILE}" ]]
    then
        . "${SCRIPT_DIR}/${LOCAL_CONFIG_FILE}"
    fi
else
    print -u2 "ERROR: could not find global or local configuration file"
fi  

# startup checks
check_params && check_config && check_setup && check_logging

# catch shell signals
trap 'do_cleanup; exit' 1 2 3 15

log "*** start of ${SCRIPT_NAME} [${CMD_LINE}] ***"    
(( ARG_LOG )) && log "logging takes places in ${LOG_FILE}"  

log "runtime info: LOCAL_DIR is set to: ${LOCAL_DIR}"

case ${ARG_ACTION} in
    1)  # apply SUDO controls remotely
        log "ACTION: apply SUDO controls remotely"
        check_root_user && die "must NOT be run as user 'root'"
        # build clients list (in array)
        cat "${TARGETS_FILE}" | grep -v -E -e '^#' -e '^$' |\
        {
            I=0
            set -A CLIENTS
            while read LINE
            do
                CLIENTS[${I}]="${LINE}"
                I=$(( I + 1 ))
            done
        }
        # set max updates in background
        COUNT=${MAX_BACKGROUND_PROCS}
        for CLIENT in ${CLIENTS[@]}
        do
            update2host ${CLIENT} &
            PID=$!
            log "updating ${CLIENT} in background [PID=${PID}] ..."
            # add PID to list of all child PIDs
            PIDS="${PIDS} ${PID}"
            COUNT=$(( COUNT - 1 ))
            if (( COUNT <= 0 ))
            then
                # wait until all background processes are completed
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

        log "finished applying SUDO controls remotely"
        ;;
    2)  # copy/distribute SUDO controls
        log "ACTION: copy/distribute SUDO controls"
        check_root_user && die "must NOT be run as user 'root'"
        # build clients list (in array)
        cat "${TARGETS_FILE}" | grep -v -E -e '^#' -e '^$' |\
        {
            I=0
            set -A CLIENTS
            while read LINE
            do
                CLIENTS[${I}]="${LINE}"
                I=$(( I + 1 ))
            done
        }
        # set max updates in background
        COUNT=${MAX_BACKGROUND_PROCS}
        for CLIENT in ${CLIENTS[@]}
        do
            distribute2host ${CLIENT} &
            PID=$!
            log "copying/distributing to ${CLIENT} in background [PID=${PID}] ..."
            # add PID to list of all child PIDs
            PIDS="${PIDS} ${PID}"
            COUNT=$(( COUNT - 1 ))
            if (( COUNT <= 0 ))
            then
                # wait until all background processes are completed
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
        log "finished copying/distributing SUDO controls"
        ;;
    3)  # perform syntax checking
        log "ACTION: validating SUDO fragments"
        # are fragments stored in a file or a directory?
        if [[ -n "${FRAGS_DIR}" ]]
        then
            TMP_WORK_DIR="${TMP_DIR}/$0.${RANDOM}"
            mkdir -p ${TMP_WORK_DIR}
            if (( $? ))
            then
                die "unable to create temporary directory ${TMP_WORK_DIR} for mangling of 'fragments' file"
            fi
            merge_fragments ${TMP_WORK_DIR}
        fi
        # remove '%%%' headers
        TMP_SCAN_FILE=$(mktemp)
        (( $? )) && die "unable to create temporary file for validation of 'fragments' file(s)"
        if [[ -n "${FRAGS_DIR}" ]]
        then
            cat ${TMP_MERGE_FILE} | grep -v '^%%%' >${TMP_SCAN_FILE}
            [[ -d ${TMP_WORK_DIR} ]] && rm -rf ${TMP_WORK_DIR} 2>/dev/null        
        else
            cat ${FRAGS_FILE} | grep -v '^%%%' >${TMP_SCAN_FILE}        
        fi
        # run syntax check
        if (( CAN_CHECK_SYNTAX ))
        then
            CHECK_RESULT="$(${VISUDO_BIN} -c -f ${TMP_SCAN_FILE} 2>/dev/null)"
            if (( $? )) 
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
        ( RC=0; ${LOCAL_DIR}/update_sudo.pl ${SUDO_UPDATE_OPTS};
          print "$?" > ${TMP_RC_FILE}; exit
        ) 2>&1 | logc
        # fetch return code from subshell
        RC="$(< ${TMP_RC_FILE})"
        if (( RC ))
        then
            log "failed to apply SUDO controls locally [RC=${RC}]"
        else
            log "finished applying SUDO controls locally [RC=${RC}]"     
        fi
        ;;
    5)  # fix directory structure/perms/ownerships
        log "ACTION: fix local SUDO controls repository"
        check_root_user || die "must be run as user 'root'"
        if (( FIX_CREATE ))
        then
            log "you requested to create directories (if needed)"
        else
            log "you requested NOT to create directories (if needed)"       
        fi
        
        # check if the SUDO control repo is already there
        if [[ ${FIX_CREATE} = 1 && ! -d "${FIX_DIR}" ]]
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
                    chown root:${SUDO_OWNER_GROUP} "${FIX_DIR}/holding" 2>/dev/null
            fi                  
            if [[ -d "${FIX_DIR}/sudoers.d" ]]
            then
                chmod 755 "${FIX_DIR}/sudoers.d" 2>/dev/null && \
                    chown root:sys "${FIX_DIR}/sudoers.d" 2>/dev/null
            fi
            # checking files (sudoers.d/* are fixed by update_sudo.pl)
            for FILE in grants alias fragments update_sudo.conf
            do
                if [[ -f "${FIX_DIR}/holding/${FILE}" ]]
                then
                    chmod 660 "${FIX_DIR}/holding/${FILE}" 2>/dev/null && \
                        chown root:${SUDO_OWNER_GROUP} "${FIX_DIR}/holding/${FILE}" 2>/dev/null
                fi
            done
            for FILE in manage_sudo.sh update_sudo.pl
            do
                if [[ -f "${FIX_DIR}/holding/${FILE}" ]]
                then
                    chmod 770 "${FIX_DIR}/holding/${FILE}" 2>/dev/null && \
                        chown root:${SUDO_OWNER_GROUP} "${FIX_DIR}/holding/${FILE}" 2>/dev/null
                fi
            done
            # log file
            if [[ -f "${LOG_FILE}" ]]
            then
                chmod 664 "${LOG_FILE}" 2>/dev/null && \
                    chown root:${SUDO_OWNER_GROUP} "${LOG_FILE}" 2>/dev/null
            fi
            # check for SELinux labels
            case ${OS_NAME} in
                *Linux*)
                    case "$(getenforce)" in
                        *Permissive*|*Enforcing*)
                            chcon -R -t etc_t "${FIX_DIR}/sudoers.d"
                            ;;
                        *Disabled*)
                            :
                            ;;
                    esac
                    ;;
                *)
                    :
                    ;;
            esac
        else
            die "SUDO controls repository at "${FIX_DIR}" does not exist?"
        fi
        log "finished applying fixes to the local SUDO control repository"
        ;;
    6)  # fix remote directory structure/perms/ownerships
        log "ACTION: fix remote SUDO controls repository"
        check_root_user && die "must NOT be run as user 'root'"
        # derive SUDO controls repo from $REMOTE_DIR: 
        # /etc/sudo_controls/holding -> /etc/sudo_controls 
        FIX_DIR="$(print ${REMOTE_DIR%/*})"
        [[ -z "${FIX_DIR}" ]] && \
            die "could not determine SUDO controls repo path from \$REMOTE_DIR?"
        # build clients list (in array)
        cat "${TARGETS_FILE}" | grep -v -E -e '^#' -e '^$' |\
        {
            I=0
            set -A CLIENTS
            while read LINE
            do
                CLIENTS[${I}]="${LINE}"
                I=$(( I + 1 ))
            done
        }
        # set max updates in background
        COUNT=${MAX_BACKGROUND_PROCS}
        for CLIENT in ${CLIENTS[@]}
        do
            fix2host ${CLIENT} "${FIX_DIR}" &
            PID=$!
            log "copying/distributing to ${CLIENT} in background [PID=${PID}] ..."
            # add PID to list of all child PIDs
            PIDS="${PIDS} ${PID}"
            COUNT=$(( COUNT - 1 ))
            if (( COUNT <= 0 ))
            then
                # wait until all background processes are completed
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
        log "finished applying fixes to the remote SUDO control repository"
        ;;
    7)  # dump the configuration namespace
        log "ACTION: dumping the global grants namespace with resolved aliases ..."
        ${LOCAL_DIR}/update_sudo.pl --preview --global
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
            if [ \( -f ${BACKUP_TAR_FILE} \) -o \( -f "${BACKUP_TAR_FILE}.gz" \) ]
            then
                die "backup file ${BACKUP_TAR_FILE}(.gz) already exists"
            fi
            # fragments files
            if [[ -n "${FRAGS_DIR}" ]]
            then
                log "$(tar -cvf ${BACKUP_TAR_FILE} ${FRAGS_DIR} 2>/dev/null)"
            else
                log "$(tar -cvf ${BACKUP_TAR_FILE} ${FRAGS_FILE} 2>/dev/null)"   
            fi
            # configuration files
            for FILE in "${LOCAL_DIR}/grants" "${LOCAL_DIR}/alias ${LOCAL_DIR}/targets"
            do
                log "$(tar -rvf ${BACKUP_TAR_FILE} ${FILE} 2>/dev/null)"
            done
            log "$(gzip ${BACKUP_TAR_FILE} 2>/dev/null)"
            log "resulting backup file is: $(ls -1 ${BACKUP_TAR_FILE}* 2>/dev/null)"
        else
            die "could not find backup directory ${BACKUP_DIR}. Host is not an SUDO master?"
        fi
        log "finished backing up the current configuration & fragment files"
        ;;
esac

# finish up work
do_cleanup

#******************************************************************************
# END of script
#******************************************************************************
