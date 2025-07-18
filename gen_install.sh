#!/usr/bin/env bash
# Useful script to generate an installer of a cmake application project
# Set cmake_opt variable before calling this script to set cmake defines
# Set selfFolderPath variable before calling this script to the absolute path of the calling script
# The following functions can be defined before including this script:
#   extend_gi_fnc_help() -> Called when -h is requested. No return value
#   extend_gi_fnc_defaults() -> Called when default values are initialized. Override default global values from the function. No return value
#     - default_VisualGenerator -> Visual Studio version to use. Default is "Visual Studio 17 2022"
#     - default_VisualToolset -> Visual Studio toolset to use. Default is "v143"
#     - default_VisualToolchain -> Visual Studio toolchain to use. Default is "x64"
#     - default_VisualArch -> Visual Studio target architecture to use. Default is "x86" (legacy parameter, replaced by default_buildArch for all platforms)
#     - default_buildArch -> Default build architecture to use. Default is the host architecture (x86, x64, arm64, etc.)
#     - default_signtoolOptions -> Options for signing binaries. Default is "/a /sm /q /fd sha256 /tr http://timestamp.sectigo.com /td sha256"
#     - default_keyDigits -> The number of digits to be used as Key for installation, comprised between 0 and 4. Default is 2
#     - default_betaTagName -> The tag to use before the 4th digit for beta releases. Default is "-beta"
#   extend_gi_fnc_unhandled_arg() -> Called when an unhandled argument is found. Return the count of consumed args
#   extend_gi_fnc_props_summary() -> Called just before invoking gen_cmake when printing build properties summary. No return value

GI_GeneratorVersion="7.2"

echo "Install Generator version $GI_GeneratorVersion"
echo ""

# Check if selfFolderPath is defined
if [ -z "$selfFolderPath" ]; then
	echo "ERROR: selfFolderPath variable not set. Please set it before calling this script."
	exit 1
fi
# Check if selfFolderPath is absolute
if [[ "$selfFolderPath" != /* ]]; then
	echo "ERROR: selfFolderPath variable is not absolute. Please set it to an absolute path before calling this script."
	exit 1
fi
# Check if selfFolderPath is a directory
if [ ! -d "$selfFolderPath" ]; then
	echo "ERROR: selfFolderPath variable is not a directory. Please set it to an absolute path to a directory before calling this script."
	exit 1
fi
# Locally store selfFolderPath for later use
bu_gi_callerFolderPath="$selfFolderPath"
# Check if bu_gi_callerFolderPath ends with /
if [[ "${bu_gi_callerFolderPath: -1}" != "/" ]]; then
	bu_gi_callerFolderPath="$bu_gi_callerFolderPath/"
fi

# Get absolute folder for this script
bu_gi_selfFolderPath="`cd "${BASH_SOURCE[0]%/*}"; pwd -P`/" # Command to get the absolute path

# Include utils functions
. "${bu_gi_selfFolderPath}utils.sh"

# Sanity checks
envSanityChecks "grep" "tar" "stat"

# Include config file functions
. "${bu_gi_selfFolderPath}load_config_file.sh"

# Deploy symbols found in current directory
deploySymbols()
{
	local projectName="$1"
	local version="$2"
	local result=""

	if [ ${doSym} -eq 0 ];
	then
		return
	fi

	if isWindows;
	then
		echo -n "Deploying symbol files... "

		local symbolsServerPath="${params["symbols_windows_pdb_server_path"]}"
		if [ -z "${symbolsServerPath}" ];
		then
			echo "FAILED: 'symbols_windows_pdb_server_path' variable not set in ${configFile}"
			return
		fi

		local pathConverterBinary
		if isCygwin;
		then
			pathConverterBinary="cygpath"
		elif isWSL;
		then
			pathConverterBinary="wslpath"
		fi

		local symbolsServerPathUnix="${symbolsServerPath}"
		if [ -n "${pathConverterBinary}" ]; then
			symbolsServerPathUnix=$(${pathConverterBinary} -a -u "${symbolsServerPath}")
		fi
		# Validate the path using the unix path as we are running in a bash shell but the provided path is in Windows format (because the symstore command expects it)
		if [ ! -d "${symbolsServerPathUnix}" ];
		then
			echo "FAILED: Server path does not exist: '${symbolsServerPath}' (unix path: '${symbolsServerPathUnix}')"
			return
		fi

		local symstorePath="${params["symbols_symstore_path"]}"
		if [ -z "${symstorePath}" ];
		then
			echo "FAILED: 'symbols_symstore_path' variable not set in ${configFile}"
			return
		fi
		if [ -n "${pathConverterBinary}" ];
		then
			symstorePath=$(${pathConverterBinary} -a -u "${symstorePath}")
			if [ $? -ne 0 ]; then
				echo "FAILED: 'symbols_symstore_path' variable is not a valid path in WSL: '${symstorePath}'"
				return
			fi
		fi
		if [ ! -f "${symstorePath}" ];
		then
			echo "FAILED: symstore.exe path does not exist: '${symstorePath}'"
			return
		fi

		result=$("${symstorePath}" add /r /l /f *.* /s "${symbolsServerPath}" /t "${projectName}" /v "${version}" /c "Adding ${projectName} ${version}" /compress)
		if [ $? -ne 0 ]; then
			echo "Failed to deploy symbols ;("
			echo ""
			echo $result
			return
		fi

		echo "done"

	elif isMac;
	then
		echo -n "Deploying symbol files... "

		local symbolsServerPath="${params["symbols_macos_dsym_server_path"]}"
		if [ -z "${symbolsServerPath}" ];
		then
			echo "FAILED: 'symbols_macos_dsym_server_path' variable not set in ${configFile}"
			return
		fi
		if [ ! -d "${symbolsServerPath}" ];
		then
			echo "FAILED: Server path does not exist: '${symbolsServerPath}'"
			return
		fi
		symbolsServerPath="${symbolsServerPath}/${projectName}/${version}"
		if [ ! -d "${symbolsServerPath}" ]; then
			mkdir -p "${symbolsServerPath}"
		fi
		for sym in `ls`
		do
			cp -R "${sym}" "${symbolsServerPath}/"
		done

		echo "done"
	fi
}

# Default values
default_VisualGenerator="Visual Studio 17 2022"
default_VisualToolset="v143"
default_VisualToolchain="x64"
default_keyDigits=2
default_betaTagName="-beta"

# Check for defaults override
if [[ $(type -t extend_gi_fnc_defaults) == function ]]; then
	extend_gi_fnc_defaults
fi

# Sanity check for legacy parameters
if [ ! -z "$default_VisualArch" ]; then
	echo "ERROR: The 'default_VisualArch' parameter from '.defaults.sh' file is deprecated. Use 'default_buildArch' instead."
	exit 4
fi

#
cmake_generator=""
platform=""
default_arch=""
declare -a arch=()
toolset=""
outputFolderBasePath="_install"
defaultOutputFolder="${outputFolderBasePath}_<platform>_<arch>_<generator>_<toolset>_<config>"
deliverablesFolder="_deliverables"
verbose=0
declare -a supportedArchs=()
if isMac; then
	cmake_path="cmake"
	# cmake from the path not found, try CMake.app
	which "${cmake_path}" &> /dev/null
	if [ $? -ne 0 ]; then
		cmake_path="/Applications/CMake.app/Contents/bin/cmake"
	fi
	generator="Xcode"
	# If a default architecture is set, use it. Otherwise, use the host architecture
	if [ -z "$default_buildArch" ]; then
		getMachineArch default_arch
	else
		default_arch="$default_buildArch"
	fi
	supportedArchs+=("x64")
	supportedArchs+=("arm64")
else
	# Use cmake from the path
	if isWindows; then
		cmake_path="cmake.exe"
		generator="$default_VisualGenerator"
		toolset="$default_VisualToolset"
		toolchain="$default_VisualToolchain"
		default_arch="$default_buildArch"
		supportedArchs+=("x86")
		supportedArchs+=("x64")
	else
		cmake_path="cmake"
		generator="Unix Makefiles"
		# If a default architecture is set, use it. Otherwise, use the host architecture
		if [ -z "$default_buildArch" ]; then
			getMachineArch default_arch
		else
			default_arch="$default_buildArch"
		fi
		supportedArchs+=("${default_arch}")
	fi
fi
getOS platform

which "${cmake_path}" &> /dev/null
if [ $? -ne 0 ]; then
	echo "CMake not found. Please add CMake binary folder in your PATH environment variable."
	exit 1
fi

outputFolder=""
buildConfig="Release"
buildConfigOverride=0
doCleanup=1
doRebuild=1
doSign=1
listArchs=0
useAllArchs=0
doSym=1
useIncredibuild=0
gen_cmake_additional_options=()
cmake_additional_options=()
key_digits=$((10#$default_keyDigits))
key_postfix=""
marketing_version=""
betaTagName="${default_betaTagName}"

while [ $# -gt 0 ]
do
	case "$1" in
		-h)
			echo "Usage: gen_install.sh [options]"
			echo " -h -> Display this help"
			echo " -v -> Print script version and exit"
			echo " -vvv -> Verbose mode"
			echo " -a <flags> -> Add cmake flags directly passed to underlying gen_cmake.sh"
			echo " -b <cmake path> -> Force cmake binary path (Default: $cmake_path)"
			echo " -c <cmake generator> -> Force cmake generator (Default: $generator)"
			echo " -d <deliverables folder> -> Force deviverables output folder (Default: $deliverablesFolder)"
			echo " -arch <arch> -> Set target architecture (Default: $default_arch). Supported archs depends on target platform"
			echo " -archs -> List supported architectures (which depends on target platform)"
			echo " -all-archs -> Build all supported architectures"
			echo " -no-clean -> Don't remove temp build folder [Default=clean on successful build]"
			echo " -no-rebuild -> Don't rebuild the whole solution [Default=rebuild everything]"
			if isWindows; then
				echo " -t <visual toolset> -> Force visual toolset (Default: $toolset)"
				echo " -tc <visual toolchain> -> Force visual toolchain (Default: $toolchain)"
				echo " -ib -> Use Incredibuild BuildConsole to build"
			fi
			echo " -no-sym -> Don't deploy symbols [Default=deploy])"
			echo " -no-signing -> Do not sign binaries (Default: Do signing)"
			echo " -debug -> Compile using Debug configuration (Default: Release)"
			echo " -key-digits <Number of digits> -> The number of digits to be used as Key for installation, comprised between 0 and 4 (Default: $default_keyDigits)"
			echo " -key-postfix <Postfix> -> Postfix string to be added to the Key for installation (Default: "")"
			echo " -marketing-version <Version> -> Set the marketing version to use (Default: Generated from CMakeLists.txt)"
			echo " -beta-tag <BetaTag> -> Set the beta tag to use before the 4th digit (Default: $default_betaTagName)"
			if [[ $(type -t extend_gi_fnc_help) == function ]]; then
				extend_gi_fnc_help
			fi
			exit 3
			;;
		-v)
			exit 0
			;;
		-vvv)
			verbose=1
			;;
		-a)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -a option, see help (-h)"
				exit 4
			fi
			cmake_additional_options+=("$1")
			;;
		-b)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -b option, see help (-h)"
				exit 4
			fi
			if [ ! -x "$1" ]; then
				echo "ERROR: Specified cmake binary is not valid (not found or not executable): $1"
				exit 4
			fi
			cmake_path="$1"
			;;
		-c)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -c option, see help (-h)"
				exit 4
			fi
			cmake_generator="$1" # Update local value, we need it later
			gen_cmake_additional_options+=("-c")
			gen_cmake_additional_options+=("$1")
			;;
		-d)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -d option, see help (-h)"
				exit 4
			fi
			deliverablesFolder="$1"
			;;
		-arch)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -arch option, see help (-h)"
				exit 4
			fi
			arch="$1"
			gen_cmake_additional_options+=("-arch")
			gen_cmake_additional_options+=("$arch")
			;;
		-archs)
			listArchs=1
			;;
		-all-archs)
			useAllArchs=1
			gen_cmake_additional_options+=("-all-archs")
			;;
		-no-clean)
			doCleanup=0
			;;
		-no-rebuild)
			doRebuild=0
			;;
		-t)
			if isWindows; then
				shift
				if [ $# -lt 1 ]; then
					echo "ERROR: Missing parameter for -t option, see help (-h)"
					exit 4
				fi
				toolset="$1" # Update local value, we need it later
				gen_cmake_additional_options+=("-t")
				gen_cmake_additional_options+=("$1")
			else
				echo "ERROR: -t option is only supported on Windows platform"
				exit 4
			fi
			;;
		-tc)
			if isWindows; then
				shift
				if [ $# -lt 1 ]; then
					echo "ERROR: Missing parameter for -tc option, see help (-h)"
					exit 4
				fi
				gen_cmake_additional_options+=("-tc")
				gen_cmake_additional_options+=("$1")
			else
				echo "ERROR: -tc option is only supported on Windows platform"
				exit 4
			fi
			;;
		-ib)
			if isWindows; then
				useIncredibuild=1
			else
				echo "ERROR: -ib option is only supported on Windows platform"
				exit 4
			fi
			;;
		-p)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -p option, see help (-h)"
				exit 4
			fi
			projectName="$1"
			;;
		-no-sym)
			doSym=0
			;;
		-no-signing)
			doSign=0
			;;
		-debug)
			buildConfig="Debug"
			buildConfigOverride=1
			;;
		-key-digits)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -key-digits option, see help (-h)"
				exit 4
			fi
			numberRegex='^[0-9]$'
			if ! [[ $1 =~ $numberRegex ]]; then
				echo "ERROR: Invalid value for -key-digits option (not a number), see help (-h)"
				exit 4
			fi
			key_digits=$((10#$1))
			if [[ $key_digits -lt 0 || $key_digits -gt 4 ]]; then
				echo "ERROR: Invalid value for -key-digits option (not comprised between 0 and 4), see help (-h)"
				exit 4
			fi
			;;
		-key-postfix)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -key-postfix option, see help (-h)"
				exit 4
			fi
			postfixRegex='^[a-zA-Z0-9_+-]+$'
			if ! [[ $1 =~ $postfixRegex ]]; then
				echo "ERROR: Invalid value for -key-postfix option (Only alphanum, underscore, plus and minus are allowed), see help (-h)"
				exit 4
			fi
			key_postfix="$1"
			;;
		-marketing-version)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -marketing-version option, see help (-h)"
				exit 4
			fi
			marketing_version="$1"
            ;;
		-beta-tag)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -beta-tag option, see help (-h)"
				exit 4
			fi
			betaTagName="$1"
			;;
		*)
			consumed_args=0
			if [[ $(type -t extend_gi_fnc_unhandled_arg) == function ]]; then
				extend_gi_fnc_unhandled_arg $@
				consumed_args=$?
				for (( i=1; i<$consumed_args; i++ )); do
					shift
				done
			fi
			if [ $consumed_args -eq 0 ]; then
				echo "ERROR: Unknown option '$1' (use -h for help)"
				exit 4
			fi
			;;
	esac
	shift
done

if [[ $(type -t extend_gi_fnc_postparse) == function ]]; then
	extend_gi_fnc_postparse
fi

# Ensure deliverablesFolder ends with /
if [[ ${deliverablesFolder: -1} != "/" ]]; then
	deliverablesFolder="$deliverablesFolder/"
fi

# Ensure deliverablesFolder does not exist (neither file nor directory)
if [ -e "${deliverablesFolder%/*}" ]; then
	if [ -f "${deliverablesFolder%/*}" ];
	then
		echo "ERROR: Deliverables folder '$deliverablesFolder' already exists and is a file"
		exit 4
	fi
	if ! isEmptyFolder "$deliverablesFolder";
	then
		echo "ERROR: Deliverables folder '$deliverablesFolder' already exists and is not empty"
		exit 4
	fi
fi

# Create deliverablesFolder
mkdir -p "$deliverablesFolder"

if [ ! -z "$cmake_generator" ]; then
	echo "Overriding default cmake generator ($generator) with: $cmake_generator"
	generator="$cmake_generator"
fi

# Check for macOS generator when using macOS >= 13
if isMac; then
	macvers="$(sw_vers -productVersion)"
	if [[ ${macvers%%.*} -ge 13 && "${generator}" == "Xcode" ]];
	then
		echo "Xcode generator is unstable starting with macOS Ventura, please use ninja instead (-c Ninja)"
		exit 4
	fi
fi

# Remove duplicates from supported archs
removeDuplicates supportedArchs

# List supported archs
if [ $listArchs -eq 1 ]; then
	echo "Supported archs for platform ${platform} (Default arch marked with [*]):"
	for arch in "${supportedArchs[@]}";	do
		if [[ " ${default_arch[@]} " =~ " ${arch} " ]]; then
			echo " [*] $arch"
		else
			echo "     $arch"
		fi
	done
	exit 0
fi

# Use all archs
if [ $useAllArchs -eq 1 ]; then
	arch=("${supportedArchs[@]}")
fi

# No arch was specified on command line, use default arch
if [ ${#arch[*]} -eq 0 ]; then
	arch=(${default_arch[@]})
	for a in "${arch[@]}";	do
		gen_cmake_additional_options+=("-arch")
		gen_cmake_additional_options+=("$a")
	done
fi

# Check arch(s) is(are) valid for target platform
for a in "${arch[@]}";	do
	if [[ ! " ${supportedArchs[@]} " =~ " ${a} " ]]; then
		echo "ERROR: Unsupported arch for platform ${platform}: ${a} (Supported archs: ${supportedArchs[@]})"
		exit 4
	fi
done

# Concatenate all archs into one string
printf -v arch_list "%s_" "${arch[@]}"
arch_list="${arch_list%_}"

# Forward more parameters to gen_cmake
gen_cmake_additional_options+=("-key-digits")
gen_cmake_additional_options+=("$key_digits")
if [ ! -z "$key_postfix" ]; then
	gen_cmake_additional_options+=("-key-postfix")
	gen_cmake_additional_options+=("$key_postfix")
fi
if [ ! -z "$marketing_version" ]; then
	gen_cmake_additional_options+=("-marketing-version")
	gen_cmake_additional_options+=("$marketing_version")
fi
if [ ! -z "$betaTagName" ]; then
	gen_cmake_additional_options+=("-beta-tag")
	gen_cmake_additional_options+=("$betaTagName")
fi

# Load config file
loadConfigFile

# Check for signing
if [ $doSign -eq 1 ]; then
	gen_cmake_additional_options+=("-sign")

	# Check if signtool options are specified on windows
	if isWindows; then
		signtoolOptions=${params["signtool_options"]}
		if [ -z "$signtoolOptions" ]; then
			echo "ERROR: windows requires signtool options to be set. Specify it in the ${configFile} file"
		fi
		gen_cmake_additional_options+=("-signtool-opt")
		gen_cmake_additional_options+=("$signtoolOptions")
	fi

	# Check if Identity is specified on macOS
	if isMac; then
		identityString="${params["identity"]}"

		if [ "x$identityString" == "x" ]; then
			echo "ERROR: macOS requires valid signing identity. Specify it in the ${configFile} file"
			exit 4
		fi
		gen_cmake_additional_options+=("-id")
		gen_cmake_additional_options+=("$identityString")
	fi
fi

# Additional options from .config file
if [ ${params["use_sparkle"]} = true ]; then
	if [ "x${params["appcast_releases"]}" == "x" ]; then
		echo "ERROR: appcast_releases must not be empty in ${configFile} file"
		exit 4
	fi
	cmake_additional_options+=("-DAPPCAST_RELEASES_URL=${params["appcast_releases"]}")

	if [ "x${params["appcast_betas"]}" == "x" ]; then
		echo "ERROR: appcast_betas must not be empty in ${configFile} file"
		exit 4
	fi
	cmake_additional_options+=("-DAPPCAST_BETAS_URL=${params["appcast_betas"]}")

	if [ "x${params["appcast_releases_fallback"]}" != "x" ]; then
		cmake_additional_options+=("-DAPPCAST_RELEASES_FALLBACK_URL=${params["appcast_releases_fallback"]}")
	fi

	if [ "x${params["appcast_betas_fallback"]}" != "x" ]; then
		cmake_additional_options+=("-DAPPCAST_BETAS_FALLBACK_URL=${params["appcast_betas_fallback"]}")
	fi
fi

if [ ! -z "$cmake_generator" ]; then
	echo "Overriding default cmake generator ($generator) with: $cmake_generator"
	generator="$cmake_generator"
fi

getOutputFolder outputFolder "${outputFolderBasePath}" "${platform}" "${arch_list}" "${toolset}" "${buildConfig}" "${generator}"

toolset_option=""
if [ ! -z "${toolset}" ]; then
	toolset_option="-t ${toolset}"
	if [ ! -z "${toolchain}" ]; then
		toolset_option="${toolset_option} -tc ${toolchain}"
	fi
fi

# Cleanup routine
cleanup_main()
{
	if [[ $doCleanup -eq 1 && $1 -eq 0 ]]; then
		echo -n "Cleaning... "
		sleep 2
		rm -rf "${bu_gi_callerFolderPath}${outputFolder}"
		echo "done"
	else
		echo "Not cleaning up as requested, folder '${outputFolder}' untouched"
	fi
	exit $1
}

trap 'cleanup_main $?' EXIT

if [ -z "$projectName" ]; then
	# Get project name
	projectName="$(grep -Po "project *\( *(\K[^\"][^ )]+|\"\K[^\"]+)" "CMakeLists.txt")"
	if [[ $projectName == "" ]]; then
		echo "Cannot detect project name"
		exit 1
	fi
	projectName="${projectName//[$'\t\r\n']}"
	projectName="${projectName/#la_/}"
fi

cmakeVersion=$(grep -m 1 -Po "set *\(.+_VERSION +\K[0-9]+(\.[0-9]+)+(?= *\))" CMakeLists.txt)
if [[ $cmakeVersion == "" ]]; then
	echo "Cannot detect project version"
	exit 1
fi
cmakeVersion="${cmakeVersion//[$'\t\r\n']}"

# Check if we have a release or devel version
oldIFS="$IFS"
IFS='.' read -a versionSplit <<< "$cmakeVersion"
IFS="$oldIFS"

if [[ ${#versionSplit[*]} -lt 3 || ${#versionSplit[*]} -gt 4 ]]; then
	echo "Invalid project version (should be in the form x.y.z[.w]): $cmakeVersion"
	exit 1
fi

beta_tag=""
build_tag=""
is_release=1
releaseVersion="${versionSplit[0]}.${versionSplit[1]}.${versionSplit[2]}"
internalVersion="$((${versionSplit[0]} * 1000000 + ${versionSplit[1]} * 1000 + ${versionSplit[2]}))"
if [ ${#versionSplit[*]} -eq 4 ]; then
	beta_tag="${betaTagName}${versionSplit[3]}"
	build_tag="+$(git rev-parse --short HEAD)"
	is_release=0
	internalVersion="${internalVersion}.${versionSplit[3]}"
else
	internalVersion="${internalVersion}.99999"
fi

if isWindows; then
	# OS name based on arch
	if [ "$arch_list" == "x64" ]; then
		installerOSName="win64"
	else
		installerOSName="win32"
	fi
elif isMac; then
	installerOSName="Darwin"
else
	getOS osName
	echo "ERROR: Installer for $osName not supported yet"
	exit 1
fi

if [ -n "$marketing_version" ]; then
	installerBaseName="${projectName}-${marketing_version}${beta_tag}${build_tag}"
else
	installerBaseName="${projectName}-${releaseVersion}${beta_tag}${build_tag}"
fi
if [ -n "$marketing_version" ]; then
	installerBaseName="${installerBaseName}+${cmakeVersion}"
fi
installerBaseName="${installerBaseName}+${installerOSName}"
if [ $buildConfigOverride -eq 1 ]; then
	installerBaseName="${installerBaseName}+${buildConfig}"
fi

cmake_additional_options+=("-DCU_INSTALLER_NAME=${installerBaseName}")

# Cleanup previous build folders, just in case
if [ $doRebuild -eq 1 ]; then
	rm -rf "${bu_gi_callerFolderPath}${outputFolder}"
fi

# We must add a cmake parameter when using Single-Configuration generators
if isSingleConfigurationGenerator "$generator"; then
	gen_cmake_additional_options+=("-${buildConfig,,}")
fi

# Print build properties summary
echo "/--------------------------\\"
echo "| Project properties summary"
echo "| - CMAKE VERS: $("$cmake_path" --version | grep -oP '\d+(\.\d+)+')"
echo "| - GENERATOR: ${generator}"
echo "| - PLATFORM: ${platform}"
echo "| - ARCH: ${arch[@]}"
if [ ! -z "${toolset}" ]; then
	echo "| - TOOLSET: ${toolset}"
fi
if [ ! -z "${toolchain}" ]; then
	echo "| - TOOLCHAIN: ${toolchain}"
fi
if [ ! -z "${buildConfig}" ]; then
	echo "| - BUILD TYPE: ${buildConfig}"
fi
if [[ $(type -t extend_gi_fnc_props_summary) == function ]]; then
	extend_gi_fnc_props_summary
fi
echo "\\--------------------------/"
echo ""


# Compilation stuff
if [ $verbose -eq 1 ]; then
	echo "Running command: ./gen_cmake.sh -o \"${outputFolder}\" ${gen_cmake_additional_options[@]} $toolset_option -f \"$cmake_opt\" -- ${cmake_additional_options[@]}"
	./gen_cmake.sh -o "${outputFolder}" "${gen_cmake_additional_options[@]}" $toolset_option -f "$cmake_opt" -- "${cmake_additional_options[@]}"
	if [ $? -ne 0 ]; then
		echo "Failed to generate cmake files ;("
		exit 1
	fi
else
	echo -n "Generating cmake files... "
	log=$(./gen_cmake.sh -o "${outputFolder}" "${gen_cmake_additional_options[@]}" $toolset_option -f "$cmake_opt" -- "${cmake_additional_options[@]}")
	if [ $? -ne 0 ]; then
		echo "Failed to generate cmake files ;("
		echo ""
		echo $log
		exit 1
	fi
	echo "done"
fi

pushd "${outputFolder}" &> /dev/null
echo -n "Building project... "
declare -a cmakeBuildParameters=("--build" "." "-j" "4" "--config" "${buildConfig}" "--target" "install")
if [ $doRebuild -eq 1 ]; then
	cmakeBuildParameters+=("--clean-first")
fi
declare -a buildCommand=()
if [ $useIncredibuild -eq 1 ]; then
	echo -n "Using Incredibuild... "
	buildCommand+=("BuildConsole.exe")
	buildCommand+=("/COMMAND=${cmake_path} ${cmakeBuildParameters[*]}") # Incredibuild expects a single parameter for the whole command (thus expand using * instead of @)
else
	buildCommand+=("${cmake_path}")
	buildCommand+=("${cmakeBuildParameters[@]}")
fi
log=$("${buildCommand[@]}")
if [ $? -ne 0 ]; then
	echo "Failed to build project ;("
	echo ""
	echo $log
	exit 1
fi
echo "done"
popd &> /dev/null

pushd "${outputFolder}" &> /dev/null
echo -n "Generating project installer... "
log=$("$cmake_path" --build . --config "${buildConfig}" --target package)
if [ $? -ne 0 ]; then
	echo "Failed to generate installer ;("
	echo ""
	echo $log
	exit 1
fi
echo "done"
popd &> /dev/null

which tar &> /dev/null
if [ $? -eq 0 ]; then
	symbolsFile="${installerBaseName}-symbols.tgz"
	echo -n "Archiving symbols... "
	log=$(tar cvzf "${deliverablesFolder}${symbolsFile}" "${outputFolder}"/Symbols)
	if [ $? -ne 0 ]; then
		echo "Failed to archive symbols ;("
		echo ""
		echo $log
		exit 1
	fi
	echo "done"
fi

generatedInstallerFilePath=$(ls "${outputFolder}"/*"${installerBaseName}."*)
if [ ! -f "$generatedInstallerFilePath" ]; then
	echo "ERROR: Cannot find installer file in $outputFolder sub folder. Not cleaning it so you can manually search. Symbols have not been deployed either, so you might not want to publish this version."
	doCleanup=0
	exit 1
fi
fullInstallerName="${generatedInstallerFilePath##*/}" # Get the file name only

mv "${generatedInstallerFilePath}" "${deliverablesFolder}"

if [ $doSign -eq 1 ]; then
	# MacOS already signed by CPack
	if isWindows; then
		echo -n "Signing Package..."
		log=$(signtool.exe sign ${signtoolOptions} "${deliverablesFolder}${fullInstallerName}")
		if [ $? -ne 0 ]; then
			echo "Failed to sign package ;("
			echo ""
			echo $log
			exit 1
		fi
		echo "done"
	fi
fi

echo ""
echo "Installer generated: ${fullInstallerName}"
if [ ! -z "${symbolsFile}" ]; then
	echo "Symbols generated: ${symbolsFile}"
	pushd "${outputFolder}/Symbols" &> /dev/null
	deploySymbols "${projectName}" "${internalVersion}"
	popd &> /dev/null
fi
