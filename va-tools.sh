#! /bin/env bash

# Are We being sourced ?
if [[ "$0" = "$BASH_SOURCE" ]]; then
    echo "Please source this script. Do not execute."
fi

## Aliases
alias ll='ls -al'

## VA Connection
# This will output the download speed of the VA either to a hook or to stdoout
speed_test() {
    
    # Have to handle params here
    # This is messed up for the moment
    DL_URL=${1:-https://proof.ovh.net/files/100Mb.dat}
    WEBHOOK_URL=${2:-stdout}
    WAIT_DELAY=${3:-10m}
    
    while true
    do
        # Now's date in ISO format
        start_date=$(date '%m-%d-%YT%H:%M:%S')
        
        # Actual total download time
        time_total=$(curl -s -o /dev/null "${DL_URL}" -w "%{time_total}")
        
        # Report results : if WEB_HOOK is set, then report to the endpoint,
        # Otherwise print to stdout
        data="{(\"@timestamp\":\"${start_date}\",\"time total\":\"${time_total}\"}"
        if [[ $WEBHOOK_URL == "stdout" ]]
        then
            echo "${data}"
        else
            curl -k -XPOST "${WEBHOOK_URL}" -H"Content-type:Application/json" -d"${data}"
        fi
        
        # Wait the configured delay
        sleep "${WAIT_DELAY}"
    done
}

## TLS / Certificates
# This function will get certificates from a <host>:<port> string and output
# the whole chain in the current directory in files named after the CN
get_certificates() {
    
    # Quick param check
    [[ ! $1 =~ .*:[0-9]* ]] && { echo "Usage : ${FUNCNAME[0]} <host>:<port>" ; return 1 ; }
    
    # Where to output ?
    output_file=$(mktemp)
    # output from openssl
    if ! openssl s_client -showcerts -connect "$1" > "${output_file}" < /dev/null 2> /dev/null
    then
        echo "There was a problem with getting certificates from ${1} please check that it is the right server name and port"
    fi
    
    awk '
BEGIN {
# change field separator, so that $2 returns everything after "CN = "
FS="CN = "
}
# selects line which contains CN (e.g.  0 s:CN = www.openssl.org)
/^ [0-9]+ s:.*CN = / {
# use CN (e.g. www.openssl.org) as filename
filename=gensub(/ /,"_","g",$2".pem")
}
# write all lines between "BEGIN CERTIFICATE" and "END CERTIFICATE" to filename
/BEGIN CERTIFICATE/,/END CERTIFICATE/ {
print $0 > filename
}
    ' "${output_file}"
    
}

## Logging
# ccg : nicer readable format
# TODO : colors : https://apihandyman.io/api-toolbox-jq-and-openapi-part-4-bonus-coloring-jqs-raw-output/
ccgl() {
    tail -f /home/sailpoint/log/ccg.log | jq -r -R ' fromjson? | ."@timestamp" +" - " +  .message'
}