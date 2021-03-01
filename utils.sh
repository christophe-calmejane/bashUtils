#!/usr/bin/env bash
# Utility bash functions

# Check bash version
if [[ ${BASH_VERSINFO[0]} < 5 && (${BASH_VERSINFO[0]} < 4 || ${BASH_VERSINFO[1]} < 3) ]]; then
  echo "bash 4.3 or later required"
  exit 255
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
		Xcode)
			result="xcode"
			;;
		"Visual Studio "*)
			result="vs"
			;;
		*)
			result="${generator}"
			exit 4
			;;
	esac

	eval $_retval="'${result}'"
}

isSingleConfigurationGenerator()
{
	local generator="$1"
	if [[ "$generator" == "Unix Makefiles" || "$generator" == "Ninja" ]]; then
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

	if isMac;
	then
		result=$(stat -f%z "$filePath")
	else
		result=$(stat -c%s "$filePath")
	fi

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
			if [[ `uname -r` == *"Microsoft"* ]]; then
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

