#!/usr/bin/env bash
#: Free TAK Server Installation Script

# enforce failfast
set -o errexit
set -o pipefail

# trap or catch signals and direct execution to cleanup
# trap cleanup SIGINT SIGTERM ERR EXIT
trap ctrl_c INT

REPO_INSTALLER="FreeTAKHub-Installation"
REPO_FTS="FreeTakServer"
FREETAKTEAM_BASE="https://github.com/FreeTAKTeam"

IPV4=$(dig @resolver4.opendns.com myip.opendns.com +short -4)

IP_ARG="ansible_host=$IPV4"
LOCALHOST="127.0.0.1"

GROUP_NAME="fts"
VENV_NAME="fts"
PYTHON_VERSION=3.8

CONDA_FILENAME="Miniconda3-py38_4.11.0-Linux-x86_64.sh"
CONDA_INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-py38_4.11.0-Linux-x86_64.sh"
CONDA_SHA256SUM="4bb91089ecc5cc2538dece680bfe2e8192de1901e5e420f63d4e78eb26b0ac1a"
CONDA_INSTALLER=$(mktemp --suffix ".$CONDA_FILENAME")

WEBMAP_NAME="FTH-webmap-linux"
WEBMAP_VERSION="0.2.5"
WEBMAP_FILENAME="/tmp/$WEBMAP_NAME-$WEBMAP_VERSION.zip"
WEBMAP_EXECUTABLE="/tmp/$WEBMAP_NAME-$WEBMAP_VERSION"
WEBMAP_URL="https://github.com/FreeTAKTeam/FreeTAKHub/releases/download/v$WEBMAP_VERSION/$WEBMAP_NAME-$WEBMAP_VERSION.zip"
WEBMAP_SHA256SUM="11afcde545cc4c2119c0ff7c89d23ebff286c99c6e0dfd214eae6e16760d6723"
WEBMAP_INSTALL_DIR="/usr/local/bin"
WEBMAP_CONFIG_FILE="/tmp/webMAP_config.json"

FTS_PACKAGE="FreeTAKServer"
FTS_UI_PACKAGE="freetakserver-ui==1.9.8"

USER_EXEC="sudo -i -u $SUDO_USER"
UNIT_FILES_DIR="/lib/systemd/system"

###############################################################################
# fts yaml file
###############################################################################
function create_fts_yaml() {
  FTS_YAML_FILE=$(
    cat <<-END
System:
  #FTS_DATABASE_TYPE: SQLite
  FTS_CONNECTION_MESSAGE: Welcome to FreeTAKServer {MainConfig.version}. The Parrot is not dead. It's just resting
  #FTS_OPTIMIZE_API: True
  #FTS_MAINLOOP_DELAY: 1
Addresses:
  #FTS_COT_PORT: 8087
  #FTS_SSLCOT_PORT: 8089
  FTS_DP_ADDRESS: $IPV4
  FTS_USER_ADDRESS: $IPV4
  #FTS_API_PORT: 19023
  #FTS_FED_PORT: 9000
  #FTS_API_ADDRESS: $IPV4
FileSystem:
  FTS_DB_PATH: /opt/FreeTAKServer.db
  #FTS_COT_TO_DB: True
  FTS_MAINPATH: $SITEPACKAGES/FreeTAKServer
  #FTS_CERTS_PATH: $SITEPACKAGES/FreeTAKServer/certs
  #FTS_EXCHECK_PATH: $SITEPACKAGES/FreeTAKServer/ExCheck
  #FTS_EXCHECK_TEMPLATE_PATH: $SITEPACKAGES/FreeTAKServer/ExCheck/template
  #FTS_EXCHECK_CHECKLIST_PATH: $SITEPACKAGES/FreeTAKServer/ExCheck/checklist
  #FTS_DATAPACKAGE_PATH: $SITEPACKAGES/FreeTAKServer/FreeTAKServerDataPackageFolder
  #FTS_LOGFILE_PATH: $SITEPACKAGES/FreeTAKServer/Logs
Certs:
  #FTS_SERVER_KEYDIR: $SITEPACKAGES/FreeTAKServer/certs/server.key
  #FTS_SERVER_PEMDIR: $SITEPACKAGES/FreeTAKServer/certs/server.pem
  #FTS_TESTCLIENT_PEMDIR: $SITEPACKAGES/FreeTAKServer/certs/Client.pem
  #FTS_TESTCLIENT_KEYDIR: $SITEPACKAGES/FreeTAKServer/certs/Client.key
  #FTS_UNENCRYPTED_KEYDIR: $SITEPACKAGES/FreeTAKServer/certs/server.key.unencrypted
  #FTS_SERVER_P12DIR: $SITEPACKAGES/FreeTAKServer/certs/server.p12
  #FTS_CADIR: $SITEPACKAGES/FreeTAKServer/certs/ca.pem
  #FTS_CAKEYDIR: $SITEPACKAGES/FreeTAKServer/certs/ca.key
  #FTS_FEDERATION_CERTDIR: $SITEPACKAGES/FreeTAKServer/certs/server.pem
  #FTS_FEDERATION_KEYDIR: $SITEPACKAGES/FreeTAKServer/certs/server.key
  #FTS_CRLDIR: $SITEPACKAGES/FreeTAKServer/certs/FTS_CRL.json
  #FTS_FEDERATION_KEYPASS: demopassfed
  #FTS_CLIENT_CERT_PASSWORD: demopasscert
  #FTS_WEBSOCKET_KEY: YourWebsocketKey
END
  )

}
###############################################################################
# SUPPORTED OS VARIABLES
###############################################################################
declare SUPPORTED_OS=(
  "ubuntu 20.04"
)

###############################################################################
# SYSTEM VARIABLES
###############################################################################
SYSTEM_NAME=$(uname)
SYSTEM_DIST="Unknown"
SYSTEM_DIST_BASED_ON="Unknown"
SYSTEM_PSEUDO_NAME="Unknown"
SYSTEM_VERSION="Unknown"
SYSTEM_ARCH=$(uname -m)
SYSTEM_ARCH_NAME="Unknown" # {i386, amd64, arm64}
SYSTEM_KERNEL=$(uname -r)
SYSTEM_CONTAINER="false"
CLOUD_PROVIVDER="false"

###############################################################################
# Functions for console output
###############################################################################

newline() { printf "\n"; }

# go "up" one line in the terminal
go_up() { echo -en "\033[${1}A"; }

# clear the line in the terminal
# helpful for changing progress status
_clear() { echo -en "\033[K"; }

# commonly combined functions
clear() {
  go_up 1
  _clear
}

progress_clear() {
  clear
  progress "${1}" "${2}"
}

###############################################################################
# Print out helpful message.
# Outputs:
#   Writes usage message to stdout
###############################################################################
function usage() {
  cat <<USAGE_TEXT
Usage: $(basename "${BASH_SOURCE[0]:-}") [<optional-arguments>]

Install Free TAK Server and components.

Available options:

-h, --help       Print help
-v, --verbose    Print script debug info
-a, --ansible    Install with ansible
-l, --log        Create fts.log to log installation (in running directory)
    --local      Use localhost (default is public ip)
USAGE_TEXT
  exit
}

###############################################################################
# Setup the log
###############################################################################
function setup_log() {

  exec 3>&1 4>&2
  trap 'exec 2>&4 1>&3' 0 1 2 3
  exec 1>fts.log 2>&1
  # TODO: tail -f fts.log

}

###############################################################################
# Cleanup here
###############################################################################
function cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # _cleanup
  die
}

function _cleanup() {
  rm -f "${CONDA_INSTALLER}"
  rm -f "${WEBMAP_ZIP}"
}

###############################################################################
# Get my public ip
###############################################################################
function get_public_ip() {

  if [[ -n "${LOCALHOST-}" ]]; then
    IP_ARG="-i localhost"
  fi

}

###############################################################################
# Interrupt Cleanup
###############################################################################
function ctrl_c() {
  trap - INT

  # _cleanup

  printf "\b\b"

  # clear line
  progress WARN "interrupted installation"

  die "" 1
}

###############################################################################
# Echo a message
###############################################################################
function msg() {
  echo -e "${1:-}" >&2
}

###############################################################################
# Exit gracefully
###############################################################################
function die() {

  # default exit status 0
  local -i code=${2:-0}
  local msg=${1:-"exiting"}

  if [ $code -ne 0 ]; then
    progress FAIL "$msg"
  fi

  exit 0
}

###############################################################################
# STATUS VARIABLES
###############################################################################
EXIT_SUCCESS=0
EXIT_FAILURE=1

declare -A STATUS_COLOR=(
  [DONE]=${GREEN-}
  [FAIL]=${RED-}
  [INFO]=${FOREGROUND-}
  [WARN]=${YELLOW-}
  [BUSY]=${YELLOW-}
  [EXIT]=${FOREGROUND-}
)

declare -A STATUS_TEXT=(
  [DONE]=" DONE "
  [FAIL]=" FAIL "
  [INFO]=" INFO "
  [WARN]=" WARN "
  [BUSY]=" BUSY "
  [EXIT]=" EXIT "
)

function progress() {

  echo -e "[  ${STATUS_COLOR[$1]}${STATUS_TEXT[$1]}${NOFORMAT}  ] ${2}"

}

###############################################################################
# Parse parameters
###############################################################################
function parse_params() {

  # setup console colors
  color

  while true; do
    case "${1-}" in

    --ansible | -a)
      ANSIBLE=1
      shift
      ;;

    --help | -h)
      usage
      exit 0
      shift
      ;;

    --log | -l)
      no_color
      setup_log
      set -x
      shift
      ;;

    --no-color)
      no_color
      shift
      ;;

    --verbose | -v)
      no_color
      set -x
      shift
      ;;

    -?*)
      die "FAIL: unknown option $1"
      ;;

    *)
      break
      ;;

    esac
  done

}

function color() {
  FOREGROUND="\033[39m"
  NOFORMAT="\033[0m"
  RED="\033[1;31m"
  GREEN="\033[1;32m"
  YELLOW='\033[1;33m'
  BLUE='\033[1;34m'
}

function no_color() {
  unset FOREGROUND
  unset NOFORMAT
  unset RED
  unset GREEN
  unset YELLOW
  unset BLUE
}

###############################################################################
# Check if script was ran as root. This script requires root execution.
###############################################################################
function check_root() {
  progress BUSY "checking if user is root"

  # check Effective User ID (EUID) for root user, which has an EUID of 0.
  if [[ "$EUID" -ne 0 ]]; then
    progress_clear FAIL "This script requires running as root. Use sudo before the command."
    exit ${EXIT_FAILURE}
  fi
  progress_clear DONE "checking if user is root"
}

function identify_cloud() {

  if dmidecode --string "bios-vendor" | grep -iq "digitalocean"; then # DigitalOcean
    CLOUD_PROVIDER="digitalocean"
  elif dmidecode -s bios-version | grep -iq "amazon"; then # Amazon Web Services
    CLOUD_PROVIDER="amazon"
  elif dmidecode -s system-manufacturer | grep -iq "microsoft corporation"; then # Microsoft Azure
    CLOUD_PROVIDER="azure"
  elif dmidecode -s bios-version | grep -iq "google"; then # Google Cloud Platform
    CLOUD_PROVIDER="google"
  elif dmidecode -s bios-version | grep -iq "ovm"; then # Oracle Cloud Infrastructure
    CLOUD_PROVIDER="oracle"
  fi

}

function identify_docker() {

  # Detect if inside Docker
  if grep -iq docker /proc/1/cgroup 2 || head -n 1 /proc/1/sched 2 | grep -Eq '^(bash|sh) ' || [ -f /.dockerenv ]; then
    SYSTEM_CONTAINER="true"
  fi

}

###############################################################################
# Check for supported system and warn user if not supported.
###############################################################################
function identify_system() {

  progress BUSY "identifying system attributes"

  if uname -s | grep -iq "darwin"; then # Detect macOS
    SYSTEM_NAME="unix"
    SYSTEM_DIST="macos"
    SYSTEM_DIST_BASED_ON="bsd"
    sw_vers -productVersion | grep -q 10.10 && SYSTEM_PSEUDO_NAME="Yosemite"
    sw_vers -productVersion | grep -q 10.11 && SYSTEM_PSEUDO_NAME="El Capitan"
    sw_vers -productVersion | grep -q 10.12 && SYSTEM_PSEUDO_NAME="Sierra"
    sw_vers -productVersion | grep -q 10.13 && SYSTEM_PSEUDO_NAME="High Sierra"
    sw_vers -productVersion | grep -q 10.14 && SYSTEM_PSEUDO_NAME="Mojave"
    sw_vers -productVersion | grep -q 10.15 && SYSTEM_PSEUDO_NAME="Catalina"
    sw_vers -productVersion | grep -q 11. && SYSTEM_PSEUDO_NAME="Big Sur"
    sw_vers -productVersion | grep -q 12. && SYSTEM_PSEUDO_NAME="Monterey"
    SYSTEM_VERSION=$(sw_vers -productVersion)
    SYSTEM_ARCH_NAME="i386"
    uname -m | grep -q "x86_64" && SYSTEM_ARCH_NAME="amd64"
    uname -m | grep -q "arm" && SYSTEM_ARCH_NAME="arm64"

  elif [ -f /etc/debian_version ]; then # Detect Debian family
    id="$(grep "^ID=" /etc/os-release | awk -F= '{ print $2 }')"
    SYSTEM_DIST="$id"
    if [ "$SYSTEM_DIST" = "debian" ]; then
      SYSTEM_PSEUDO_NAME=$(grep "^VERSION=" /etc/os-release | awk -F= '{ print $2 }' | grep -oEi '[a-z]+')
      SYSTEM_VERSION=$(cat /etc/debian_version)
    elif [ "$SYSTEM_DIST" = "ubuntu" ]; then
      SYSTEM_PSEUDO_NAME=$(grep '^DISTRIB_CODENAME' /etc/lsb-release | awk -F= '{ print $2 }')
      SYSTEM_VERSION=$(grep '^DISTRIB_RELEASE' /etc/lsb-release | awk -F= '{ print $2 }')
    elif [ "$SYSTEM_DIST" = "kali" ]; then
      SYSTEM_PSEUDO_NAME=$(grep "^PRETTY_NAME=" /etc/os-release | awk -F= '{ print $2 }' | sed s/\"//g | awk '{print $NF}')
      SYSTEM_VERSION=$(grep "^VERSION=" /etc/os-release | awk -F= '{ print $2 }' | sed s/\"//g)
    fi
    SYSTEM_DIST_BASED_ON="debian"
    SYSTEM_ARCH_NAME="i386"
    uname -m | grep -q "64" && SYSTEM_ARCH_NAME="amd64"
    { uname -m | grep -q "arm[_]*64" || uname -m | grep -q "aarch64"; } && SYSTEM_ARCH_NAME="arm64"

  elif [ -f /etc/redhat-release ]; then # Detect RedHat family
    SYSTEM_DIST=$(sed s/\ release.*// /etc/redhat-release | tr "[:upper:]" "[:lower:]")
    echo "$SYSTEM_DIST" | grep -q "red" && SYSTEM_DIST="redhat"
    echo "$SYSTEM_DIST" | grep -q "centos" && SYSTEM_DIST="centos"
    SYSTEM_DIST_BASED_ON="redhat"
    SYSTEM_PSEUDO_NAME=$(sed s/.*\(// /etc/redhat-release | sed s/\)//)
    SYSTEM_VERSION=$(sed s/.*release\ // /etc/redhat-release | sed s/\ .*//)
    SYSTEM_ARCH_NAME="i386"
    uname -m | grep -q "64" && SYSTEM_ARCH_NAME="amd64"
    { uname -m | grep -q "arm[_]*64" || uname -m | grep -q "aarch64"; } && SYSTEM_ARCH_NAME="arm64"

  elif which apk; then # Detect Alpine
    SYSTEM_DIST="alpine"
    SYSTEM_DIST_BASED_ON="alpine"
    SYSTEM_PSEUDO_NAME=
    SYSTEM_VERSION=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' /etc/alpine-release)
    SYSTEM_ARCH_NAME="i386"
    uname -m | grep -q "64" && SYSTEM_ARCH_NAME="amd64"
    { uname -m | grep -q "arm[_]*64" || uname -m | grep -q "aarch64"; } && SYSTEM_ARCH_NAME="arm64"

  elif which busybox; then # Detect Busybox
    SYSTEM_DIST="busybox"
    SYSTEM_DIST_BASED_ON="busybox"
    SYSTEM_PSEUDO_NAME=
    SYSTEM_VERSION=$(busybox | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    SYSTEM_ARCH_NAME="i386"
    uname -m | grep -q "64" && SYSTEM_ARCH_NAME="amd64"
    { uname -m | grep -q "arm[_]*64" || uname -m | grep -q "aarch64"; } && SYSTEM_ARCH_NAME="arm64"

  elif grep -iq "amazon linux" /etc/os-release 2; then # Detect Amazon Linux
    SYSTEM_DIST="amazon"
    SYSTEM_DIST_BASED_ON="redhat"
    SYSTEM_PSEUDO_NAME=
    SYSTEM_VERSION=$(grep "^VARIANT_ID=" /etc/os-release | awk -F= '{ print $2 }' | sed s/\"//g)
    [ -z "$SYSTEM_VERSION" ] && SYSTEM_VERSION=$(grep "^VERSION_ID=" /etc/os-release | awk -F= '{ print $2 }' | sed s/\"//g)
    SYSTEM_ARCH_NAME="i386"
    uname -m | grep -q "64" && SYSTEM_ARCH_NAME="amd64"
    { uname -m | grep -q "arm[_]*64" || uname -m | grep -q "aarch64"; } && SYSTEM_ARCH_NAME="arm64"
  fi

  # make vars lowercase
  SYSTEM_NAME=$(echo "$SYSTEM_NAME" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  SYSTEM_DIST=$(echo "$SYSTEM_DIST" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  SYSTEM_DIST_BASED_ON=$(echo "$SYSTEM_DIST_BASED_ON" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  SYSTEM_PSEUDO_NAME=$(echo "$SYSTEM_PSEUDO_NAME" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  SYSTEM_VERSION=$(echo "$SYSTEM_VERSION" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  SYSTEM_ARCH=$(echo "$SYSTEM_ARCH" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  SYSTEM_ARCH_NAME=$(echo "$SYSTEM_ARCH_NAME" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  SYSTEM_KERNEL=$(echo "$SYSTEM_KERNEL" | tr "[:upper:]" "[:lower:]" | tr " " "_")
  # echo "SYSTEM_CONTAINER=$(echo "$SYSTEM_CONTAINER" | tr "[:upper:]" "[:lower:]" | tr " " "_")"

  # echo "SYSTEM_NAME=$SYSTEM_NAME"
  # echo "SYSTEM_DIST=$SYSTEM_DIST"
  # echo "SYSTEM_DIST_BASED_ON=$SYSTEM_DIST_BASED_ON"
  # echo "SYSTEM_PSEUDO_NAME=$SYSTEM_PSEUDO_NAME"
  # echo "SYSTEM_VERSION=$SYSTEM_VERSION"
  # echo "SYSTEM_ARCH=$SYSTEM_ARCH"
  # echo "SYSTEM_ARCH_NAME=$SYSTEM_ARCH_NAME"
  # echo "SYSTEM_KERNEL=$SYSTEM_KERNEL"
  # echo "CLOUD_PROVIVDER=$(echo "$CLOUD_PROVIVDER" | tr "[:upper:]" "[:lower:]" | tr " " "_")"

  # iterate through supported operating systems
  local is_supported=false

  for candidate_os in "${SUPPORTED_OS[@]}"; do
    if [[ "$SYSTEM_DIST $SYSTEM_VERSION" = "$candidate_os" ]]; then
      is_supported=true
    fi
  done

  if [ $is_supported = false ]; then
    echo -e "${YELLOW}WARNING${NOFORMAT}"
    echo -e "running"
    echo -e "This machine is currently running: ${YELLOW}${OS} ${VER}${NOFORMAT}"
    echo "Errors may arise during installation or execution."
  fi

  # # check for supported OS and version and warn if not supported
  # if [[ "${SYSTEM_NAME} ${SYSTEM_VERSION}" != "Ubuntu" ]] || [[ "${VER}" != "20.04" ]]; then

  #   read -r -e -p "Do you want to continue? [y/n]: " PROCEED

  #   # Default answer is "n" for NO.
  #   DEFAULT="n"

  #   # Set user-inputted value and apply default if user input is null.
  #   PROCEED="${PROCEED:-${DEFAULT}}"

  #   # Check user input to proceed or not.
  #   if [[ "${PROCEED}" != "y" ]]; then
  #     die "Answer was not y. Not proceeding."
  #   else
  #     echo -e "${GREEN}Proceeding...${NOFORMAT}"
  #   fi

  # else

  #   echo -e "${GREEN}Success!${NOFORMAT}"
  #   echo -e "This machine is currently running: ${GREEN}${OS} ${VER}${NOFORMAT}"

  # fi

  progress_clear DONE "identifying system attributes"
}

###############################################################################
# Check for supported architecture
###############################################################################
function check_architecture() {

  progress BUSY "checking for supported architecture"

  # check for non-Intel-based architecture here
  arch=$(uname --hardware-platform) # uname is non-portable, but we only target Ubuntu 20.04
  if ! grep --ignore-case x86 <<<"${arch}"; then

    echo "Possible non-Intel architecture detected, ${name}"
    echo "Non-intel architectures may cause problems. The web map might not install."

    read -r -e -p "Do you want to force web map installation? [y/n]: " USER_INPUT

    # Default answer is "n" for NO.
    DEFAULT="n"

    # Set user-inputted value and apply default if user input is null.
    FORCE_WEBMAP_INSTALL_INPUT="${USER_INPUT:-${DEFAULT}}"

    # Check user input to force install web map or not
    if [[ "${FORCE_WEBMAP_INSTALL_INPUT}" != "y" ]]; then
      echo -e "${YELLOW}WARNING${NOFORMAT}: installer may skip web map installation."
    else
      WEBMAP_FORCE_INSTALL="-e webmap_force_install=true"
      echo -e "${YELLOW}WARNING${NOFORMAT}: forcing web map installation!"
    fi

  else # good architecture to install webmap
    echo -e "${GREEN}Success!${NOFORMAT}"
    echo "Intel architecture detected, ${name}"

  fi

  progress_clear DONE "checking for supported architecture"
}

###############################################################################
# check sha256sum
###############################################################################
function check_file_integrity() {

  local checksum=$1
  local file=$2

  progress BUSY "checking file integrity of ${file}"
  SHA256SUM_RESULT=$(printf "%s %s" "$checksum" "$file" | sha256sum -c)

  if [ "${SHA256SUM_RESULT}" = "${file}: OK" ]; then
    progress_clear DONE "checking file integrity"
  else
    progress_clear FAIL "sha256sum check failed: ${file}"
    exit $EXIT_FAILURE
  fi

}

###############################################################################
# setup miniconda virtual environment
###############################################################################
function setup_virtual_environment() {

  # get the home directory of user that ran this script
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  CONDA_INSTALL_DIR="$USER_HOME/conda"

  progress BUSY "downloading miniconda"
  wget $CONDA_INSTALLER_URL -qO "$CONDA_INSTALLER"
  # todo: print out result when verbose
  progress_clear DONE "downloading miniconda"

  check_file_integrity "$CONDA_SHA256SUM" "$CONDA_INSTALLER"

  progress BUSY "setting up virtual environment"

  # create conda install directory
  mkdir -p "$CONDA_INSTALL_DIR"

  # install conda
  bash "$CONDA_INSTALLER" -u -b -p "$CONDA_INSTALL_DIR"

  # configure conda
  conda config --set auto_activate_base true --set always_yes yes --set changeps1 yes

  # create group and add user to it
  groupadd -f "$GROUP_NAME"

  # add user to newly created group
  usermod -a -G "$GROUP_NAME" "$SUDO_USER"

  # set permissions
  chgrp "$GROUP_NAME" "/usr/local/bin"

  # symlink conda executable
  ln -sf "$CONDA_INSTALL_DIR/bin/conda" "/usr/local/bin/conda"

  CONDA="conda"
  CONDA_RUN="conda run -n $VENV_NAME"
  CONDA_SCRIPTS="$CONDA_PREFIX/etc/profile.d"

  # shellcheck source="$CONDA_INSTALL_DIR/etc/profile.d/conda.sh"
  source "$CONDA_INSTALL_DIR/etc/profile.d/conda.sh"

  # update conda
  $CONDA update --yes --name base conda

  # create virtual environment
  $CONDA create --name "$VENV_NAME" python="$PYTHON_VERSION"

  # activate virtual environment
  conda init bash
  eval "$(conda shell.bash hook)"
  conda activate "$VENV_NAME"

  # set conda variables
  PYTHON_EXEC=$($CONDA_RUN which python${PYTHON_VERSION})
  SITEPACKAGES="$CONDA_INSTALL_DIR/lib/python${PYTHON_VERSION}/site-packages"

  # ensure permissions after activate
  chown -R "$SUDO_USER":"$GROUP_NAME" "$CONDA_INSTALL_DIR"

  progress_clear DONE "setting up virtual environment"

}

###############################################################################
# setup a service (used for autostarting on login)
###############################################################################
function setup_service() {

  local name=$1
  local command=$2

  # create launch script
  cat >"${name}.sh" <<EOL
#!/bin/bash

source $CONDA_INSTALL_DIR/etc/profile.d/conda.sh
conda activate $VENV_NAME
$command
EOL

  # create unit file
  cat >"${name}.service" <<EOL
[Unit]
Description=${name} service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=${CONDA_SCRIPTS}/${name}.sh

[Install]
WantedBy=multi-user.target
EOL

  chown -R "$SUDO_USER":"$GROUP_NAME" "${name}.service"
  chown -R "$SUDO_USER":"$GROUP_NAME" "${name}.sh"
  chgrp "$GROUP_NAME" "$UNIT_FILES_DIR"
  chgrp "$GROUP_NAME" "$CONDA_SCRIPTS"

  mv -f "${name}.sh" "$CONDA_SCRIPTS/${name}.sh"
  mv -f "${name}.service" "$UNIT_FILES_DIR/${unit_file}.service"

  enable_and_start_service "$name" "${name}.service"

}

###############################################################################
# Enable systemctl services to execute on startup
###############################################################################
function enable_and_start_service() {

  local name="$1"
  local unit_file="$2"

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable "$name"

}

###############################################################################
# Handle git repository
###############################################################################
function handle_git_repository() {

  cd ~

  # check for FreeTAKHub-Installation repository
  if [[ ! -d ~/FreeTAKHub-Installation ]]; then
    $CONDA_RUN git clone ${REPO}
    cd ~/FreeTAKHub-Installation
  else
    cd ~/FreeTAKHub-Installation
    $CONDA_RUN git pull
  fi

}

###############################################################################
# Run Ansible playbook to install
###############################################################################
function run_playbook() {

  $CONDA install --name "$VENV_NAME" --channel conda-forge ansible

  EXTRA_VARS=-e "CONDA_PREFIX=$CONDA_PREFIX" -e "VENV_NAME=$VENV_NAME"
  if [[ -n "${ANSIBLE-}" ]]; then
    $CONDA_RUN ansible-playbook -u "$SUDO_USER", "$IP_ARG", --connection=local "$EXTRA_VARS" install_mainserver.yml -vvv
  else
    $CONDA_RUN ansible-playbook -u "$SUDO_USER", "$IP_ARG", --connection=local "$EXTRA_VARS" install_all.yml -vvv
  fi
}

function replace() {
  local file=$1
  local search=$2
  local replace=$3
  sed -i "s/$search/$replace/g" "$file"

}

###############################################################################
# Install FTS via shell
###############################################################################
function fts_shell_install() {

  progress BUSY "setting up fts"

  $USER_EXEC $CONDA install --name "$VENV_NAME" unzip

  if [[ ! -d "$CONDA_PREFIX/$REPO_FTS" ]]; then
    $USER_EXEC $CONDA_RUN git clone "$FREETAKTEAM_BASE/$REPO_FTS" "$CONDA_PREFIX/$REPO_FTS"
  else
    cd "$CONDA_PREFIX/$REPO_FTS" && $CONDA_RUN git pull
  fi

  $USER_EXEC $CONDA_RUN python "$CONDA_PREFIX/$REPO_FTS/setup.py install"

  # change first start in MainConfig.py to false
  local search="    first_start = True"
  local replace="    first_start = False"
  replace "$SITEPACKAGES/controllers/configuration/MainConfig.py" "$search" "$replace"

  $USER_EXEC $CONDA_RUN pip3 install "$FTS_UI_PACKAGE"

  # configure FTS
  create_fts_yaml
  cat >"/tmp/FTSConfig.yaml" <<EOL
$FTS_YAML_FILE
EOL

  chgrp "$GROUP_NAME" "/tmp/FTSConfig.yaml"
  mv -f "/tmp/FTSConfig.yaml" "/opt/FTSConfig.yaml"

  progress_clear DONE "setting up fts"

  progress BUSY "setting up webmap"
  wget $WEBMAP_URL -qO "$WEBMAP_FILENAME"
  check_file_integrity "$WEBMAP_SHA256SUM" "$WEBMAP_FILENAME"
  progress_clear DONE "setting up webmap"

  progress BUSY "setting up webmap"

  # unzip webmap
  chmod 777 "$WEBMAP_FILENAME"
  $CONDA_RUN unzip -o "$WEBMAP_FILENAME" -d /tmp

  # remove version string in webmap executable
  mv -f "$WEBMAP_EXECUTABLE" "$WEBMAP_NAME"

  chgrp "$GROUP_NAME" "$WEBMAP_NAME"
  mv -f "$WEBMAP_NAME" "$WEBMAP_INSTALL_DIR/$WEBMAP_NAME"

  # configure ip in webMAP_config.json
  local search="\"FTH_FTS_URL\": \"204.48.30.216\","
  local replace="\"FTH_FTS_URL\": \"$IPV4\","
  replace "$WEBMAP_CONFIG_FILE" "$search" "$replace"

  chgrp "$GROUP_NAME" "$WEBMAP_CONFIG_FILE"
  mv -f "$WEBMAP_CONFIG_FILE" "/opt/$WEBMAP_CONFIG_DESTINATION"
  progress_clear DONE "setting up webmap"

  progress BUSY "configuring fts to autostart"

  local startup_command="$PYTHON_EXEC -m FreeTAKServer.controllers.services.FTS"
  setup_service "fts" "$startup_command"
  progress_clear DONE "setting up fts"

}

###############################################################################
# Install using shell script or ansible (default is shell)
###############################################################################
function install_fts() {

  if [[ -n "${ANSIBLE-}" ]]; then
    handle_git_repository
    run_playbook
  else
    fts_shell_install
  fi
}

###############################################################################
# MAIN BUSINESS LOGIC HERE
###############################################################################
start=$(date +%s)
parse_params "$@"
check_root
# identify_system
# identify_cloud
# identify_docker
setup_virtual_environment
# get_public_ip
install_fts

# systemctl start "${name}.service"
end=$(date +%s)
progress DONE "SUCCESS! Installed in $((end - start))s."
