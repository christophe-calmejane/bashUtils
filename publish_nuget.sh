#!/usr/bin/env bash
# Useful script to publish a C# NuGet package

PN_Version="1.3"

echo "Publish Nuget version $PN_Version"
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
bu_pn_callerFolderPath="$selfFolderPath"
# Check if bu_pn_callerFolderPath ends with /
if [[ "${bu_pn_callerFolderPath: -1}" != "/" ]]; then
	bu_pn_callerFolderPath="$bu_pn_callerFolderPath/"
fi

# Get absolute folder for this script
bu_pn_selfFolderPath="`cd "${BASH_SOURCE[0]%/*}"; pwd -P`/" # Command to get the absolute path

# Include util functions
. "${bu_pn_selfFolderPath}utils.sh"

# Default values
defaultOutputFolder="_publish"
defaultConfigType="Release"

# Parse variables
outputFolder="$defaultOutputFolder"
configType="$defaultConfigType"
nugetSource=""
nugetApiKey=""
libName=""
doRebuild=1
force_arch=""
add_cmake_opt=()
doCleanup=1

while [ $# -gt 0 ]
do
	case "$1" in
		-h)
			echo "Usage: publish_nuget.sh [options] -- [cmake options]"
			echo "Everything passed after -- will be passed directly to the gen_cmake command"
			echo "Available options:"
			echo " -h -> Display this help"
			echo " -o <folder> -> Output folder (Default: ${defaultOutputFolder})"
			echo " -c <config> -> Configuration type (Default: ${defaultConfigType})"
			echo " -s <source> -> NuGet source (Mandatory)"
			echo " -k <apiKey> -> NuGet API key (Optional if credentials are set in the NuGet.config file)"
			echo " -l <libName> -> Library name (Mandatory)"
			echo " -arch <arch> -> Architecture to build (Default: x64 on Windows, all archs on macOS, x64 on Linux)"
			echo " -no-clean -> Don't remove temp build folder [Default=clean on successful build]"
			echo " -no-rebuild -> Don't rebuild the whole solution [Default=rebuild everything]"
			exit 3
			;;
		-o)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -o option, see help (-h)"
				exit 4
			fi
			outputFolder="$1"
			;;
		-c)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -c option, see help (-h)"
				exit 4
			fi
			configType="$1"
			;;
		-s)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -s option, see help (-h)"
				exit 4
			fi
			nugetSource="$1"
			;;
		-k)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -k option, see help (-h)"
				exit 4
			fi
			nugetApiKey="$1"
			;;
		-l)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -l option, see help (-h)"
				exit 4
			fi
			libName="$1"
			;;
		-arch)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -arch option, see help (-h)"
				exit 4
			fi
			force_arch="$1"
			;;
		-no-clean)
			doCleanup=0
			;;
		-no-rebuild)
			doRebuild=0
			;;
		--)
			shift
			while [ $# -gt 0 ]
			do
				# Ignore another "--" if present
				if [ "$1" == "--" ]; then
					shift
					continue
				fi
				add_cmake_opt+=("$1")
				shift
			done
			break
			;;
		*)
			echo "ERROR: Unknown option '$1' (use -h for help)"
			exit 4
			;;
	esac
	shift
done

# Error if the nugetSource is empty
if [ -z "$nugetSource" ]; then
	echo "NuGet source is mandatory, please provide it using -s option."
	exit 1
fi

# Error if the libName is empty
if [ -z "$libName" ]; then
	echo "Library name is mandatory, please provide it using -l option."
	exit 1
fi

publishTargetName=${libName}-csharp-nuget-push

# Additional cmake parameters
add_cmake_opt+=("-DNUGET_PUBLISH_SOURCE_URL=$nugetSource" "-DNUGET_PUBLISH_API_KEY=$nugetApiKey")

# Additional gen_cmake parameters
declare -a params=()

# Architecture to build
if [ -n "$force_arch" ]; then
	params+=("-arch" "$force_arch")
else
	# On windows, use x64 architecture
	if isWindows; then
		params+=("-arch" "x64")
	# On macOS, use all archs and Ninja generator
	elif isMac; then
		params+=("-all-archs") # Force multi-arch build
		params+=("-c" "Ninja")
		params+=("-${configType,,}")
	# On Linux, use x64 architecture and Ninja generator
	elif isLinux; then
		params+=("-arch" "x64")
		params+=("-c" "Ninja")
		params+=("-${configType,,}")
	fi
fi

# Build config
# On macOS, use Ninja generator
if isMac; then
	params+=("-c" "Ninja")
	params+=("-${configType,,}")
# On Linux, use Ninja generator
elif isLinux; then
	params+=("-c" "Ninja")
	params+=("-${configType,,}")
fi

# Cleanup routine
cleanup_main()
{
	if [[ $doCleanup -eq 1 && $1 -eq 0 ]]; then
		echo -n "Cleaning... "
		sleep 2
		rm -rf "${bu_pn_callerFolderPath}${outputFolder}"
		echo "done"
	else
		echo "Not cleaning up as requested, folder '${outputFolder}' untouched"
	fi
	exit $1
}

trap 'cleanup_main $?' EXIT

# Cleanup previous build folders, just in case
if [ $doRebuild -eq 1 ]; then
	rm -rf "${bu_pn_callerFolderPath}${outputFolder}"
fi

# Generate solution
. "${bu_pn_selfFolderPath}gen_cmake.sh" -o $outputFolder ${params[@]} -- "${add_cmake_opt[@]}"

# Build and publish
cmake --build $outputFolder --target $publishTargetName --config $configType
