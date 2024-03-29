#! /bin/env bash

# Are We being sourced ?
if [[ "$0" = "$BASH_SOURCE" ]]; then
    echo "Please source this script. Do not execute."
else
    echo    "##################################################################################"
    echo -e "###                \e[34mWelcome to the va-tools tools library\e[0m                       ###"
    echo    "### Run the va-tools command to see what functions are vavailable at this time ###"
    echo    "###                              DISCLAIMER                                    ###"
    echo    "###     !!! This tool is neither released nor Supported by Sailpoint !!!       ###"
    echo    "###     If you have questions, requests or bugs to report, please contact      ###"
    echo    "###                       christophe.chazeau@sailpoint.com                     ###"
    echo    "##################################################################################"
fi

## Aliases
alias ll='ls -al'

##############################
### What is that about ?? ####
##############################
va-tools() {
    logline "INFO" "################"
    logline "INFO" "### VA-TOOLS ###"
    logline "INFO" "################"
    logline "INFO" "This script offers a few functions simplifying certain VA tasks"
    logline "INFO" "Here is the complete list of what it offers so far :"
    logline "INFO" ""
    logline "INFO" "  * logline   : logs a line with level coloring :"
    logline "INFO" "      usage   : logline [SUCCESS|WARNING|ERROR|INFO] \"Message to log\""
    logline "INFO" ""
    logline "INFO" "  * logmessage   : logs a message with level coloring (no newline):"
    logline "INFO" "      usage      : logmessage [SUCCESS|WARNING|ERROR|INFO] \"Message to log\""
    logline "INFO" ""
    logline "INFO" "  * speed_test   : Performs a connection test and output either to an endpoint or stdout"
    logline "INFO" "      usage      : speed_test <FILE_TO_DOWNLOAD> <DELAY_BETWEEN_DOWNLOADS> <ENDPOINT_TO_POST_RESULTS>"
    logline "INFO" "      default    : speed_test https://proof.ovh.net/files/100Mb.dat 10m stdout"
    logline "INFO" ""
    logline "INFO" "  * mitm_proxy   : Tries to guess if the VA connects through a proxy performing MITM :"
    logline "INFO" "      usage      : mitm_proxy"
    logline "INFO" ""
    logline "INFO" "  * get_certificates   : Dumps the whole certificate chain (if available) presented by a server "
    logline "INFO" "      usage            : get_certificates <SERVER>:<PORT>"
    logline "INFO" ""
    logline "INFO" "  * valogs    : Display and follow the logs in a more human friendly fashion. It will only handle JSON lines of logs"
    logline "INFO" "      usage   : valogs <LOGFILE>"
    logline "INFO" "      example : valogs ccg"
    logline "INFO" ""
    logline "INFO" "  * stunt   : Downloads and run the stunt script for the support to analyze"
    logline "INFO" "      usage : stunt"
}


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
        start_date=$(date +'%m-%d-%YT%H:%M:%S')
        
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

# MITM PROXY DETECTION
mitm_proxy(){
    # Let's try to guess if we are behind a proxy performing MITM
    # Some free examples : https://mitmproxy.org/ or https://www.telerik.com/fiddler
    # But lots of commercial ones are dong the same thing (Mc Afee, Fortinet ...)
    
    # Find the issuer of the certificate for the www.sailpoint.com website :
    # Note : We use an untrusted connection because if there is a MITM proxy, then most probably
    # curl won't be able to validate the certificate that has been signed on the fly by the Proxy's own
    # CA that the VA don't trust.
    # We assume here that the proxy is correctly setup (proxy.yaml, http_proxy env variables ...)
    SAILPOINT_CERTIFICATE_ISSUER=$(curl --insecure --verbose --output /dev/null --silent https://www.sailpoint.com 2>&1 | grep "issuer:" | sed 's/.*issuer: //')
    
    # We want to find the string DigiCert in that issuer, otherwise, there is a problem and a proxy is
    # most probably signing it on the fly
    echo $SAILPOINT_CERTIFICATE_ISSUER | grep -q "DigiCert"
    [[ $? -eq 0 ]] && logline "SUCCESS" "*No proxy or the proxy is not performing MITM* : www.sailpoint.com certificate has been issued by DigiCert as exepected : ${SAILPOINT_CERTIFICATE_ISSUER}" \
    || logline "ERROR" "The proxy ${https_proxy} is most probably performing MITM because we expect a certificate issued by DigiCert but a connection to www.sailpoint.com returns a certificate issued by : ${SAILPOINT_CERTIFICATE_ISSUER}"
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
    
    logline "WARNING" ""
    logline "WARNING" "This function will only output data from json lines, please refer to the log file to see Stack traces"
    logline "WARNING" "-----------------------------------------------------------------------------------------------------"
    logline "WARNING" ""
    
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

# Get and Execute the stunt log script for support
stunt() {
    
    _script_file=/tmp/stunt.sh
    logline "INFO" "Downloading stunt script to ${_script_file} ..."
    logline "INFO" "The VA needs to have access to the Internet and the githubusercontent.com domain to be opened on the firewalls"
    curl -o ${_script_file} -fsSL https://raw.githubusercontent.com/luke-hagar-sp/VA-Scripts/main/stunt.sh
    logline "INFO" "Executing stunt script from ${_script_file}"
    chmod +x ${_script_file}
    ${_script_file}
    logline "INFO" "stunt script execution end"
}