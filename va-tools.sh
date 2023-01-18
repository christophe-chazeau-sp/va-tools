#! /bin/env bash

# Are We being sourced ?
if [[ "$0" = "$BASH_SOURCE" ]]; then
    echo "Please source this script. Do not execute."
fi

## Aliases
alias ll='ls -al'

#######################################
### Helper functions and variables ####
#######################################
# Variables
# Colors : declare them once and for all (better than at each call of the log function)
# Key = Level
# Value = Bash color code https://tldp.org/HOWTO/Bash-Prompt-HOWTO/x329.html
declare -A COLORS
COLORS['SUCCESS']='\E[0;32m'
COLORS['WARNING']='\E[0;33m'
COLORS['ERROR']='\E[0;31m'
COLORS['INFO']='\E[0;34m'
COLORS['RESET']=$(tput sgr0)

# URL_REGEX : to check if a variable is a regex
URL_REGEX='(https?)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'

## Functions
# logline : Just log a line with the appropriate level and associated color
# arg 1 : level
# arg 2 : message
logline () {
    # nb. of arguments check
    if [ ! $# -eq 2 ]
    then
        logline "ERROR" "The ${FUNCNAME[0]} function has been called with an incorrect number of arguments, it needs 2 : ${FUNCNAME[0]} <level> <message>"
        return 1
    fi
    
    _level=$1
    _message=$2
    echo -e "${COLORS[$_level]}$_level${COLORS["RESET"]} : $_message"
}

# logmessage : Just log a message without newline, with the color associated to the level parameter
# arg 1 : level
# arg 2 : message
logmessage () {
    # nb. of arguments check
    if [ ! $# -eq 2 ]
    then
        logline "ERROR" "The ${FUNCNAME[0]} function has been called with an incorrect number of arguments, it needs 2 : ${FUNCNAME[0]} <level> <message>"
        return 1
    fi
    
    _level=$1
    _message=$2
    echo -en "${COLORS[$_level]}$_message${COLORS["RESET"]}"
}

## Colored Logging module for jq
# First create ~/.jq directory :
[ ! -d /home/sailpoint/.jq ] && mkdir /home/sailpoint/.jq
# Them put our module in it :

cat << EOF > /home/sailpoint/.jq/coloredvalogs.jq
# Taken from https://apihandyman.io/api-toolbox-jq-and-openapi-part-4-bonus-coloring-jqs-raw-output/
# To learn more about colors in terminal, see https://misc.flogisoft.com/bash/tip_colors_and_formatting
# use with -r flag on jq command

# Unicode escape character
# \e, \033 and \x1b cause "Invalid escape" error
def escape: "\u001b";

# Terminal color codes
def colors:
 {
  "red": "[31m",
  "green": "[32m",
  "yellow": "[33m",
  "blue": "[34m",
  "darkgray": "[90m",
  "magenta": "[35m",
  "disabled": "[30;100m", # Black on darkgray
  "reset": "[0m"
};

# Colors text with the given color
# colored_text("some text"; "red")
# will output
# \u001b[31msome text\u001b[0m
# WARNING parameters are separated by ; not ,
def colored_text(text; color):
  escape + colors[color] + text + escape + colors.reset;
EOF
#####################
### VA Connection ###
#####################
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

##########################
### TLS / Certificates ###
##########################
# This function will get certificates from a <host>:<port> string and output
# the whole chain in the current directory in files named after the CN
get_certificates() {
    
    # Quick param check
    [[ ! $1 =~ .*:[0-9]* ]] && { echo "Usage : ${FUNCNAME[0]} <host>:<port>" ; return 1 ; }
    
    # Where to output ?
    _output_file=$(mktemp)
    # output from openssl
    if ! openssl s_client -showcerts -connect "$1" > "${_output_file}" < /dev/null 2> /dev/null
    then
        echo "There was a problem with getting certificates from ${1} please check that it is the right server name and port"
        return 1
    fi
    
    _cert_files=$(awk '
BEGIN {
# change field separator, so that $2 returns everything after "CN = " or "CN="
# Note : We need to handle differencies in the way openssl outputs
# s_client accros version :
# openssl v1 outputs "CN=" and openssl v3 outputs "CN ="
FS="CN ?= ?"
}
# selects line which contains CN (e.g.  0 s:CN = www.openssl.org)
/^ [0-9]+ s:.*CN ?= ?/ {
# use CN (e.g. www.openssl.org) as filename
# but sanitize it, we don''t want spaces in there
filename=gensub(/ /,"_","g",$2".pem")
printf filename" "
}
# write all lines between "BEGIN CERTIFICATE" and "END CERTIFICATE" to filename
/BEGIN CERTIFICATE/,/END CERTIFICATE/ {
print $0 > filename
}
    ' "${_output_file}")

    logline "INFO" "The certificate chain is in now in those files in the pem format : $_cert_files"

    # Removing our temp file
    rm "${_output_file}"
}

###############
### Logging ###
###############
# Output json content of log files in a nicer readable format
valogs() {
    # nb. of arguments check
    if [ ! $# -eq 1 ]
    then
        logfile "ERROR" "The ${FUNCNAME[0]} function has been called with an incorrect number of arguments, it needs 1 : ${FUNCNAME[0]} <container_name> (va_agent, ccg ...)"
        return 1
    fi
    
    _file="/home/sailpoint/log/${1}.log"
    if [ ! -f "${_file}" ]
    then
        logline "ERROR" "file $1 does not exist"
        return 1 ;
    else
        # Read logs and output colors
        tail -f "$_file" | grep -E --line-buffered '^\{".*\"}$' | jq -r -R 'include "coloredvalogs" ; fromjson? | colored_text("@"+."@timestamp";"blue")+" "+colored_text(.level;"magenta")+" "+.message'
    fi
}
