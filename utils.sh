#!/usr/bin/env bash
# Utility bash functions

# Check bash version
if [[ ${BASH_VERSINFO[0]} < 5 && (${BASH_VERSINFO[0]} < 4 || ${BASH_VERSINFO[1]} < 1) ]]; then
  echo "bash 4.1 or later required"
  exit 255
fi

getOutputFolder()
{
	local _retval="$1"
	local basePath="$2"
	local arch="$3"
	local toolset="$4"
	local config="$5"
	local result=""

	if isMac; then
		result="${basePath}_${arch}"
	elif isWindows; then
		result="${basePath}_${arch}_${toolset}"
	else
		result="${basePath}_${arch}_${config}"
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

getCcArch()
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

	eval $_retval="'$($ccCommand -dumpmachine)'"
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

