# Useful script to generate an AppImage for a Linux cmake project
# Set cmake_opt variable before calling this script to set cmake defines
# Set selfFolderPath variable before calling this script to the absolute path of the calling script
#
# Required variables (must be set before sourcing this script):
#   selfFolderPath - absolute path of the calling script's directory (with trailing /)
#   cmake_opt - cmake defines for the project
#   appimage_app_name - application name (used for naming the AppImage and .desktop file)
#   appimage_executable - relative path to the main executable inside the build directory
#   appimage_icon - path to the application icon (PNG), absolute or relative to CWD
#
# Optional variables:
#   appimage_use_qt_plugin - set to 1 to use linuxdeploy-plugin-qt (default: 0)
#   appimage_additional_libs - array of additional library paths to bundle (e.g. libpcap, filled by caller)
#   appimage_desktop_file - path to a custom .desktop file (default: auto-generated from variables below)
#   appimage_custom_apprun - path to a custom AppRun script (default: bundled generic AppRun.appimage)
#   appimage_categories - .desktop Categories value (default: "Utility;")
#   appimage_comment - .desktop Comment value (default: "")
#   appimage_mime_types - .desktop MimeType value (default: "")
#   appimage_setcap_capability - file capability string for setcap at install time, e.g. "cap_net_raw+ep" (default: "" = no setcap)
#   appimage_linuxdeploy_url - override download URL for linuxdeploy (default: GitHub continuous release)
#   appimage_linuxdeploy_qt_url - override download URL for linuxdeploy-plugin-qt (default: GitHub continuous release)
#
# The following functions can be defined before including this script:
#   extend_ga_fnc_help() -> Called when -h is requested. No return value
#   extend_ga_fnc_defaults() -> Called when default values are initialized. Override default global values from the function. No return value
#     - default_buildArch -> Default build architecture to use. Default is the host architecture
#     - default_keyDigits -> The number of digits to be used as Key for installation. Default is 2
#     - default_betaTagName -> The tag to use before the 4th digit for beta releases. Default is "-beta"
#   extend_ga_fnc_unhandled_arg() -> Called when an unhandled argument is found. Return the count of consumed args
#   extend_ga_fnc_postparse() -> Called after parsing all arguments. No return value
#   extend_ga_fnc_setup_env() -> Called before running linuxdeploy. Set up environment variables (LD_LIBRARY_PATH, QMAKE, etc.). No return value
#   extend_ga_fnc_customize_appdir(appDirPath) -> Called after AppDir is prepared but before linuxdeploy runs. Add custom files to the AppDir. No return value
#   extend_ga_fnc_props_summary() -> Called when printing build properties summary. No return value

GA_GeneratorVersion="1.0"

echo "AppImage Generator version $GA_GeneratorVersion"
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
bu_ga_callerFolderPath="$selfFolderPath"
# Check if bu_ga_callerFolderPath ends with /
if [[ "${bu_ga_callerFolderPath: -1}" != "/" ]]; then
	bu_ga_callerFolderPath="$bu_ga_callerFolderPath/"
fi

# Get absolute folder for this script
bu_ga_selfFolderPath="`cd "${BASH_SOURCE[0]%/*}"; pwd -P`/" # Command to get the absolute path

# Include utils functions
. "${bu_ga_selfFolderPath}utils.sh"

# Sanity checks
envSanityChecks "grep"

# Only Linux is supported for AppImage generation
if ! isLinux; then
	echo "ERROR: AppImage generation is only supported on Linux"
	exit 4
fi

# Validate required variables
if [ -z "$appimage_app_name" ]; then
	echo "ERROR: appimage_app_name variable not set"
	exit 4
fi
if [ -z "$appimage_executable" ]; then
	echo "ERROR: appimage_executable variable not set"
	exit 4
fi
if [ -z "$appimage_icon" ]; then
	echo "ERROR: appimage_icon variable not set"
	exit 4
fi

# Default values
default_keyDigits=2
default_betaTagName="-beta"
appimage_use_qt_plugin=${appimage_use_qt_plugin:-0}
appimage_categories=${appimage_categories:-"Utility;"}
appimage_comment=${appimage_comment:-""}
appimage_mime_types=${appimage_mime_types:-""}
appimage_setcap_capability=${appimage_setcap_capability:-""}
appimage_custom_apprun=${appimage_custom_apprun:-"${bu_ga_selfFolderPath}AppRun.appimage"}

# Check for defaults override
if [[ $(type -t extend_ga_fnc_defaults) == function ]]; then
	extend_ga_fnc_defaults
fi

# Variables
cmake_path=""
platform=""
default_arch=""
declare -a arch=()
outputFolderBasePath="_appimage"
defaultOutputFolder="${outputFolderBasePath}_<platform>_<arch>_<generator>_<config>"
deliverablesFolder="_deliverables"
declare -a supportedArchs=()

getCmakePath cmake_path

generator="Unix Makefiles"
# If a default architecture is set, use it. Otherwise, use the host architecture
if [ -z "$default_buildArch" ]; then
	getMachineArch default_arch
else
	default_arch="$default_buildArch"
fi
supportedArchs+=("${default_arch}")
getOS platform

# Parse variables
outputFolder=""
buildConfig="Release"
buildConfigOverride=0
doCleanup=1
doRebuild=1
doNoStrip=0
listArchs=0
useAllArchs=0
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
			echo "Usage: gen_appimage.sh [options]"
			echo " -h -> Display this help"
			echo " -v -> Print script version and exit"
			echo " -o <folder> -> Output build folder (Default: ${defaultOutputFolder})"
			echo " -d <deliverables folder> -> Force deliverables output folder (Default: $deliverablesFolder)"
			echo " -a <flags> -> Add cmake flags directly passed to underlying gen_cmake.sh"
			echo " -b <cmake path> -> Force cmake binary path (Default: $cmake_path)"
			echo " -c <cmake generator> -> Force cmake generator (Default: $generator)"
			echo " -arch <arch> -> Set target architecture (Default: $default_arch)"
			echo " -archs -> List supported architectures"
			echo " -no-clean -> Don't remove temp build folder [Default=clean on successful build]"
			echo " -no-rebuild -> Don't rebuild the whole solution [Default=rebuild everything]"
			echo " -no-strip -> Don't strip binaries in AppImage [Default=strip]"
			echo " -debug -> Compile using Debug configuration (Default: Release)"
			echo " -key-digits <Number of digits> -> The number of digits to be used as Key for installation, comprised between 0 and 4 (Default: $default_keyDigits)"
			echo " -key-postfix <Postfix> -> Postfix string to be added to the Key for installation (Default: \"\")"
			echo " -marketing-version <Version> -> Set the marketing version to use (Default: Generated from CMakeLists.txt)"
			echo " -beta-tag <BetaTag> -> Set the beta tag to use before the 4th digit (Default: $default_betaTagName)"
			if [[ $(type -t extend_ga_fnc_help) == function ]]; then
				extend_ga_fnc_help
			fi
			exit 3
			;;
		-v)
			exit 0
			;;
		-o)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -o option, see help (-h)"
				exit 4
			fi
			outputFolder="$1"
			;;
		-d)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -d option, see help (-h)"
				exit 4
			fi
			deliverablesFolder="$1"
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
			generator="$1"
			gen_cmake_additional_options+=("-c")
			gen_cmake_additional_options+=("$1")
			;;
		-arch)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -arch option, see help (-h)"
				exit 4
			fi
			arch=("$1")
			gen_cmake_additional_options+=("-arch")
			gen_cmake_additional_options+=("$1")
			;;
		-archs)
			listArchs=1
			;;
		-no-clean)
			doCleanup=0
			;;
		-no-rebuild)
			doRebuild=0
			;;
		-no-strip)
			doNoStrip=1
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
			if [[ $(type -t extend_ga_fnc_unhandled_arg) == function ]]; then
				extend_ga_fnc_unhandled_arg $@
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

if [[ $(type -t extend_ga_fnc_postparse) == function ]]; then
	extend_ga_fnc_postparse
fi

# Ensure deliverablesFolder ends with /
if [[ ${deliverablesFolder: -1} != "/" ]]; then
	deliverablesFolder="$deliverablesFolder/"
fi

# Remove duplicates from supported archs
removeDuplicates supportedArchs

# List supported archs
if [ $listArchs -eq 1 ]; then
	echo "Supported archs for platform ${platform} (Default arch marked with [*]):"
	for a in "${supportedArchs[@]}"; do
		if [[ " ${default_arch[@]} " =~ " ${a} " ]]; then
			echo " [*] $a"
		else
			echo "     $a"
		fi
	done
	exit 0
fi

# No arch was specified on command line, use default arch
if [ ${#arch[*]} -eq 0 ]; then
	arch=(${default_arch[@]})
	# Don't forward default arch to gen_cmake, let it use its own defaults
fi

# Check arch is valid for target platform
for a in "${arch[@]}"; do
	if [[ ! " ${supportedArchs[@]} " =~ " ${a} " ]]; then
		echo "ERROR: Unsupported arch for platform ${platform}: ${a} (Supported archs: ${supportedArchs[@]})"
		exit 4
	fi
done

# Concatenate all archs into one string
printf -v arch_list "%s_" "${arch[@]}"
arch_list="${arch_list%_}"

# Map architecture for linuxdeploy download
getLinuxDeployArch()
{
	local _retval="$1"
	local _arch="$2"
	local result=""

	case "$_arch" in
		x64)
			result="x86_64"
			;;
		arm64)
			result="aarch64"
			;;
		*)
			echo "ERROR: Unsupported architecture for AppImage: $_arch"
			exit 4
			;;
	esac

	eval $_retval="'${result}'"
}

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

# Compute output folder if not specified
if [ -z "$outputFolder" ]; then
	getOutputFolder outputFolder "${outputFolderBasePath}" "${platform}" "${arch_list}" "" "${buildConfig}" "${generator}"
fi

# Cleanup routine
cleanup_appimage()
{
	if [[ $doCleanup -eq 1 && $1 -eq 0 ]]; then
		echo -n "Cleaning build folder... "
		sleep 2
		rm -rf "${bu_ga_callerFolderPath}${outputFolder}"
		echo "done"
	else
		echo "Build folder '${outputFolder}' left in place"
	fi
	exit $1
}

trap 'cleanup_appimage $?' EXIT

# We must add a cmake parameter when using Single-Configuration generators
if isSingleConfigurationGenerator "$generator"; then
	gen_cmake_additional_options+=("-${buildConfig,,}")
fi

# Get project info from CMakeLists.txt
projectName="$(grep -Po "project *\( *(\K[^\"][^ )]+|\"\K[^\"]+)" "CMakeLists.txt")"
if [[ $projectName == "" ]]; then
	echo "Cannot detect project name"
	exit 1
fi
projectName="${projectName//[$'\t\r\n']}"
projectName="${projectName/#la_/}"

cmakeVersion=$(grep -m 1 -Po "set *\(.+_VERSION +\K[0-9]+(\.[0-9]+)+(?= *\))" CMakeLists.txt)
if [[ $cmakeVersion == "" ]]; then
	echo "Cannot detect project version"
	exit 1
fi
cmakeVersion="${cmakeVersion//[$'\t\r\n']}"

# Parse version
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
if [ ${#versionSplit[*]} -eq 4 ]; then
	beta_tag="${betaTagName}${versionSplit[3]}"
	build_tag="+$(git rev-parse --short HEAD)"
	is_release=0
fi

# Build AppImage base name
if [ -n "$marketing_version" ]; then
	appimageBaseName="${appimage_app_name}-${marketing_version}${beta_tag}${build_tag}"
else
	appimageBaseName="${appimage_app_name}-${releaseVersion}${beta_tag}${build_tag}"
fi
if [ -n "$marketing_version" ]; then
	appimageBaseName="${appimageBaseName}+${cmakeVersion}"
fi
appimageBaseName="${appimageBaseName}+Linux"
if [ $buildConfigOverride -eq 1 ]; then
	appimageBaseName="${appimageBaseName}+${buildConfig}"
fi

# Resolve linuxdeploy architecture name
linuxdeploy_arch=""
getLinuxDeployArch linuxdeploy_arch "${arch[0]}"

# Determine linuxdeploy download URLs
linuxdeploy_url="${appimage_linuxdeploy_url:-https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${linuxdeploy_arch}.AppImage}"
linuxdeploy_qt_url="${appimage_linuxdeploy_qt_url:-https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-${linuxdeploy_arch}.AppImage}"

# Print build properties summary
echo "/--------------------------\\"
echo "| AppImage properties summary"
echo "| - CMAKE VERS: $("$cmake_path" --version | grep -oP '\d+(\.\d+)+')"
echo "| - GENERATOR: ${generator}"
echo "| - PLATFORM: ${platform}"
echo "| - ARCH: ${arch[@]}"
echo "| - BUILD TYPE: ${buildConfig}"
echo "| - APP NAME: ${appimage_app_name}"
echo "| - EXECUTABLE: ${appimage_executable}"
echo "| - QT PLUGIN: $([ $appimage_use_qt_plugin -eq 1 ] && echo 'Yes' || echo 'No')"
echo "| - NO STRIP: $([ $doNoStrip -eq 1 ] && echo 'Yes' || echo 'No')"
if [[ $(type -t extend_ga_fnc_props_summary) == function ]]; then
	extend_ga_fnc_props_summary
fi
echo "\\--------------------------/"
echo ""

# Cleanup previous build folder if rebuilding
if [ $doRebuild -eq 1 ]; then
	rm -rf "${bu_ga_callerFolderPath}${outputFolder}"
fi

# Create deliverables folder
mkdir -p "$deliverablesFolder"

# Step 1: Configure with gen_cmake.sh
echo -n "Generating cmake files... "
log=$(./gen_cmake.sh -o "${outputFolder}" "${gen_cmake_additional_options[@]}" -f "$cmake_opt" -- "${cmake_additional_options[@]}")
if [ $? -ne 0 ]; then
	echo "FAILED"
	echo ""
	echo "$log"
	exit 1
fi
echo "done"

# Step 2: Build the project
echo -n "Building project... "
log=$("$cmake_path" --build "${outputFolder}" -j "$(nproc)" --config "${buildConfig}")
if [ $? -ne 0 ]; then
	echo "FAILED"
	echo ""
	echo "$log"
	exit 1
fi
echo "done"

# Step 3: Download linuxdeploy tools into the build directory
linuxdeploy_bin="${outputFolder}/linuxdeploy-${linuxdeploy_arch}.AppImage"
linuxdeploy_qt_bin="${outputFolder}/linuxdeploy-plugin-qt-${linuxdeploy_arch}.AppImage"

echo -n "Downloading linuxdeploy... "
if [ ! -f "${linuxdeploy_bin}" ]; then
	wget -q -O "${linuxdeploy_bin}" "${linuxdeploy_url}"
	if [ $? -ne 0 ]; then
		echo "FAILED"
		echo "Failed to download linuxdeploy from: ${linuxdeploy_url}"
		exit 1
	fi
	chmod +x "${linuxdeploy_bin}"
fi
echo "done"

if [ $appimage_use_qt_plugin -eq 1 ]; then
	echo -n "Downloading linuxdeploy Qt plugin... "
	if [ ! -f "${linuxdeploy_qt_bin}" ]; then
		wget -q -O "${linuxdeploy_qt_bin}" "${linuxdeploy_qt_url}"
		if [ $? -ne 0 ]; then
			echo "FAILED"
			echo "Failed to download linuxdeploy-plugin-qt from: ${linuxdeploy_qt_url}"
			exit 1
		fi
		chmod +x "${linuxdeploy_qt_bin}"
	fi
	echo "done"
fi

# Step 4: Prepare linuxdeploy environment
# Get absolute output folder path for linuxdeploy (which runs from a different CWD)
outputFolderAbs="$(cd "${outputFolder}" && pwd -P)"

# Resolve icon to absolute path
appimage_icon_abs=""
if [[ "${appimage_icon}" == /* ]]; then
	appimage_icon_abs="${appimage_icon}"
else
	appimage_icon_abs="$(cd "$(dirname "${appimage_icon}")" && pwd)/$(basename "${appimage_icon}")"
fi
if [ ! -f "${appimage_icon_abs}" ]; then
	echo "ERROR: Icon file not found: ${appimage_icon_abs}"
	exit 4
fi

# Resolve desktop file to absolute path (if provided)
appimage_desktop_abs=""
if [ ! -z "$appimage_desktop_file" ]; then
	if [[ "${appimage_desktop_file}" == /* ]]; then
		appimage_desktop_abs="${appimage_desktop_file}"
	else
		appimage_desktop_abs="$(cd "$(dirname "${appimage_desktop_file}")" && pwd)/$(basename "${appimage_desktop_file}")"
	fi
	if [ ! -f "${appimage_desktop_abs}" ]; then
		echo "ERROR: Desktop file not found: ${appimage_desktop_abs}"
		exit 4
	fi
fi

# Set version for linuxdeploy (included in filename)
export LINUXDEPLOY_OUTPUT_VERSION="${releaseVersion}${beta_tag}${build_tag}"

# In Docker or without FUSE, use extract-and-run mode
if isInDocker; then
	export APPIMAGE_EXTRACT_AND_RUN=1
fi

# Set up LD_LIBRARY_PATH with the build lib directory
export LD_LIBRARY_PATH="${outputFolderAbs}/lib:${LD_LIBRARY_PATH:-}"

# Call project-specific environment setup
if [[ $(type -t extend_ga_fnc_setup_env) == function ]]; then
	extend_ga_fnc_setup_env
fi

# Step 5: Run linuxdeploy
echo -n "Generating AppImage... "

appDirPath="${outputFolderAbs}/AppDir"
rm -rf "${appDirPath}"
mkdir -p "${appDirPath}"

# Write version marker for persistent install tracking
echo "${LINUXDEPLOY_OUTPUT_VERSION}" > "${appDirPath}/.appimage_version"

# Call hook for project-specific AppDir customization
if [[ $(type -t extend_ga_fnc_customize_appdir) == function ]]; then
	extend_ga_fnc_customize_appdir "${appDirPath}"
fi

# Write runtime configuration file for AppRun
# This file is sourced by AppRun at install time to configure the persistent install
cat > "${appDirPath}/.appimage_config" << CONFIGEOF
# Auto-generated - do not edit
APP_NAME="${appimage_app_name}"
APP_BINARY="usr/bin/$(basename "${appimage_executable}")"
SETCAP_CAPABILITY="${appimage_setcap_capability}"
CONFIGEOF

# Bundle patchelf (needed at install time to rewrite $ORIGIN-based RPATHs to absolute paths,
# so that bundled libraries are isolated from system-installed versions and library resolution
# works under AT_SECURE when file capabilities are set via setcap)
local_patchelf=$(which patchelf 2>/dev/null)
if [ -n "$local_patchelf" ] && [ -x "$local_patchelf" ]; then
	mkdir -p "${appDirPath}/usr/bin"
	cp "$local_patchelf" "${appDirPath}/usr/bin/patchelf"
	chmod +x "${appDirPath}/usr/bin/patchelf"
else
	echo ""
	echo "WARNING: patchelf not found on the build system, it will not be bundled."
	echo "         RPATH rewriting at install time will only work if patchelf is available on the target system."
fi

# Auto-generate .desktop file if none was provided by the caller
if [ -z "${appimage_desktop_abs}" ]; then
	generated_desktop="${outputFolderAbs}/${appimage_app_name}.desktop"
	cat > "${generated_desktop}" << DESKTOPEOF
[Desktop Entry]
Type=Application
Name=${appimage_app_name}
Exec=${appimage_app_name}
Icon=${appimage_app_name}
Categories=${appimage_categories}
Terminal=false
StartupNotify=false
DESKTOPEOF
	if [ -n "${appimage_comment}" ]; then
		echo "Comment=${appimage_comment}" >> "${generated_desktop}"
	fi
	if [ -n "${appimage_mime_types}" ]; then
		echo "MimeType=${appimage_mime_types}" >> "${generated_desktop}"
	fi
	appimage_desktop_abs="${generated_desktop}"
fi

# Build linuxdeploy command (all paths must be absolute since we pushd before running)
declare -a linuxdeploy_cmd=()
linuxdeploy_cmd+=("${outputFolderAbs}/linuxdeploy-${linuxdeploy_arch}.AppImage")
linuxdeploy_cmd+=("--appdir" "${appDirPath}")
linuxdeploy_cmd+=("--executable" "${outputFolderAbs}/${appimage_executable}")
linuxdeploy_cmd+=("--icon-file" "${appimage_icon_abs}")

# Custom AppRun
if [ ! -z "$appimage_custom_apprun" ]; then
	local_apprun_abs=""
	if [[ "${appimage_custom_apprun}" == /* ]]; then
		local_apprun_abs="${appimage_custom_apprun}"
	else
		local_apprun_abs="$(cd "$(dirname "${appimage_custom_apprun}")" && pwd)/$(basename "${appimage_custom_apprun}")"
	fi
	if [ ! -f "${local_apprun_abs}" ]; then
		echo "ERROR: Custom AppRun not found: ${local_apprun_abs}"
		exit 4
	fi
	linuxdeploy_cmd+=("--custom-apprun" "${local_apprun_abs}")
fi

# Desktop file
if [ ! -z "${appimage_desktop_abs}" ]; then
	linuxdeploy_cmd+=("--desktop-file" "${appimage_desktop_abs}")
else
	linuxdeploy_cmd+=("--create-desktop-file")
fi

# Qt plugin
if [ $appimage_use_qt_plugin -eq 1 ]; then
	linuxdeploy_cmd+=("--plugin" "qt")
fi

# Additional libraries
if [ ${#appimage_additional_libs[@]} -gt 0 ]; then
	for lib in "${appimage_additional_libs[@]}"; do
		if [ -f "$lib" ]; then
			linuxdeploy_cmd+=("-l" "$lib")
		else
			echo ""
			echo "WARNING: Additional library not found, skipping: $lib"
		fi
	done
fi

# No strip
if [ $doNoStrip -eq 1 ]; then
	export NO_STRIP=1
fi

# Output
linuxdeploy_cmd+=("--output" "appimage")

# Run linuxdeploy from the output folder (it creates the AppImage in CWD)
pushd "${outputFolderAbs}" &> /dev/null
log=$("${linuxdeploy_cmd[@]}" 2>&1)
linuxdeploy_result=$?
popd &> /dev/null
if [ $linuxdeploy_result -ne 0 ]; then
	echo "FAILED"
	echo ""
	echo "$log"
	exit 1
fi
echo "done"

# Step 6: Move AppImage to deliverables
# linuxdeploy creates the AppImage in CWD (outputFolderAbs), named <AppName>-<VERSION>-<arch>.AppImage
generatedAppImage=$(ls "${outputFolderAbs}/${appimage_app_name}"*-"${linuxdeploy_arch}.AppImage" 2>/dev/null | head -1)
if [ -z "$generatedAppImage" ]; then
	# Try without version
	generatedAppImage=$(ls "${outputFolderAbs}/${appimage_app_name}"*".AppImage" 2>/dev/null | head -1)
fi

if [ -z "$generatedAppImage" ] || [ ! -f "$generatedAppImage" ]; then
	echo "ERROR: Cannot find generated AppImage file"
	echo "Expected pattern: ${appimage_app_name}*-${linuxdeploy_arch}.AppImage"
	doCleanup=0
	exit 1
fi

# Rename to our convention
finalAppImageName="${appimageBaseName}-${linuxdeploy_arch}.AppImage"
mv "$generatedAppImage" "${deliverablesFolder}${finalAppImageName}"

echo ""
echo "AppImage generated: ${deliverablesFolder}${finalAppImageName}"

exit 0
