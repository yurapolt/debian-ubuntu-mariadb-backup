#!/bin/bash

export LC_ALL=C

days_of_backups=3  # Must be less than 7
backup_owner="backup"
parent_dir="/backup/mariadb"
defaults_file="/etc/mysql/backup.cnf"
todays_dir="${parent_dir}/$(date +%a)"
log_file="${todays_dir}/backup-progress.log"
#encryption_key_file="${parent_dir}/encryption_key"
now="$(date +%m-%d-%Y_%H-%M-%S)"
processors="$(nproc --all)"

# Use this to echo to standard error
error () {
    printf "%s: %s\n" "$(basename "${BASH_SOURCE}")" "${1}" >&2
    exit 1
}

trap 'error "An unexpected error occurred."' ERR

sanity_check () {
    # Check user running the script
    if [ "$USER" != "$backup_owner" ]; then
        error "Script can only be run as the \"$backup_owner\" user"
    fi
    
    # Check whether the encryption key file is available
    #if [ ! -r "${encryption_key_file}" ]; then
    #    error "Cannot read encryption key at ${encryption_key_file}"
    #fi
}

set_options () {
    # List the innobackupex arguments
    #declare -ga innobackupex_args=(
        #"--encrypt=AES256"
        #"--encrypt-key-file=${encryption_key_file}"
        #"--encrypt-threads=${processors}"
        #"--slave-info"
        #"--incremental"
        
    innobackupex_args=(
        "--defaults-file=${defaults_file}"
        "--extra-lsndir=${todays_dir}"
        "--backup"
        "--compress"
        "--stream=xbstream"
        "--parallel=${processors}"
        "--compress-threads=${processors}"
    )
    
    backup_type="full"

    # Add option to read LSN (log sequence number) if a full backup has been
    # taken today.
    if grep -q -s "to_lsn" "${todays_dir}/xtrabackup_checkpoints"; then
        backup_type="incremental"
        lsn=$(awk '/to_lsn/ {print $3;}' "${todays_dir}/xtrabackup_checkpoints")
        innobackupex_args+=( "--incremental-lsn=${lsn}" )
    fi
}

rotate_old () {
    # Remove the oldest backup in rotation
    day_dir_to_remove="${parent_dir}/$(date --date="${days_of_backups} days ago" +%a)"

    if [ -d "${day_dir_to_remove}" ]; then
        rm -rf "${day_dir_to_remove}"
    fi
}

take_backup () {
    # Make sure today's backup directory is available and take the actual backup
    mkdir -p "${todays_dir}"
    find "${todays_dir}" -type f -name "*.incomplete" -delete
    #innobackupex "${innobackupex_args[@]}" "${todays_dir}" > "${todays_dir}/${backup_type}-${now}.xbstream.incomplete" 2> "${log_file}"
    mariabackup "${innobackupex_args[@]}" "--target-dir=${todays_dir}" > "${todays_dir}/${backup_type}-${now}.xbstream.incomplete" 2> "${log_file}"
    
    mv "${todays_dir}/${backup_type}-${now}.xbstream.incomplete" "${todays_dir}/${backup_type}-${now}.xbstream"
}

sanity_check && set_options && rotate_old && take_backup

# Check success and print message
if tail -1 "${log_file}" | grep -q "completed OK"; then
    printf "Backup successful!\n"
    printf "Backup created at %s/%s-%s.xbstream\n" "${todays_dir}" "${backup_type}" "${now}"
else
    error "Backup failure! Check ${log_file} for more information"
fi
