#!/usr/bin/env bash

# terraformer.sh within https://github.com/wilsonmar/tf-samples/blob/main/terraformer.sh
# This script automates https://github.com/GoogleCloudPlatform/terraformer
# A CLI tool that generates tf/json and tfstate files based on existing infrastructure (reverse Terraform).
# -Installs and -Upgrades bash, jq, wget, git, tfsec, then
# download a GPG secret key for running tfsec, and
# runs tfsec to a file with a name containing a date/time stamp.

# cd to folder, copy this line and paste in the terminal:
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/wilsonmar/tf-samples/main/terraformer.sh)" -v 
# This was tested on MacOS 18.7.0 

# SETUP STEP 01 - Capture starting timestamp and display no matter how it ends:
THIS_PROGRAM="$0"
SCRIPT_VERSION="v0.0.4"

EPOCH_START="$( date -u +%s )"  # such as 1572634619
LOG_DATETIME=$( date +%Y-%m-%dT%H%M%S%z)
# clear  # screen (but not history)
echo "  $THIS_PROGRAM $SCRIPT_VERSION ============== $LOG_DATETIME "

# SETUP STEP 02 - Ensure run variables are based on arguments or defaults ..."
args_prompt() {
   echo "OPTIONS:"
   echo "   -E           to set -e to NOT stop on error"
   echo "   -x           to set -x to trace command lines"
   echo "   -v           to run -verbose (list space use and each image to console)"
   echo "   -vv          to run -very verbose for debugging"
   echo "   -q           -quiet headings for each step"
   echo " "
   echo "   -I           Install brew, jq, git, docker"
   echo "   -U           Upgrade brew packages"
   echo " "
   echo "USAGE EXAMPLE:"
   echo "./terraformer.sh -v -I -U "
 }
if [ $# -eq 0 ]; then  # display if no parameters are provided:
   args_prompt
   exit 1
fi
exit_abnormal() {            # Function: Exit with error.
  echo "exiting abnormally"
  #args_prompt
  exit 1
}

# SETUP STEP 03 - Set Defaults (default true so flag turns it true):
   SET_EXIT=true                # -E
   RUN_QUIET=false              # -q
   DOWNLOAD_INSTALL=false       # -I
   UPDATE_PKGS=false            # -U
   SET_TRACE=false              # -x
   RUN_VERBOSE=false            # -v
   RUN_DEBUG=false              # -vv
   UPDATE_PKGS=false            # -U
   AWS_PROFILE="default"        # -p
   TF_FILE=""                   # -tf  # terraform file name
   BUCKET_IN=""                 # -b  # bucket in S3
   EXEC_SUB_COMMAND=""          # -x
   CMD_SETUP=false              # -setup
   CMD_TEARDOWN=false           # -teardown

   PROJECT_FOLDER_PATH="$HOME/projects"  # -P
   GitHub_REPO_URL="https://github.com/GoogleCloudPlatform/terraformer.git"
   GitHub_REPO_NAME="terraformer"

# SETUP STEP 04 - Read parameters specified:
while test $# -gt 0; do
  case "$1" in
    -b*)
      shift
             BUCKET_IN=$( echo "$1" | sed -e 's/^[^=]*=//g' )
      export BUCKET_IN
      shift
      ;;
    -E)
      export SET_EXIT=false
      shift
      ;;
    -q)
      export RUN_QUIET=true
      shift
      ;;
    -I)
      export DOWNLOAD_INSTALL=true
      shift
      ;;
    -U)
      export UPDATE_PKGS=true
      shift
      ;;
    -v)
      export RUN_VERBOSE=true
      shift
      ;;
    -vv)
      export RUN_DEBUG=true
      shift
      ;;
    -p*)
      shift
             AWS_PROFILE=$( echo "$1" | sed -e 's/^[^=]*=//g' )
      export AWS_PROFILE
      shift
      ;;
    -x)
      export SET_TRACE=true
      shift
      ;;
    -setup)
      export CMD_SETUP=true
      shift
      ;;
    -teardown)
      export CMD_TEARDOWN=true
      shift
      ;;
    -tf*)
      shift
             TF_FILE=$( echo "$1" | sed -e 's/^[^=]*=//g' )
      export TF_FILE
      shift
      ;;
    -U)
      export UPDATE_PKGS=true
      shift
      ;;
    *)
      error "Parameter \"$1\" not recognized. Aborting."
      exit 0
      break
      ;;
  esac
done


# SETUP STEP 04 - Set ANSI color variables (based on aws_code_deploy.sh): 
bold="\e[1m"
dim="\e[2m"
# shellcheck disable=SC2034 # ... appears unused. Verify use (or export if used externally).
underline="\e[4m"
# shellcheck disable=SC2034 # ... appears unused. Verify use (or export if used externally).
blink="\e[5m"
reset="\e[0m"
red="\e[31m"
green="\e[32m"
# shellcheck disable=SC2034 # ... appears unused. Verify use (or export if used externally).
blue="\e[34m"
cyan="\e[36m"

# SETUP STEP 05 - Specify alternate echo commands:
h2() { if [ "${RUN_QUIET}" = false ]; then    # heading
   printf "\n${bold}\e[33m\u2665 %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
   fi
}
info() {   # output on every run
   printf "${dim}\n➜ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
note() { if [ "${RUN_VERBOSE}" = true ]; then
   printf "\n${bold}${cyan} ${reset} ${cyan}%s${reset}" "$(echo "$@" | sed '/./,$!d')"
   printf "\n"
   fi
}
debug_echo() { if [ "${RUN_DEBUG}" = true ]; then
   printf "\n${bold}${cyan} ${reset} ${cyan}%s${reset}" "$(echo "$@" | sed '/./,$!d')"
   printf "\n"
   fi
}
success() {
   printf "\n${green}✔ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
error() {    # &#9747;
   printf "\n${red}${bold}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
warning() {  # &#9758; or &#9755;
   printf "\n${cyan}☞ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
fatal() {   # Skull: &#9760;  # Star: &starf; &#9733; U+02606  # Toxic: &#9762;
   printf "\n${red}☢  %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
divider() {
  printf "\r\033[0;1m========================================================================\033[0m\n"
}

pause_for_confirmation() {
  read -rsp $'Press any key to continue (ctrl-c to quit):\n' -n1 key
}

# SETUP STEP 06 - Check what operating system is in use:
   OS_DETAILS=""  # default blank.
   OS_TYPE="$( uname )"
if [ "$(uname)" == "Darwin" ]; then  # it's on a Mac:
      OS_TYPE="macOS"
      OS_DETAILS=$( uname -r )  # like "18.7.0"
      PACKAGE_MANAGER="brew"
elif [ "$(uname)" == "Linux" ]; then  # it's on a Mac:
   if command -v lsb_release ; then
      OS_TYPE="Ubuntu"
      OS_VERSION=$( uname -r )   # or lsb_release -d  "Description:	Debian GNU/Linux 9.5 (stretch)"
      # TODO: OS_TYPE="WSL" ???
      PACKAGE_MANAGER="apt-get"

      silent-apt-get-install(){  # see https://wilsonmar.github.io/bash-scripts/#silent-apt-get-install
         if [ "${RUN_VERBOSE}" = true ]; then
            info "apt-get install $1 ... "
            sudo apt-get install "$1"
         else
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq "$1" < /dev/null > /dev/null
         fi
      }
   elif [ -f "/etc/os-release" ]; then
      OS_DETAILS=$( cat "/etc/os-release" )  # ID_LIKE="rhel fedora"
      OS_TYPE="Fedora"
      PACKAGE_MANAGER="yum"
   elif [ -f "/etc/redhat-release" ]; then
      OS_DETAILS=$( cat "/etc/redhat-release" )
      OS_TYPE="RedHat"
      PACKAGE_MANAGER="yum"
   elif [ -f "/etc/centos-release" ]; then
      OS_TYPE="CentOS"
      PACKAGE_MANAGER="yum"
   else
      error "Linux distribution not anticipated. Please update script. Aborting."
      exit 0
   fi
else 
   error "Operating system not anticipated. Please update script. Aborting."
   exit 0
fi
note "OS_DETAILS=$OS_DETAILS"

# SETUP STEP 07 - Define utility functions, such as bash function to kill process by name:
ps_kill(){  # $1=process name
      PSID=$(ps aux | grep $1 | awk '{print $2}')
      if [ -z "$PSID" ]; then
         h2 "Kill $1 PSID= $PSID ..."
         kill 2 "$PSID"
         sleep 2
      fi
}

# SETUP STEP 08 - Adjust Bash version:
BASH_VERSION=$( bash --version | grep bash | cut -d' ' -f4 | head -c 1 )
   if [ "${BASH_VERSION}" -ge "4" ]; then  # use array feature in BASH v4+ :
      DISK_PCT_FREE=$(read -d '' -ra df_arr < <(LC_ALL=C df -P /); echo "${df_arr[11]}" )
      FREE_DISKBLOCKS_START=$(read -d '' -ra df_arr < <(LC_ALL=C df -P /); echo "${df_arr[10]}" )
   else
      if [ "${UPDATE_PKGS}" = true ]; then
         info "Bash version ${BASH_VERSION} too old. Upgrading to latest ..."
         if [ "${PACKAGE_MANAGER}" == "brew" ]; then
            brew install bash
         elif [ "${PACKAGE_MANAGER}" == "apt-get" ]; then
            silent-apt-get-install "bash"
         elif [ "${PACKAGE_MANAGER}" == "yum" ]; then    # For Redhat distro:
            sudo yum install bash      # please test
         elif [ "${PACKAGE_MANAGER}" == "zypper" ]; then   # for [open]SuSE:
            sudo zypper install bash   # please test
         fi
         info "Now at $( bash --version  | grep 'bash' )"
         fatal "Now please run this script again now that Bash is up to date. Exiting ..."
         exit 0
      else   # carry on with old bash:
         DISK_PCT_FREE="0"
         FREE_DISKBLOCKS_START="0"
      fi
   fi

# SETUP STEP 09 - Handle run endings:"

# In case of interrupt control+C confirm to exit gracefully:
#interrupt_count=0
#interrupt_handler() {
#  ((interrupt_count += 1))
#  echo ""
#  if [[ $interrupt_count -eq 1 ]]; then
#    fail "Really quit? Hit ctrl-c again to confirm."
#  else
#    echo "Goodbye!"
#    exit
#  fi
#}

trap interrupt_handler SIGINT SIGTERM
trap this_ending EXIT
trap this_ending INT QUIT TERM
this_ending() {
   EPOCH_END=$(date -u +%s);
   EPOCH_DIFF=$((EPOCH_END-EPOCH_START))
   # Using BASH_VERSION identified above:
   if [ "${BASH_VERSION}" -lt "4" ]; then
      FREE_DISKBLOCKS_END="0"
   else
      FREE_DISKBLOCKS_END=$(read -d '' -ra df_arr < <(LC_ALL=C df -P /); echo "${df_arr[10]}" )
   fi
   FREE_DIFF=$(((FREE_DISKBLOCKS_END-FREE_DISKBLOCKS_START)))
   MSG="End of script $SCRIPT_VERSION after $((EPOCH_DIFF/360)) seconds and $((FREE_DIFF*512)) bytes on disk."
   # echo 'Elapsed HH:MM:SS: ' $( awk -v t=$beg-seconds 'BEGIN{t=int(t*1000); printf "%d:%02d:%02d\n", t/3600000, t/60000%60, t/1000%60}' )
   success "$MSG"
   # note "Disk $FREE_DISKBLOCKS_START to $FREE_DISKBLOCKS_END"
}
sig_cleanup() {
    trap '' EXIT  # some shells call EXIT after the INT handler.
    false # sets $?
    this_ending
}

#################### Print run heading:

# SETUP STEP 10 - Operating environment information:
HOSTNAME=$( hostname )
PUBLIC_IP=$( curl -s ifconfig.me )

if [ "$OS_TYPE" == "macOS" ]; then  # it's on a Mac:
   debug_echo "BASHFILE=~/.bash_profile ..."
   BASHFILE="$HOME/.bash_profile"  # on Macs
else
   debug_echo "BASHFILE=~/.bashrc ..."
   BASHFILE="$HOME/.bashrc"  # on Linux
fi
   debug_echo "Running $0 in $PWD"  # $0 = script being run in Present Wording Directory.
   debug_echo "OS_TYPE=$OS_TYPE $OS_DETAILS using $PACKAGE_MANAGER from $DISK_PCT_FREE disk free"
   debug_echo "on hostname=$HOSTNAME at PUBLIC_IP=$PUBLIC_IP."
   debug_echo " "

# print all command arguments submitted:
#while (( "$#" )); do 
#  echo $1 
#  shift 
#done 


# SETUP STEP 11 - Define run error handling:
EXIT_CODE=0
if [ "${SET_EXIT}" = true ]; then  # don't
   debug_echo "Set -e (no -E parameter  )..."
   set -e  # exits script when a command fails
   # set -eu pipefail  # pipefail counts as a parameter
else
   warning "Don't set -e (-E parameter)..."
fi
if [ "${SET_XTRACE}" = true ]; then
   debug_echo "Set -x ..."
   set -x  # (-o xtrace) to show commands for specific issues.
fi
# set -o nounset


# SETUP STEP 12 - Configure location to create new files:
if [ -z "$PROJECT_FOLDER_PATH" ]; then  # -p ""  override blank (the default)
   h2 "Using current folder as project folder path ..."
   pwd
else
   if [ ! -d "$PROJECT_FOLDER_PATH" ]; then  # path not available.
      note "Creating folder $PROJECT_FOLDER_PATH as -project folder path ..."
      mkdir -p "$PROJECT_FOLDER_PATH"
   fi
   pushd "$PROJECT_FOLDER_PATH" || return # as suggested by SC2164
   note "Pushed into path $PWD during script run ..."
fi
# note "$( ls )"

# divider

# SETUP STEP 13 - Install brew/choco installer manager:
if [ "${DOWNLOAD_INSTALL}" = true ]; then  # -I

   if [ "${PACKAGE_MANAGER}" == "brew" ]; then

         if ! command -v git >/dev/null; then  # command not found, so:
            h2 "Brew installing git ..."
            brew install git
         else  # installed already:
            if [ "${UPDATE_PKGS}" = true ]; then
               h2 "Brew upgrading git ..."
               brew upgrade git
            fi
         fi   # includes curl
         note "$( git --version )"
            # git, version 2018.11.26

         if ! command -v jq >/dev/null; then  # command not found, so:
            h2 "Brew installing jq ..."
            brew install jq
         else  # installed already:
            if [ "${UPDATE_PKGS}" = true ]; then
               h2 "Brew upgrading jq ..."
               brew upgrade jq
            fi
         fi
         note "$( jq --version )"  # jq-1.6


         if ! command -v tfsec >/dev/null; then  # command not found, so:
            h2 "Brew installing tfsec ..."
            brew install tfsec
         else  # installed already:
            if [ "${UPDATE_PKGS}" = true ]; then
               h2 "Brew upgrading tfsec ..."
               brew upgrade tfsec
            fi
         fi
         note "tfsec $( tfsec --version )"


         if ! command -v wget >/dev/null; then  # command not found, so:
            h2 "Brew installing wget ..."
            brew install wget
         else  # installed already:
            if [ "${UPDATE_PKGS}" = true ]; then
               h2 "Brew upgrading wget ..."
               brew upgrade wget
            fi
         fi
         note "$( wget --version | head -n 1 )"
            # GNU Wget 1.21.2 built on darwin18.7.0.
            # ...


         if ! command -v gpg >/dev/null; then  # command not found, so:
            h2 "Brew installing gpg ..."
            brew install gpg
         else  # installed already:
            if [ "${UPDATE_PKGS}" = true ]; then
               h2 "Brew upgrading gpg ..."
               brew upgrade gpg
            fi
         fi
         note "$( gpg --version | head -n 1 )"
            # gpg (GnuPG/MacGPG2) 2.2.27


         if ! command -v go >/dev/null; then
            h2 "Brew installing go ..."
            brew install go
         else  # installed already:
            if [ "${UPDATE_PKGS}" = true ]; then
               h2 "Brew upgrading go ..."
               brew upgrade go
            fi
         fi
         note "$( go version )"  # go version go1.17.2 darwin/amd64
            # go: GOPATH entry is relative; must be absolute path: "$HOME/go".

   elif [ "${PACKAGE_MANAGER}" == "choco" ]; then

         if ! command -v git >/dev/null; then  # command not found, so:
            h2 "Brew installing git ..."
            brew install git
         else  # installed already:
            if [ "${UPDATE_PKGS}" = true ]; then
               h2 "Brew upgrading git ..."
               brew upgrade git
            fi
         fi
         note "$( git --version )"
            # git, version 2018.11.26

   fi  # PACKAGE_MANAGER

   # SETUP STEP 14 - Download & Install GitHub repo:
   Delete_GitHub_clone(){
      # https://www.shellcheck.net/wiki/SC2115 Use "${var:?}" to ensure this never expands to / .
      PROJECT_FOLDER_FULL_PATH="${PROJECT_FOLDER_PATH}/${GitHub_REPO_NAME}"
      if [ -d "${PROJECT_FOLDER_FULL_PATH:?}" ]; then  # path available.
         h2 "Removing project folder $PROJECT_FOLDER_FULL_PATH ..."
         ls -al "${PROJECT_FOLDER_FULL_PATH}"
         rm -rf "${PROJECT_FOLDER_FULL_PATH}"
      fi
   }
   Clone_GitHub_repo(){
      git clone "${GitHub_REPO_URL}" "$GitHub_REPO_NAME"
      cd "$GitHub_REPO_NAME"
      note "At $PWD"
   }

   if [ "${CLONE_GITHUB}" = true ]; then   # -clone specified:

      if [ -z "${GitHub_REPO_NAME}" ]; then   # name not specified:
         fatal "GitHub_REPO_NAME not specified ..."
         exit
      fi 

      if [ -z "${PROJECT_FOLDER_PATH}" ]; then   # No name specified:
         fatal "PROJECT_FOLDER_PATH not specified ..."
         exit
      fi

      PROJECT_FOLDER_FULL_PATH="${PROJECT_FOLDER_PATH}/${GitHub_REPO_NAME}"
      h2 "-clone requested for $GitHub_REPO_URL $GitHub_REPO_NAME ..."
      if [ -d "${PROJECT_FOLDER_FULL_PATH:?}" ]; then  # path available.
         rm -rf "$GitHub_REPO_NAME" 
         Delete_GitHub_clone    # defined above in this file.
      fi

      Clone_GitHub_repo      # defined above in this file.
         # curl -s -O https://raw.GitHubusercontent.com/wilsonmar/build-a-saas-app-with-flask/master/sample.sh
         # git remote add upstream https://github.com/nickjj/build-a-saas-app-with-flask
         # git pull upstream master

   
      # SETUP STEP 15 - Install Golang
      # See https://wilsonmar.github.io/golang


   else   # do not -clone
      if [ -d "${GitHub_REPO_NAME}" ]; then  # path available.
         h2 "Re-using repo $GitHub_REPO_URL $GitHub_REPO_NAME ..."
         cd "$GitHub_REPO_NAME"
      else
         h2 "Git cloning repo $GitHub_REPO_URL $GitHub_REPO_NAME ..."
         # Clone_GitHub_repo      # defined above in this file.
      fi
   fi
   note "$( ls $PWD )"

fi # if [ "${DOWNLOAD_INSTALL}"


# After downloading GitHub:
   note "go mod download ... "
   go mod download

export PROVIDER=aws   # {all,google,aws,kubernetes}
curl -LO https://github.com/GoogleCloudPlatform/terraformer/releases/download/$(curl -s https://api.github.com/repos/GoogleCloudPlatform/terraformer/releases/latest | grep tag_name | cut -d '"' -f 4)/terraformer-${PROVIDER}-darwin-amd64
chmod +x terraformer-${PROVIDER}-darwin-amd64
sudo  mv terraformer-${PROVIDER}-darwin-amd64 /usr/local/bin/terraformer


###  08. Validate variables controlling run:

###  09. Setup folders needed:

SIGNING_FILEPATH="signing.asc"
   if [ ! -f "$SIGNING_FILEPATH" ]; then   # file NOT found, then copy from github:
      note "wget $SIGNING_FILEPATH ... "
      # curl -v -O https://tfsec.dev/assets/signing.asc
      wget --quiet https://tfsec.dev/assets/signing.asc
   fi
   if [ ! -f "$SIGNING_FILEPATH" ]; then   # file NOT found
      fatal "$SIGNING_FILEPATH not found after download."
      exit -1
   else
      note "ls $SIGNING_FILEPATH ..."
      ls -al "$SIGNING_FILEPATH"
   fi


   RESPONSE=$( gpg --list-keys signing@tfsec.dev )
      # pub   rsa4096 2021-05-20 [SC]
      #       D66B222A3EA4C25D5D1A097FC34ACEFB46EC39CE
      # uid           [ unknown] Tfsec Signing (Code signing for tfsec) <signing@tfsec.dev>
      # sub   rsa4096 2021-05-20 [E]
   if [[ "$RESPONSE" == *"signing@tfsec.dev"* ]]; then
      note "Using signing@tfsec.dev in $HOME/.gnupg/pubring.kbx ..."
   else  # not found
      echo "yikes"
      exit
      note "gpg --allow-secret-key-import --import < $SIGNING_FILEPATH ... "
      gpg --allow-secret-key-import --import "$SIGNING_FILEPATH"
         # gpg: key C34ACEFB46EC39CE: public key "Tfsec Signing (Code signing for tfsec) <signing@tfsec.dev>" imported
         # gpg: Total number processed: 1
         # gpg:               imported: 1
      retval=$?
      if [ $retval -ne 0 ]; then
         fatal "Returning $retval - aborting."
         exit -1
      fi
   fi

   gpg --list-keys signing@tfsec.dev
      # pub   rsa4096 2021-05-20 [SC]
      #       D66B222A3EA4C25D5D1A097FC34ACEFB46EC39CE
      # uid           [ unknown] Tfsec Signing (Code signing for tfsec) <signing@tfsec.dev>
      # sub   rsa4096 2021-05-20 [E]
   retval=$?
   if [ $retval -ne 0 ]; then
      fatal "Returning $retval - aborting."
      exit -1
   fi

CURRENT_FOLDER=$( basename "$PWD" )   # or ${PWD##*/} 
TFSEC_OUTPUT_FILE="tfsec.$CURRENT_FOLDER.$LOG_DATETIME.txt"
note "tfsec . --no-color --concise-output --out $TFSEC_OUTPUT_FILE "
   tfsec . --no-color --out "$TFSEC_OUTPUT_FILE"
      #  --concise-output
   retval=$?
   note "Returning $retval "
   ls -al "$TFSEC_OUTPUT_FILE"
   code "$TFSEC_OUTPUT_FILE"

# note "run tfsec in a Docker container:"
#   docker run --rm -it -v "$(pwd):/src" aquasec/tfsec /src   