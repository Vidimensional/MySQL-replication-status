#!/bin/bash

export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export LC_ALL='C'

LOCKFILE='/tmp/replicacheck'

SECONDS_BEHIND_MASTER=3600
EMAIL_ADDRESS=""


# Returns the status of the replica. To know, it checks
# * If Slave_IO_Running equals to Yes
# * If Slave_SQL_Running equals to Yes
# * If Seconds_Behind_Master is lower than ${SECONDS_BEHIND_MASTER} (if ${SECONDS_BEHIND_MASTER} is not defined
#   it will check if it's below than 3600 by default)
is_replica_ok () {
    local awk_script="
    /Slave_IO_Running:/  { if (\$2 == \"Yes\") slave_io = \"true\" }
    /Slave_SQL_Running:/ { if (\$2 == \"Yes\") slave_sql = \"true\" }
    /Seconds_Behind_Master/ { if ( \$2 < ${SECONDS_BEHIND_MASTER:-3600} ) behind_master = \"true\" }
    END {
         if (slave_io && slave_sql && behind_master)
             printf(\"OK\")
         else
             printf(\"NOK\")
    }"

    [ "$( echo "SHOW SLAVE STATUS" | mysql -E | awk "${awk_script}" )" == 'OK' ] && return 0
    return 1
}


# Returns if the LOCKFILE was created before 1 hour ago
is_lockfile_too_old () {
    [ -e "${LOCKFILE}" ] && [ "$(cat ${LOCKFILE})" -lt $( date -d '1 hour ago' +%s) ] && return 0
    return 1
}


# Sends an alert to the address defined on ${EMAIL_ADDRESS}
send_alert () {
    local subject="Replication problems on ${HOSTNAME}"
    local tmp_mailfile="/tmp/$(basename $0).$(date +%s)"

    echo "SHOW SLAVE STATUS" | mysql -E > ${tmp_mailfile}
    mail -s "${subject}" "${EMAIL_ADDRESS}" < ${tmp_mailfile}
    rm -f ${tmp_mailfile}
}


####################
# MAIN
#

if is_replica_ok; then
    # Delete the LOCKFILE if it was present due a previous replica failure
    [ -e ${LOCKFILE} ] && rm -f "${LOCKFILE}"

else

    # If we sent an alert before 1 hour ago, we should send it again
    is_lockfile_too_old && rm -f "${LOCKFILE}"

    if ! [ -e ${LOCKFILE} ]; then
        send_alert
        date +%s > "${LOCKFILE}"
    fi
fi
