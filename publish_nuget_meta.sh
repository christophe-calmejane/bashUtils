#!/usr/bin/env bash
# Useful script to generate and publish a NuGet meta-package referencing all the RID specific packages (<PackageName>[-debug]-<RID>) already published on a NuGet source
# The meta-package must be published again for each new version of the RID specific packages, once all of them have been published.
# Can be called directly, or through publish_nuget.sh with the -meta option.

PNM_Version="1.0"

echo "Publish NuGet meta-package version $PNM_Version"
echo ""

# Get absolute folder for this script
bu_pnm_selfFolderPath="`cd "${BASH_SOURCE[0]%/*}"; pwd -P`/" # Command to get the absolute path

# Include util functions
. "${bu_pnm_selfFolderPath}utils.sh"

# Default values
defaultOutputFolder="_publish_meta"
defaultConfigType="Release"
cmake_path=""

# Find cmake path
getCmakePath "cmake_path"

# Parse variables
outputFolder="$defaultOutputFolder"
configType="$defaultConfigType"
nugetSource=""
nugetApiKey=""
packageName=""
metaVersion=""
doPush=1
doCleanup=1

while [ $# -gt 0 ]
do
	case "$1" in
		-h)
			echo "Usage: publish_nuget_meta.sh [options]"
			echo "Available options:"
			echo " -h -> Display this help"
			echo " -n <packageName> -> Base name of the packages, without the -debug and -<RID> suffixes (Mandatory)"
			echo " -s <source> -> NuGet source (name of a configured source, URL or folder) to search the RID specific packages in and to push the meta-package to (Mandatory)"
			echo " -k <apiKey> -> NuGet API key (Optional if credentials are set in the NuGet.config file)"
			echo " -c <config> -> Configuration type, Debug adds the -debug suffix to all package IDs (Default: ${defaultConfigType})"
			echo " -v <version> -> Version of the meta-package, must be published for at least one RID (Default: highest version found)"
			echo " -o <folder> -> Temporary work folder (Default: ${defaultOutputFolder})"
			echo " -no-push -> Only generate the meta-package, don't push it"
			echo " -no-clean -> Don't remove the work folder [Default=clean on success]"
			echo "The NuGet.config files are searched from the current folder."
			exit 3
			;;
		-n)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -n option, see help (-h)"
				exit 4
			fi
			packageName="$1"
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
		-c)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -c option, see help (-h)"
				exit 4
			fi
			configType="$1"
			;;
		-v)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -v option, see help (-h)"
				exit 4
			fi
			metaVersion="$1"
			;;
		-o)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -o option, see help (-h)"
				exit 4
			fi
			outputFolder="$1"
			;;
		-no-push)
			doPush=0
			;;
		-no-clean)
			doCleanup=0
			;;
		*)
			echo "ERROR: Unknown option '$1' (use -h for help)"
			exit 4
			;;
	esac
	shift
done

if [ -z "$packageName" ]; then
	echo "Package name is mandatory, please provide it using -n option."
	exit 1
fi
if [ -z "$nugetSource" ]; then
	echo "NuGet source is mandatory, please provide it using -s option."
	exit 1
fi
if [[ "$configType" != "Debug" && "$configType" != "Release" ]]; then
	echo "Configuration type must be Debug or Release."
	exit 1
fi

# Get the absolute paths of the work folder and the current folder, in a form usable by CMake
mkdir -p "${outputFolder}"
workFolderPath=""
getFolderAbsoluteOSDependantPath "workFolderPath" "${outputFolder}"
searchFolderPath=""
getFolderAbsoluteOSDependantPath "searchFolderPath" "."

pushValue="ON"
if [ $doPush -eq 0 ]; then
	pushValue="OFF"
fi

"$cmake_path" \
	"-DMETA_PACKAGE_NAME=${packageName}" \
	"-DNUGET_SOURCE=${nugetSource}" \
	"-DNUGET_API_KEY=${nugetApiKey}" \
	"-DCONFIG_TYPE=${configType}" \
	"-DMETA_VERSION=${metaVersion}" \
	"-DWORK_FOLDER=${workFolderPath}" \
	"-DSEARCH_FOLDER=${searchFolderPath}" \
	"-DPUSH=${pushValue}" \
	-P "${bu_pnm_selfFolderPath}supportFiles/nugetMetaPackage.cmake"
result=$?

if [ $result -ne 0 ]; then
	# Only keep the work folder if the generation started
	rmdir "${outputFolder}" 2> /dev/null
	if [ -d "${outputFolder}" ]; then
		echo "Failed to generate the meta-package, work folder '${outputFolder}' untouched"
	else
		echo "Failed to generate the meta-package"
	fi
	exit $result
fi

if [ $doCleanup -eq 1 ]; then
	rm -rf "${outputFolder}"
fi

exit 0
