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
			result="${generator}"
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
			local regex="*[Mm]icrosoft*"
			if [[ `uname -r` == $regex ]]; then
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
				grep --version | grep -i GNU &> /dev/null
				if [ $? -ne 0 ];
				then
					echo "GNU grep required (not macOS native grep version). Install it via HomeBrew:"
					printBrewInstallHelp "grep" "grep"
					exit 127
				fi
			fi
		done
	fi
}

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

vscode_append_build_task()
{
	local workspace_file_path="$1"
	local build_folder="$2"
	local build_config="$3"
	local is_default=$4

	echo "				\"label\": \"Build $build_config\"," >> "$workspace_file_path"
	echo "				\"type\": \"shell\"," >> "$workspace_file_path"
	echo "				\"command\": \"cmake --build $build_folder --config $build_config\"," >> "$workspace_file_path"
	if isWindows; then
		echo "				\"problemMatcher\": [\"\$msCompile\"]," >> "$workspace_file_path"
	fi
	if [ $is_default -eq 1 ]; then
		echo "				\"group\": {" >> "$workspace_file_path"
		echo "					\"kind\": \"build\"," >> "$workspace_file_path"
		echo "					\"isDefault\": true," >> "$workspace_file_path"
		echo "				}," >> "$workspace_file_path"
	else
		echo "				\"group\": \"build\"", >> "$workspace_file_path"
	fi
	echo "				\"presentation\": {" >> "$workspace_file_path"
	echo "					\"reveal\": \"always\"," >> "$workspace_file_path"
	echo "					\"focus\": false," >> "$workspace_file_path"
	echo "					\"panel\": \"shared\"," >> "$workspace_file_path"
	echo "					\"clear\": true" >> "$workspace_file_path"
	echo "				}" >> "$workspace_file_path"
}

generate_vscode_workspace()
{
	local project_name="$1"
	local build_folder="$2"
	local build_config="$3"
	local workspace_file_path="${build_folder}/${project_name}.code-workspace"

	# Start a workspace file
	echo "{" > "$workspace_file_path"

	# Settings
	echo "	\"settings\": {" >> "$workspace_file_path"
	# Exclude files
	echo "		\"files.exclude\": {" >> "$workspace_file_path"
	echo "			\"**/.git\": true," >> "$workspace_file_path"
	echo "			\"**/.vscode\": true," >> "$workspace_file_path"
	echo "			\"**/_*\": true," >> "$workspace_file_path"
	echo "			\"**/.DS_Store\": true," >> "$workspace_file_path"
	echo "			\"**/Thumbs.db\": true" >> "$workspace_file_path"
	echo "		}" >> "$workspace_file_path"
	echo "	}," >> "$workspace_file_path"

	# Add folders
	echo "	\"folders\": [" >> "$workspace_file_path"
	echo "		{" >> "$workspace_file_path"
	echo "			\"path\": \"..\"" >> "$workspace_file_path"
	echo "		}," >> "$workspace_file_path"
	echo "		{" >> "$workspace_file_path"
	echo "			\"path\": \".\"" >> "$workspace_file_path"
	echo "		}" >> "$workspace_file_path"
	echo "	]," >> "$workspace_file_path"

	# Add build tasks
	echo "	\"tasks\": {" >> "$workspace_file_path"
	echo "		\"version\": \"2.0.0\"," >> "$workspace_file_path"
	echo "		\"tasks\": [" >> "$workspace_file_path"
	# If build config is not specified, this is a multi-config project
	if [ -z "$build_config" ]; then
		echo "			{" >> "$workspace_file_path"
		vscode_append_build_task "$workspace_file_path" "$build_folder" "Debug" 1
		echo "			}," >> "$workspace_file_path"
		echo "			{" >> "$workspace_file_path"
		vscode_append_build_task "$workspace_file_path" "$build_folder" "Release" 0
		echo "			}" >> "$workspace_file_path"
	else
		# If build config is specified, this is a single-config project
		echo "			{" >> "$workspace_file_path"
		vscode_append_build_task "$workspace_file_path" "$build_folder" "$build_config" 1
		echo "			}" >> "$workspace_file_path"
	fi
	echo "		]" >> "$workspace_file_path"
	echo "	}" >> "$workspace_file_path"

	# End workspace file
	echo "}" >> "$workspace_file_path"
}
