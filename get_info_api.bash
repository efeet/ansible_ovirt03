#!/bin/bash

ENGINE_URL="https://rhvm.lab.example.com/ovirt-engine"
USER_NAME="admin@internal"
USER_PASSW="redhat"
#CA_CERT_PATH=/root/RHVM_API_Lab/Ansible/apache-ca.pem

HEADER_CONTENT_TYPE="Content-Type: application/xml"
HEADER_ACCEPT="Accept: application/xml"
COMM_FILE="/var/lib/awx/projects/RHV_VMs/rhv_vms_auto_resources/restapi_com.xml"
STAT_FILE="/var/lib/awx/projects/RHV_VMs/rhv_vms_auto_resources/restapi_stat.xml"
FILE_BEST_HOST="/var/lib/awx/projects/RHV_VMs/rhv_vms_auto_resources/best_hypervisor.yml"
FILE_BEST_STORAGE="/var/lib/awx/projects/RHV_VMs/rhv_vms_auto_resources/best_storage.yml"
BEST_PLACE=""
BEST_MEMFREE=0
BEST_STORAGE=""
BEST_FREESTORAGE=0

#Clear files
>$COMM_FILE
>$STAT_FILE
>$FILE_BEST_HOST
>$FILE_BEST_STORAGE

declare -A hosts_list
declare -A storage_list

function _fill_best_placement_memory {
        for hosts in $(seq 1 $count_host)
        do
                if [ ${hosts_list[$hosts,2]} -gt $BEST_MEMFREE ]
                then
                        BEST_MEMFREE=${hosts_list[$hosts,2]}
                        BEST_PLACE=${hosts_list[$hosts,1]}
                fi
        done
}

function _fill_best_placement_storage {
        for stdom in $(seq 1 $1)
        do
                #echo "Comparando: " ${storage_list[$stdom,0]}
                if [  ${storage_list[$stdom,3]} == "1" ]
                then
                        if [ ${storage_list[$stdom,1]} -gt $BEST_FREESTORAGE ]
                        then
                                BEST_FREESTORAGE=${storage_list[$stdom,1]}
                                BEST_STORAGE=${storage_list[$stdom,0]}
                        fi
                fi
        done
        if [ -z $BEST_STORAGE ]
        then
                echo "ERROR: No existen Storage Domain Tier 1."
                echo "rhvhost: NOAPLICA" >> $FILE_BEST_HOST
                echo "storage_domain: NOAPLICA" >> $FILE_BEST_STORAGE
                exit 1
        fi
}

function _get_apiservice {
        local uri=$1
        #curl -X GET -H "${HEADER_ACCEPT}" -H "${HEADER_CONTENT_TYPE}" -u "${USER_NAME}:${USER_PASSW}" --cacert "${CA_CERT_PATH}" "${ENGINE_URL}${uri}" --output "${2}" 2> /dev/null > "${2}"
        curl -X GET -H "${HEADER_ACCEPT}" -H "${HEADER_CONTENT_TYPE}" -u "${USER_NAME}:${USER_PASSW}" --insecure "${ENGINE_URL}${uri}" --output "${2}" 2> /dev/null > "${2}"
}

function _get_hosts_stats {
        hosts_list[$1,2]=$(xmllint "${STAT_FILE}" --xpath '//max_scheduling_memory/text()')
}

function _get_href_and_name {
        count_host=$(xmllint "${COMM_FILE}" --xpath 'count(//hosts/host)')
        for hosts in $(seq 1 $count_host)
        do
                
                # Get Host URI
                hosts_list[$hosts,0]=$(xmllint "${COMM_FILE}" --xpath '//hosts/host['$hosts']/@href' | sed 's/ href="\/ovirt-engine\([^"]*\)"/\1\n/g')
                # Get Host Name
                hosts_list[$hosts,1]=$(xmllint "${COMM_FILE}" --xpath '//hosts/host['$hosts']/name/text()')
                if [ $( xmllint "${COMM_FILE}" --xpath 'string(//hosts/host['$hosts']/cluster/@id)') == "4e869d1b-1739-4380-a2af-f159ef1af860" ]
                then
                    if [ $( xmllint "${COMM_FILE}" --xpath '//hosts/host['$hosts']/status/text()' ) == "up" ]
                    then
                            # Call statistics function, arg: URI + FileOutput
                            _get_apiservice "${hosts_list[$hosts,0]}" "${STAT_FILE}"
                            _get_hosts_stats $hosts
                    else
                            hosts_list[$hosts,2]=0
                    fi
                else
                    hosts_list[$hosts,2]=0
                fi
        done

        _fill_best_placement_memory
}

function _get_storage_info {
        count_fill=0
        count_storage=$(xmllint "${COMM_FILE}" --xpath 'count(//storage_domain)')
        for stdom in $(seq 1 $count_storage)
        do
                #Get Type of Storage Domain and only pass with Type: data.
                data_type=$(xmllint "${COMM_FILE}" --xpath '//storage_domain['$stdom']/type/text()')
                if [ $data_type = "data" ]
                then
                    count_fill=$(eval expr ${count_fill} + 1)
                    # Get Storage Domain Name
                    storage_list[$stdom,0]=$(xmllint "${COMM_FILE}" --xpath '//storage_domain['$stdom']/name/text()')
                    # Get Storage Domain Available
                    storage_list[$stdom,1]=$(xmllint "${COMM_FILE}" --xpath '//storage_domain['$stdom']/available/text()')
                    # Get Storage Type
                    storage_list[$stdom,2]=$(xmllint "${COMM_FILE}" --xpath '//storage_domain['$stdom']/type/text()')
                    # Get Storage Comment to check Tier level
                    if [[ ! $(xmllint "${COMM_FILE}" --xpath '//storage_domain['$stdom']/comment/text()' | grep NoOrquestation ) ]]
                    then
                        storage_list[$stdom,3]=$(xmllint "${COMM_FILE}" --xpath '//storage_domain['$stdom']/comment/text()' | sed 's/ //g' | tr '[:upper:]' '[:lower:]' | awk -F'tier' '{ print $NF '} | cut -c1 )
                        if ! [[ ${storage_list[$stdom,3]} =~ ^[0-9]+$ ]]
                        then
                                echo "ERROR: El Tier del Almacenamiento no es correcto. -> ${storage_list[$stdom,0]}"
                                exit 1
                        fi
                    else
                        storage_list[$stdom,3]=11
                        storage_list[$stdom,1]=0
                    fi
                else
                    storage_list[$stdom,3]=3
                    storage_list[$stdom,1]=0
                fi
        done
        _fill_best_placement_storage $count_fill
}

_get_apiservice "/api/hosts" "${COMM_FILE}"
_get_href_and_name
_get_apiservice "/api/datacenters/8f998c0c-abd6-4b29-a619-523a8cc52c17/storagedomains" "${COMM_FILE}"
_get_storage_info

echo $BEST_MEMFREE
echo $BEST_PLACE
echo $BEST_PLACE >> $FILE_BEST_HOST
echo $BEST_FREESTORAGE
echo $BEST_STORAGE
echo $BEST_STORAGE >> $FILE_BEST_STORAGE
