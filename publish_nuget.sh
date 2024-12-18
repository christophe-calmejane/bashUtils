#!/usr/bin/env bash
# Useful script to publish a C# NuGet package

PN_Version="1.0"

echo "Publish Nuget version $PN_Version"
echo ""

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
add_cmake_opt=()

while [ $# -gt 0 ]
do
	case "$1" in
		-h)
			echo "Usage: publish_nuget.sh [options] -- [cmake options]"
			echo "Everything passed after -- will be passed directly to the cmake command"
			echo "Available options:"
			echo " -h -> Display this help"
			echo " -o <folder> -> Output folder (Default: ${defaultOutputFolder})"
			echo " -c <config> -> Configuration type (Default: ${defaultConfigType})"
			echo " -s <source> -> NuGet source (Mandatory)"
			echo " -k <apiKey -> NuGet API key (Mandatory)"
			echo " -l <libName> -> Library name (Mandatory)"
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

# Error if the output folder already exists
if [ -d $outputFolder ]; then
	echo "Output folder already exists ($outputFolder). Please remove it before running this script."
	exit 1
fi

# Error if the nugetSource is empty
if [ -z "$nugetSource" ]; then
	echo "NuGet source is mandatory, please provide it using -s option."
	exit 1
fi

# Error if the nugetApiKey is empty
if [ -z "$nugetApiKey" ]; then
	echo "NuGet API key is mandatory, please provide it using -k option."
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

# On windows, use x64 architecture
if isWindows; then
	params+=("-arch" "x64")
# On macOS, use all archs and Ninja generator
elif isMac; then
	params+=("-all-archs")
	params+=("-c" "Ninja")
	params+=("-${configType,,}")
# On Linux, use x64 architecture and Ninja generator
elif isLinux; then
	params+=("-arch" "x64")
	params+=("-c" "Ninja")
	params+=("-${configType,,}")
fi

# Generate solution
$SHELL "${bu_pn_selfFolderPath}gen_cmake.sh" -o $outputFolder ${params[@]} -- "${add_cmake_opt[@]}"

# Build and publish
cmake --build $outputFolder --target $publishTargetName --config $configType
