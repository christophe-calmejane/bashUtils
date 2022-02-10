#!/usr/bin/env bash
# Useful script to generate project files using cmake
# Set cmake_opt variable before calling this script to set cmake defines
# The following functions can be defined before including this script:
#   extend_gc_fnc_help() -> Called when -h is requested. No return value
#   extend_gc_fnc_unhandled_arg() -> Called when an unhandled argument is found. Return the count of consumed args
#   extend_gc_fnc_precmake() -> Called just before invoking cmake. The $add_cmake_opt list can be appended. No return value
#   extend_gc_fnc_props_summary() -> Called just before invoking cmake when printing build properties summary. No return value

# Get absolute folder for this script
selfFolderPath="`cd "${BASH_SOURCE[0]%/*}"; pwd -P`/" # Command to get the absolute path

# Include util functions
. "${selfFolderPath}utils.sh"

# Sanity checks
envSanityChecks "grep"

# Default values
default_VisualGenerator="Visual Studio 16 2019"
default_VisualToolset="v142"
default_VisualToolchain="x64"
default_VisualArch="x86"
default_signtoolOptions="/a /sm /q /fd sha256 /tr http://timestamp.sectigo.com /td sha256"

# 
cmake_generator=""
generator_arch=""
platform=""
default_arch=""
declare -a arch=()
toolset=""
cmake_config=""
outputFolderBasePath="_build"
defaultOutputFolder="${outputFolderBasePath}_<platform>_<arch>_<generator>_<toolset>_<config>"
declare -a supportedArchs=()
if isMac; then
	cmake_path="/Applications/CMake.app/Contents/bin/cmake"
	# CMake.app not found, use cmake from the path
	if [ ! -f "${cmake_path}" ]; then
		cmake_path="cmake"
	fi
	generator="Xcode"
	getMachineArch default_arch
	supportedArchs+=("x64")
	supportedArchs+=("arm64")
else
	# Use cmake from the path
	if isWindows; then
		cmake_path="cmake.exe"
		generator="$default_VisualGenerator"
		toolset="$default_VisualToolset"
		toolchain="$default_VisualToolchain"
		default_arch="$default_VisualArch"
		supportedArchs+=("x86")
		supportedArchs+=("x64")
	else
		cmake_path="cmake"
		generator="Unix Makefiles"
		getMachineArch default_arch
		supportedArchs+=("${default_arch}")
	fi
fi
getOS platform

which "${cmake_path}" &> /dev/null
if [ $? -ne 0 ]; then
	echo "CMake not found. Please add CMake binary folder in your PATH environment variable."
	exit 1
fi

# Parse variables
outputFolder=""
outputFolderForced=0
add_cmake_opt=()
useVSclang=0
hasTeamId=0
signingId=""
doSign=0
listArchs=0
useAllArchs=0
signtoolOptions="$default_signtoolOptions"

# Override defaults using config file, if loaded
if [[ ! -z $configFileLoaded && $configFileLoaded -eq 1 ]]; then
	signingId="${params["identity"]}"
	signtoolOptions=${params["signtool_options"]}
fi

while [ $# -gt 0 ]
do
	case "$1" in
		-h)
			echo "Usage: gen_cmake.sh [options] -- [cmake options]"
			echo "Everything passed after -- will be passed directly to the cmake command"
			echo "Available options:"
			echo " -h -> Display this help"
			echo " -o <folder> -> Output folder (Default: ${defaultOutputFolder})"
			echo " -f <flags> -> Force all cmake flags (Default: $cmake_opt)"
			echo " -a <flag> -> Append specified cmake flag to default ones (or to forced ones with -f option). Alternatively use -- if many flags are to be passed, to avoid many -a options"
			echo " -b <cmake path> -> Force cmake binary path (Default: $cmake_path)"
			echo " -c <cmake generator> -> Force cmake generator (Default: $generator)"
			echo " -arch <arch> -> Set target architecture (Default: $default_arch). For platforms that support it, you can specify multiple -arch options"
			echo " -archs -> List supported architectures (which depends on target platform)"
			echo " -all-archs -> Build all supported architectures"
			if isWindows; then
				echo " -t <visual toolset> -> Force visual toolset (Default: $toolset)"
				echo " -tc <visual toolchain> -> Force visual toolchain (Default: $toolchain)"
				echo " -clang -> Compile using clang for VisualStudio"
				echo " -signtool-opt <options> -> Windows code signing options (Default: $default_signtoolOptions)"
			fi
			if isMac; then
				echo " -id <Signing Identity> -> Signing identity for binary signing (full identity name inbetween the quotes, see -ids to get the list)"
				echo " -ids -> List signing identities"
				echo " -t <xcode toolset> -> Force xcode toolset (Default: autodetect)"
				echo " -ios -> Cross-compiling for iOS"
			fi
			echo " -android -> Cross-compiling for Android"
			echo " -debug -> Force debug configuration (Single-Configuration generators only)"
			echo " -release -> Force release configuration (Single-Configuration generators only)"
			echo " -sign -> Sign binaries (Default: No signing)"
			echo " -asan -> Enable Address Sanitizer (Default: Off)"
			if [[ $(type -t extend_gc_fnc_help) == function ]]; then
				extend_gc_fnc_help
			fi
			exit 3
			;;
		-o)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -o option, see help (-h)"
				exit 4
			fi
			outputFolder="$1"
			outputFolderForced=1
			;;
		-f)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -f option, see help (-h)"
				exit 4
			fi
			cmake_opt="$1"
			;;
		-a)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -a option, see help (-h)"
				exit 4
			fi
			add_cmake_opt+=("$1")
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
			cmake_generator="$1"
			;;
		-t)
			if [[ $(isWindows; echo $?) -eq 0 || $(isMac; echo $?) -eq 0 ]]; then
				shift
				if [ $# -lt 1 ]; then
					echo "ERROR: Missing parameter for -t option, see help (-h)"
					exit 4
				fi
				toolset="$1"
			else
				echo "ERROR: -t option is only supported on Windows/macOS platforms"
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
				toolchain="$1"
			else
				echo "ERROR: -tc option is only supported on Windows platform"
				exit 4
			fi
			;;
		-64)
			echo "ERROR: -64 option is deprecated, use -arch x64 instead"
			exit 4
			;;
		-clang)
			if isWindows; then
				useVSclang=1
			else
				echo "ERROR: -clang option is only supported on Windows platform"
				exit 4
			fi
			;;
		-signtool-opt)
			if isWindows; then
				shift
				if [ $# -lt 1 ]; then
					echo "ERROR: Missing parameter for -signtool-opt option, see help (-h)"
					exit 4
				fi
				signtoolOptions="$1"
			else
				echo "ERROR: -signtool-opt option is only supported on Windows platform"
				exit 4
			fi
			;;
		-id)
			if isMac; then
				shift
				if [ $# -lt 1 ]; then
					echo "ERROR: Missing parameter for -id option, see help (-h)"
					exit 4
				fi
				signingId="$1"
			else
				echo "ERROR: -id option is only supported on macOS platform"
				exit 4
			fi
			;;
		-ids)
			if isMac; then
				getDeveloperSigningIdentities identities "Developer ID Application"
				if [ ${#identities[*]} -eq 0 ]; then
					echo "No valid signing identity found."
					echo "You need to install a valid 'Developer ID Application' codesigning identity."
					exit 4
				fi
				echo "Found ${#identities[*]} valid codesigning identities:"
				for identity in "${identities[@]}"; do
					echo " -> $identity"
				done
				exit 0
			else
				echo "ERROR: -ids option is only supported on macOS platform"
				exit 4
			fi
			;;
		-ios)
			if isMac; then
				platform="ios"
				default_arch="arm64" # Setting default arch for cross-compilation
				supportedArchs+=("arm")
				supportedArchs+=("arm64")
				add_cmake_opt+=("-DCMAKE_SYSTEM_NAME=iOS")
			else
				echo "ERROR: -ios option is only supported on MacOS platform"
				exit 4
			fi
			;;
		-android)
			if [ "x${ANDROID_NDK_HOME}" == "x" ]; then
				echo "ERROR: ANDROID_NDK_HOME env var required for Android cross-compilation"
				exit 4
			fi
			if [ ! -d "${ANDROID_NDK_HOME}" ]; then
				echo "ERROR: ANDROID_NDK_HOME env var does not point to a valid folder: ${ANDROID_NDK_HOME}"
				exit 4
			fi
			if [ ! -f "${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" ]; then
				echo "ERROR: ANDROID_NDK_HOME env var does not point to a valid NDK folder (build/cmake/android.toolchain.cmake not found): ${ANDROID_NDK_HOME}"
				exit 4
			fi
			generator="Ninja"
			toolset=""
			toolchain="clang"
			platform="android"
			androidSdkVersion="24"
			default_arch="arm64" # Setting default arch for cross-compilation
			supportedArchs+=("arm")
			supportedArchs+=("arm64")
			add_cmake_opt+=("-DCMAKE_SYSTEM_NAME=Android")
			add_cmake_opt+=("-DCMAKE_SYSTEM_VERSION=android-${androidSdkVersion}")
			add_cmake_opt+=("-DANDROID_TOOLCHAIN=${toolchain}")
			add_cmake_opt+=("-DCMAKE_ANDROID_NDK=$ANDROID_NDK_HOME")
			add_cmake_opt+=("-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake")
			add_cmake_opt+=("-DCMAKE_ANDROID_STL_TYPE=c++_static")
			add_cmake_opt+=("-DANDROID_PLATFORM=android-${androidSdkVersion}")
			;;
		-arch)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -arch option, see help (-h)"
				exit 4
			fi
			arch+=("$1")
			;;
		-archs)
			listArchs=1
			;;
		-all-archs)
			useAllArchs=1
			;;
		-debug)
			cmake_config="Debug"
			;;
		-release)
			cmake_config="Release"
			;;
		-sign)
			doSign=1
			;;
		-asan)
			add_cmake_opt+=("-DCU_ENABLE_ASAN=TRUE")
			;;
		--)
			shift
			while [ $# -gt 0 ]
			do
				add_cmake_opt+=("$1")
				shift
			done
			break
			;;
		*)
			consumed_args=0
			if [[ $(type -t extend_gc_fnc_unhandled_arg) == function ]]; then
				extend_gc_fnc_unhandled_arg $@
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

if [[ $(type -t extend_gc_fnc_postparse) == function ]]; then
	extend_gc_fnc_postparse
fi

if [ ! -z "$cmake_generator" ]; then
	echo "Overriding default cmake generator ($generator) with: $cmake_generator"
	generator="$cmake_generator"
fi

# Remove duplicates from supported archs
removeDuplicates supportedArchs

# List supported archs
if [ $listArchs -eq 1 ]; then
	echo "Supported archs for platform ${platform} (Default arch marked with [*]):"
	for arch in "${supportedArchs[@]}";	do
		if [ $arch == $default_arch ]; then
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
	arch+=("$default_arch")
fi

# Check arch(s) is(are) valid for target platform
for a in "${arch[@]}";	do
	if [[ ! " ${supportedArchs[@]} " =~ " ${a} " ]]; then
		echo "ERROR: Unsupported arch for platform ${platform}: ${a} (Supported archs: ${supportedArchs[@]})"
		exit 4
	fi
done

# Set correct generator architecture on Windows
if [ "${platform}" == "win" ];
then
	# No support for multi arch on Windows
	if [ ${#arch[*]} -gt 1 ]; then
		echo "ERROR: Multi arch not supported on Windows"
		exit 4
	fi

	case "${arch}" in
		x86)
			generator_arch="Win32"
			;;
		x64)
			generator_arch="x64"
			;;
		*)
			echo "ERROR: Unknown windows arch: ${arch} (add support for it)"
			exit 4
			;;
	esac

# Special case for Android cross-compilation, we must set the correct ABI
elif [ "${platform}" == "android" ];
then
	# No support for multi arch on android (yet)
	if [ ${#arch[*]} -gt 1 ]; then
		echo "ERROR: Multi arch not supported on Android"
		exit 4
	fi

	case "${arch}" in
		x86)
			add_cmake_opt+=("-DANDROID_ABI=x86")
			;;
		x64)
			add_cmake_opt+=("-DANDROID_ABI=x86_64")
			;;
		arm64)
			add_cmake_opt+=("-DANDROID_ABI=arm64-v8a")
			;;
		*)
			echo "ERROR: Unknown android arch: ${arch} (add support for it)"
			exit 4
			;;
	esac

# Set macOS/iOS target architecture(s), otherwise CMake targets the architecture of the host
elif [[ "${platform}" == "mac" || "${platform}" == "ios" ]];
then
	# MacOS/iOS supports multi arch, convert each arch to cmake arch
	declare -a cmake_archs=()
	for a in "${arch[@]}"; do
		case "${a}" in
			x64)
				cmake_archs+=("x86_64")
				;;
			arm)
				cmake_archs+=("armv7")
				cmake_archs+=("armv7s")
				;;
			arm64)
				cmake_archs+=("arm64")
				;;
			*)
				echo "ERROR: Unknown macOS/iOS arch: ${a} (add support for it)"
				exit 4
				;;
		esac
	done
	# Concatenate all cmake archs into one string
	printf -v cmake_arch_list "%s;" "${cmake_archs[@]}"
	add_cmake_opt+=("-DCMAKE_OSX_ARCHITECTURES=${cmake_arch_list%;}")
fi

# Concatenate all archs into one string
printf -v arch_list "%s_" "${arch[@]}"
arch_list="${arch_list%_}"

# Signing is now mandatory for macOS
if isMac; then
	# No signing identity provided, try to autodetect
	getDeveloperSigningIdentities identities "Developer ID Application"
	if [ "$signingId" == "" ]; then
		echo -n "No code signing identity provided, autodetecting... "
		if [ ${#identities[*]} -eq 0 ]; then
			echo "ERROR: No valid signing identity found."
			echo "You need to install a valid 'Developer ID Application' codesigning identity."
			exit 4
		fi
		signingId="${identities[0]}"
		echo "using identity: '$signingId'"
	fi
	# Validate code signing identity exists
	if [[ ! " ${identities[@]} " =~ " ${signingId} " ]]; then
		echo "ERROR: Code signing identity '${signingId}' not found, use the full identity name (see -ids to get a list of valid identities)"
		exit 4
	fi
	# Validate installer signing identity exists
	getDeveloperSigningIdentities installerIdentities "Developer ID Installer"
	signingInstallerId="${signingId/Developer ID Application/Developer ID Installer}"
	if [[ ! " ${installerIdentities[@]} " =~ " ${signingInstallerId} " ]]; then
		echo "ERROR: Installer signing identity '${signingInstallerId}' not found. Download or create it from your Apple Developer account (should be of type 'Developer ID Installer')"
		exit 4
	fi
	# Get Team Identifier from signing identity (for xcode)
	teamRegEx="[^(]+\(([^)]+)"
	if ! [[ $signingId =~ $teamRegEx ]]; then
		echo "ERROR: Failed to find Team Identifier in signing identity: $signingId"
		exit 4
	fi
	teamId="${BASH_REMATCH[1]}"
	if [ $doSign -eq 0 ]; then
		echo "Binary signing is mandatory since macOS Catalina, forcing it using ID '$signingId' (TeamID '$teamId')"
		doSign=1
	fi
	add_cmake_opt+=("-DCU_BINARY_SIGNING_IDENTITY=$signingId")
	add_cmake_opt+=("-DCU_INSTALLER_SIGNING_IDENTITY=$signingInstallerId")
	add_cmake_opt+=("-DCU_TEAM_IDENTIFIER=$teamId")
fi

if [ $doSign -eq 1 ]; then
	add_cmake_opt+=("-DENABLE_CODE_SIGNING=TRUE")
	# Set signtool options if signing enabled on windows
	if isWindows; then
		if [ ! -z "$signtoolOptions" ]; then
			add_cmake_opt+=("-DCU_SIGNTOOL_OPTIONS=$signtoolOptions")
		fi
	fi
fi

# Using -clang option (shortcut to auto-define the toolset)
if [ $useVSclang -eq 1 ]; then
	toolset="ClangCL"
fi

# Check if at least a -debug or -release option has been passed for Single-Configuration generators
if isSingleConfigurationGenerator "$generator"; then
	if [ -z $cmake_config ]; then
		echo "ERROR: Single-Configuration generator '$generator' requires either -debug or -release option to be specified"
		exit 4
	fi
	add_cmake_opt+=("-DCMAKE_BUILD_TYPE=${cmake_config}")
else
	# Clear any -debug or -release passed to a Multi-Configurations generator
	cmake_config=""
fi

if [ $outputFolderForced -eq 0 ]; then
	getOutputFolder outputFolder "${outputFolderBasePath}" "${platform}" "${arch_list}" "${toolset}" "${cmake_config}" "${generator}"
fi

if ! isSingleConfigurationGenerator "$generator"; then
	generator_arch_option=""
	if [ ! -z "${generator_arch}" ]; then
		generator_arch_option="-A${generator_arch} "
	fi

	toolset_option=""
	if [ ! -z "${toolset}" ]; then
		# On macOS, only valid for Xcode generator
		if [[ $(isMac; echo $?) -eq 0 && "${generator}" != "Xcode" ]]; then
			echo "The toolset option (-t) is only valid for Xcode generator on macOS"
			exit 4
		fi
		if [ ! -z "${toolchain}" ]; then
			toolset_option="-T${toolset},host=${toolchain} "
		else
			toolset_option="-T${toolset} "
		fi
	fi
fi

if [[ $(type -t extend_gc_fnc_precmake) == function ]]; then
	extend_gc_fnc_precmake
fi

echo "/--------------------------\\"
echo "| Generating cmake project"
echo "| - GENERATOR: ${generator}"
echo "| - PLATFORM: ${platform}"
echo "| - ARCH: ${arch[@]}"
if [ ! -z "${toolset}" ]; then
	echo "| - TOOLSET: ${toolset}"
fi
if [ ! -z "${toolchain}" ]; then
	echo "| - TOOLCHAIN: ${toolchain}"
fi
if [ ! -z "${cmake_config}" ]; then
	echo "| - BUILD TYPE: ${cmake_config}"
fi
if [[ $(type -t extend_gc_fnc_props_summary) == function ]]; then
	extend_gc_fnc_props_summary
fi
echo "\\--------------------------/"
echo ""

"$cmake_path" -H. -B"${outputFolder}" "-G${generator}" $generator_arch_option $toolset_option $cmake_opt "${add_cmake_opt[@]}"

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
if [ -z "${cmake_config}" ]; then
	workspace_name="${projectName}_${arch[@]}"
else
	workspace_name="${projectName}_${arch[@]}_${cmake_config}"
fi
generate_vscode_workspace "${workspace_name}" "${outputFolder}" "${cmake_config}"

if [ $? -ne 0 ]; then
	echo ""
	echo "Something went wrong, check log"
else
	echo ""
	echo "All done, generated project lies in ${outputFolder}"
fi
