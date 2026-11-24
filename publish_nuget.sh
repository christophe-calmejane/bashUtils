# Useful script to publish a NuGet package

PN_Version="1.5"

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
cmake_path=""

# Find cmake path
getCmakePath "cmake_path"

# Parse variables
outputFolder="$defaultOutputFolder"
configType="$defaultConfigType"
nugetSource=""
nugetApiKey=""
libName=""
publishTargetName=""
packageName=""
metaVersion=""
doMeta=0
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
			echo " -l <libName> -> C# library name (Mandatory unless -t is used)"
			echo " -t <target> -> CMake NuGet push target (Mandatory unless -l is used)"
			echo " -n <packageName> -> Base name of the published packages, used by -meta (Default: the -l value)"
			echo " -meta -> Don't build anything, generate and publish the meta-package referencing all the RID specific packages already published on the source (see publish_nuget_meta.sh)"
			echo " -v <version> -> Version of the meta-package, only used with -meta (Default: highest version found)"
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
		-t)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -t option, see help (-h)"
				exit 4
			fi
			publishTargetName="$1"
			;;
		-n)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -n option, see help (-h)"
				exit 4
			fi
			packageName="$1"
			;;
		-meta)
			doMeta=1
			;;
		-v)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -v option, see help (-h)"
				exit 4
			fi
			metaVersion="$1"
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

# Require exactly one package target selection
if [ -z "$libName" ] && [ -z "$publishTargetName" ]; then
	echo "Library name (-l) or NuGet push target (-t) is mandatory."
	exit 1
fi
if [ -n "$libName" ] && [ -n "$publishTargetName" ]; then
	echo "Options -l and -t are mutually exclusive."
	exit 1
fi
if [ -z "$publishTargetName" ]; then
	publishTargetName=${libName}-csharp-nuget-push
fi

# Meta-package mode: nothing to build, delegate to the dedicated script (run from the caller folder so its NuGet.config files are used)
if [ $doMeta -eq 1 ]; then
	if [ -z "$packageName" ]; then
		packageName="$libName"
	fi
	if [ -z "$packageName" ]; then
		echo "Package name (-n) is mandatory with -meta when -t is used."
		exit 1
	fi
	declare -a metaParams=("-n" "$packageName" "-s" "$nugetSource" "-c" "$configType" "-o" "${bu_pn_callerFolderPath}${outputFolder}")
	if [ -n "$nugetApiKey" ]; then
		metaParams+=("-k" "$nugetApiKey")
	fi
	if [ -n "$metaVersion" ]; then
		metaParams+=("-v" "$metaVersion")
	fi
	if [ $doCleanup -eq 0 ]; then
		metaParams+=("-no-clean")
	fi
	(cd "$bu_pn_callerFolderPath" && "${bu_pn_selfFolderPath}publish_nuget_meta.sh" "${metaParams[@]}")
	exit $?
fi

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
. "${bu_pn_selfFolderPath}gen_cmake.sh" -o "$outputFolder" "${params[@]}" -- "${add_cmake_opt[@]}"

# Build and publish
"$cmake_path" --build "$outputFolder" --target "$publishTargetName" --config "$configType"
