#!/usr/bin/env bash
# Utility bash functions

# Check bash version
if [[ ${BASH_VERSINFO[0]} < 5 && (${BASH_VERSINFO[0]} < 4 || ${BASH_VERSINFO[1]} < 3) ]]; then
  echo "bash 4.4 or later required"
  exit 255
fi

# Prevent MSYS from automatically converting paths to Windows format
if [ $OSTYPE == "msys" ]; then
	export MSYS_NO_PATHCONV=1
fi

# Parses an options file and fill an array with all options found.
# parseFile <file path> <list of allowed options> <associative array to be filled, possibly pre-initialized with default values>
#
# Options in the file must be in the format key=value
# Lines starting with a # are comment lines and ignored
#
# Ex:
# declare -A params=()
# declare -a knownOptions=("opt1" "opt2")
# params["opt1"]="" # Default value empty
# params["opt2"]="My Default" # Default value set
# parseFile "${configFile}" knownOptions[@] params
parseFile()
{
	local configFile="$1"
	declare -a allowedOptions=("${!2}")
	declare -n _params="$3"

	if [ ! -f "$configFile" ]; then
		return
	fi

	while IFS=$'\r\n' read -r -a line || [ -n "$line" ]; do
		# Only process lines with something
		if [ "${line}" != "" ]; then
			IFS='=' read -a lineSplit <<< "${line}"

			local key="${lineSplit[0]}"
			local value="${lineSplit[1]}"

			# Don't parse commented lines
			if [ "${key:0:1}" = "#" ]; then
				continue
			fi

			local found=0
			for opt in "${allowedOptions[@]}"
			do
				if [ "$opt" = "$key" ]; then
					_params["$key"]="$value"
					found=1
				fi
			done

			if [ $found -eq 0 ];
			then
				echo "Ignoring unknown key '$key' in '${configFile}' file"
			fi
		fi
	done < "${configFile}"
}

getGeneratorShortName()
{
	local _retval="$1"
	local generator="$2"
	local result=""

	case "$generator" in
		"Unix Makefiles")
			result="makefiles"
			;;
		Ninja)
			result="ninja"
			;;
		Fastbuild)
			result="fastbuild"
			;;
		Xcode)
			result="xcode"
			;;
		"Visual Studio "*)
			result="vs"
			;;
		*)
			echo "Unsupported CMake generator: ${generator}"
			exit 4
			;;
	esac

	eval $_retval="'${result}'"
}

isSingleConfigurationGenerator()
{
	local generator="$1"
	if [[ "$generator" == "Unix Makefiles" || "$generator" == "Ninja" || "$generator" == "Fastbuild" ]]; then
		return 0
	fi
	return 1
}

# Compute a CMake output folder based on OS, arch, toolset, build configuration, generator
getOutputFolder()
{
	local _retval="$1"
	local basePath="$2"
	local os="$3"
	local arch="$4"
	local toolset="$5"
	local config="$6"
	local generator="$7"
	local result=""

	result="${basePath}_${os}_${arch}"

	# Append the generator short name
	local shortName=""
	getGeneratorShortName	shortName "$generator"
	result="${result}_${shortName}"

	# Append the toolset
	if [ ! -z "${toolset}" ]; then
		result="${result}_${toolset}"
	fi

	# For Single-Configuration generators, always append build configuration
	if isSingleConfigurationGenerator "$generator"; then
		result="${result}_${config,,}"
	fi

	eval $_retval="'${result}'"
}

getFileSize()
{
	local filePath="$1"
	local _retval="$2"
	local result=""

	result=$(stat -c%s "$filePath")

	eval $_retval="'${result}'"
}

getFileAbsolutePath()
{
	local _retval="$1"
	local _file_path_name="${2##*/}"
	local _file_path_folder="${2%/*}"
	if [[ "${_file_path_name}" == "${_file_path_folder}" ]]; then # In case the path specified is directly the file name (=empty relative path)
		_file_path_folder="."
	fi
	local _file_path_abs_folder="`cd "${_file_path_folder}"; pwd`/" # Trick to get absolute path

	eval $_retval="'${_file_path_abs_folder}${_file_path_name}'"
}

getFolderAbsolutePath()
{
	local _retval="$1"
	local result="$2"
	
	if [ -d "$2" ]; then
		result="$(cd "$2"; pwd -P)/"
	else
		result="$2"
	fi
	
	eval $_retval="'${result}'"
}

getFolderAbsoluteOSDependantPath()
{
	local _retval="$1"
	local result="$2"
	
	if isCygwin; then
		result="$(cygpath -a -w "$2")\\"
	elif isWindows; then
		result="$({ cd "$2" && pwd -W; } | sed 's|/|\\|g')\\"
	else
		result="$(cd "$2"; pwd -P)/"
	fi
	
	eval $_retval="'${result}'"
}

getExistingFolders()
{
	local _retval="$1"
	local result=""
	local inputList="$2"
	
	for i in $inputList; do
		if [ -d "$i" ]; then
			result="$result $i"
		fi
	done
	
	eval $_retval="'${result}'"
}

isEmptyFolder()
{
	test -e "${1%/*}/"* 2> /dev/null
	case $? in
		1)
			return 0;;
		*)
			return 1;;
	esac
}

isInDocker()
{
	# Check for the presence of the IN_DOCKER_CONTAINER environment variable
	if [ -n "$IN_DOCKER_CONTAINER" ]; then
		return 0
	fi

	# Check for the presence of the /.dockerenv file
	if [ -f "/.dockerenv" ]; then
		return 0
	fi

	# Check for the presence of the /.dockerinit file
	if [ -f "/.dockerinit" ]; then
		return 0
	fi

	# Check for 'docker' or 'lxc' in the cgroup file
	if grep -sq 'docker\|lxc' /proc/1/cgroup; then
		return 0
	fi

	# Not in a Docker container
	return 1
}

getOS()
{
	local _retval="$1"
	local result=""

	case "$OSTYPE" in
		msys)
			result="win"
			;;
		cygwin)
			result="win"
			;;
		darwin*)
			result="mac"
			;;
		linux*)
			# We have to check for WSL
			if isWSL; then
				result="win"
			else
				result="linux"
			fi
			;;
		*)
			echo "ERROR: Unknown OSTYPE: $OSTYPE"
			exit 127
			;;
	esac

	eval $_retval="'${result}'"
}

# Returns 0 if running OS is windows
isWindows()
{
	local osName
	getOS osName
	if [[ $osName = win ]]; then
		return 0
	fi
	return 1
}

# Returns 0 if running OS is mac
isMac()
{
	local osName
	getOS osName
	if [[ $osName = mac ]]; then
		return 0
	fi
	return 1
}

# Returns 0 if running OS is linux
isLinux()
{
	local osName
	getOS osName
	if [[ $osName = linux ]]; then
		return 0
	fi
	return 1
}

# Returns 0 if running OS is cygwin
isCygwin()
{
	if [[ $OSTYPE = cygwin ]]; then
		return 0
	fi
	return 1
}

# Returns 0 if running OS is WSL (but not in a Docker container)
isWSL()
{
	# uname -r outputs the kernel version, which contains "microsoft" if running in WSL(2), currently it is the only way to detect WSL
	# otherwise other elements from uname or OSType will only return linux results,
	# also true when running in a Docker container thus the need to check for that
	if [[ $OSTYPE == linux* ]] && [[ $(uname -r) == *[Mm]icrosoft* ]] && ! isInDocker ; then
		return 0
	fi
	return 1
}

getMachineArch()
{
	local _retval="$1"
	
	if isMac; then
		ccCommand="clang"
	else
		ccCommand="gcc"
	fi
	if [ ! -z "$CC" ]; then
		ccCommand="$CC"
	fi

	local result="$($ccCommand -dumpmachine)"
	result="${result%%-*}"
	case "$result" in
		i386)
			result="x86"
			;;
		i486)
			result="x86"
			;;
		i586)
			result="x86"
			;;
		i686)
			result="x86"
			;;
		x86_64)
			result="x64"
			;;
		arm)
			result="arm"
			;;
		arm64)
			result="arm64"
			;;
		aarch64)
			result="arm64"
			;;
		*)
			echo "Unknown Machine Arch: $result (add support for it in getMachineArch function)"
			exit 1
	esac
	eval $_retval="'${result}'"
}

getUserName()
{
	local _retval="$1"
	local result="$USER"
	
	if [ -z $result ]; then
		result="$USERNAME"
	fi

	eval $_retval="'${result}'"
}

getCommandPath()
{
	local result=$(which "$1" 2> /dev/null)
	if [ -z "$result" ]; then
		echo ""
	else
		echo $result
	fi
}

# Check if specified git ref exists - Returns 0 if it exists
doesRefExist()
{
	git rev-parse --verify "$1" &> /dev/null
}

getCurrentGitRef()
{
	local _retval="$1"
	local result="$(git rev-parse --abbrev-ref HEAD 2>&1)"

	# Check if we are on a detached head
	if [[ $result == HEAD ]]; then
		result="$(git rev-parse --short HEAD 2>&1)"
	fi
	
	eval $_retval="'${result}'"
}

getDeveloperSigningIdentities()
{
	local -n arrayNameRef=$1
	local identityType="$2"
	readarray -t arrayNameRef < <(security find-identity -v -p basic | grep -Po "^[[:space:]]+[0-9]+\)[[:space:]]+[0-9A-Z]+[[:space:]]+\"\K${identityType}: [^(]+\([^)]+\)(?=\")")
}

printBrewInstallHelp()
{
	local moduleName="$1"
	local formula="$2"

	which brew &> /dev/null
	if [ $? -ne 0 ]; then
		echo " - Install HomeBrew with the following command: /usr/bin/ruby -e \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\""
		echo " - Export brew path with the following command: export PATH=\"/usr/local/bin:\$PATH\""
	fi
	echo " - Install $moduleName with the following command: brew install $formula"
	echo " - Export $moduleName path with the following command: export PATH=\"\$(brew --prefix $formula)/libexec/gnubin:\$PATH\""
	echo " - Optionally set this path command in your .bashrc"
}

envSanityChecks()
{
	if [[ ${BASH_VERSINFO[0]} < 5 && (${BASH_VERSINFO[0]} < 4 || ${BASH_VERSINFO[1]} < 3) ]];
	then
		echo "bash 4.3 or later required"
		if isMac;
		then
			echo "Try invoking the script with 'bash $0' instead of just '$0'"
		fi
		exit 127
	fi
	if isMac;
	then
		for module in "$@"
		do
			if [ "$module" == "tar" ];
			then
				which tar &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU tar required. Install it via HomeBrew:"
					printBrewInstallHelp "tar" "gnu-tar"
					exit 127
				fi
				tar --version | grep -i GNU &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU tar required (not macOS native tar version). Install it via HomeBrew:"
					printBrewInstallHelp "tar" "gnu-tar"
					exit 127
				fi
			elif [ "$module" == "grep" ];
			then
				which grep &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU grep required. Install it via HomeBrew:"
					printBrewInstallHelp "grep" "grep"
					exit 127
				fi
				grep --version | grep -i BSD &> /dev/null
				if [ $? -eq 0 ];
				then
					echo "GNU grep required (not macOS native grep version). Install it via HomeBrew:"
					printBrewInstallHelp "grep" "grep"
					exit 127
				fi
			elif [ "$module" == "sed" ];
			then
				which sed &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU sed required. Install it via HomeBrew:"
					printBrewInstallHelp "sed" "gnu-sed"
					exit 127
				fi
				local sedVersion;
				sedVersion=$(sed --version &> /dev/null)
				if [ $? -ne 0 ];
				then
					echo "GNU sed required (not macOS native sed version). Install it via HomeBrew:"
					printBrewInstallHelp "sed" "gnu-sed"
					exit 127
				fi
				echo $sedVersion | grep -i BSD &> /dev/null
				if [ $? -eq 0 ];
				then
					echo "GNU sed required (not macOS native sed version). Install it via HomeBrew:"
					printBrewInstallHelp "sed" "gnu-sed"
					exit 127
				fi
			elif [ "$module" == "stat" ];
			then
				which stat &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU stat required. Install it via HomeBrew:"
					printBrewInstallHelp "stat" "coreutils"
					exit 127
				fi
				stat --version | grep -i GNU &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU stat required (not macOS native stat version). Install it via HomeBrew:"
					printBrewInstallHelp "stat" "coreutils"
					exit 127
				fi
			elif [ "$module" == "awk" ];
			then
				which awk &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU awk required. Install it via HomeBrew:"
					printBrewInstallHelp "gawk" "gawk"
					exit 127
				fi
				awk --version | grep -i GNU &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU awk required (not macOS native awk version). Install it via HomeBrew:"
					printBrewInstallHelp "gawk" "gawk"
					exit 127
				fi
			else
				echo "Unsupported module, please add it: $module"
				exit 127
			fi
		done
	fi
}

# Remove duplicates from an array
removeDuplicates()
{
	local -n sourceArray=$1
	local temp_array=()

	for value in "${sourceArray[@]}";	do
		# Not already added in array
		if [[ ! " ${temp_array[@]} " =~ " ${value} " ]]; then
			temp_array+=("$value")
		fi
	done

	# Copy back to source array
	sourceArray=("${temp_array[@]}")
}

# Get the cmake config Qt path for the current OS, specified Qt arch and Qt version
getQtDir()
{
	# $arch must be defined before calling this function
	local -n _retval="$1"
	local qtBaseInstallPath="$2"
	local qtArchName="$3"
	local qtVersion="$4"

	local qtBasePath=""
	local qtArch=""
	local qtDir=""
	local majorVersion="${qtVersion%%.*}"

	if isWindows; then
		qtBasePath="${qtBaseInstallPath}/${QtVersion}"
		if [ "$arch" == "x64" ]; then
			qtArch="${qtArchName}_64"
		else
			qtArch="${qtArchName}"
		fi
		qtDir="${qtBasePath}/${qtArch}/lib/cmake"
	elif isMac; then
		qtBasePath="${qtBaseInstallPath}/${QtVersion}"
		if [ "${majorVersion}" == "6" ] ; then
			qtArch="macos"
		else
			qtArch="${qtArchName}"
		fi
		qtDir="${qtBasePath}/${qtArch}/lib/cmake"
	elif isLinux; then
		which g++ &> /dev/null
		if [ $? -ne 0 ];
		then
			echo "ERROR: g++ not found"
			exit 4
		fi
		if [ "x${QT_BASE_PATH}" != "x" ]; then
			if [ ! -f "${QT_BASE_PATH}/MaintenanceTool" ]; then
				echo "Invalid QT_BASE_PATH: MaintenanceTool not found in specified folder: ${QT_BASE_PATH}"
				echo "Maybe try the -qtdir option, see help (-h)"
				exit 1
			fi

			qtBasePath="${QT_BASE_PATH}/${QtVersion}"
			# qtArch="" # Maybe use qtArchName as well? (if yes, factorize qtArch for both QT_BASE_PATH and system wide)
			qtDir="${qtBasePath}/cmake"
		else
			qtBasePath="${qtBaseInstallPath}"
			qtArch="${qtArchName}"
			qtDir="${qtBasePath}/${qtArch}/cmake"
		fi
	else
		echo "Unsupported platform"
		exit 1
	fi

	_retval="${qtDir}"
}
