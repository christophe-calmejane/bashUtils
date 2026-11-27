# Useful script to publish a NuGet package
# Set selfFolderPath variable before calling this script to the absolute path of the calling script
# Set nugetPackages array variable before calling this script to the names of the packages the calling script can publish (optional). When set, the -package option is mandatory and the extend_pn_fnc_select_package function must be defined.
# The following functions can be defined before including this script:
#   extend_pn_fnc_help() -> Called when -h is requested. No return value
#   extend_pn_fnc_unhandled_arg() -> Called when an unhandled argument is found. Return the count of consumed args
#   extend_pn_fnc_select_package() -> Called after parsing all arguments, with the name of the package selected with -package. No return value
#     It must set either libName (the package contains the C# bindings of the library, see -l) or targetName (see -t), and can set packageName (see -n).
#     It can append the CMake options required to build the package to the add_cmake_opt array (options passed after -- on the command line override them).
#     It is also called with -meta (doMeta=1), in which case only the package names are used.

PN_Version="1.6"

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
targetName=""
packageName=""
selectedPackage=""
outputFolderSet=0
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
			if [ ${#nugetPackages[@]} -gt 0 ]; then
				echo " -o <folder> -> Output folder (Default: ${defaultOutputFolder}_<package name>)"
			else
				echo " -o <folder> -> Output folder (Default: ${defaultOutputFolder})"
			fi
			echo " -c <config> -> Configuration type (Default: ${defaultConfigType})"
			echo " -s <source> -> NuGet source (Mandatory)"
			echo " -k <apiKey> -> NuGet API key (Optional if credentials are set in the NuGet.config file)"
			if [ ${#nugetPackages[@]} -gt 0 ]; then
				echo " -package <name> -> Package to publish (Mandatory): ${nugetPackages[*]}"
			else
				echo " -l <libName> -> C# library name, publishing the C# bindings of the library (Mandatory unless -t is used)"
				echo " -t <target> -> CMake target whose NuGet package is published, using its '<target>-nuget-push' target (Mandatory unless -l is used)"
				echo " -n <packageName> -> Base name of the published packages, used by -meta (Default: the -l or -t value)"
			fi
			echo " -meta -> Don't build anything, generate and publish the meta-package referencing all the RID specific packages already published on the source (see publish_nuget_meta.sh)"
			echo " -v <version> -> Version of the meta-package, only used with -meta (Default: highest version found)"
			echo " -arch <arch> -> Architecture to build (Default: x64 on Windows, all archs on macOS, x64 on Linux)"
			echo " -no-clean -> Don't remove temp build folder [Default=clean on successful build]"
			echo " -no-rebuild -> Don't rebuild the whole solution [Default=rebuild everything]"
			if [[ $(type -t extend_pn_fnc_help) == function ]]; then
				extend_pn_fnc_help
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
			outputFolderSet=1
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
			targetName="$1"
			;;
		-n)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -n option, see help (-h)"
				exit 4
			fi
			packageName="$1"
			;;
		-package)
			shift
			if [ $# -lt 1 ]; then
				echo "ERROR: Missing parameter for -package option, see help (-h)"
				exit 4
			fi
			selectedPackage="$1"
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
			consumed_args=0
			if [[ $(type -t extend_pn_fnc_unhandled_arg) == function ]]; then
				extend_pn_fnc_unhandled_arg "$@"
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

# Let the calling script configure the selected package
if [ ${#nugetPackages[@]} -gt 0 ]; then
	if [ -z "$selectedPackage" ]; then
		echo "Package to publish is mandatory, please provide it using -package option (${nugetPackages[*]})."
		exit 1
	fi
	if [[ " ${nugetPackages[*]} " != *" ${selectedPackage} "* ]]; then
		echo "Unknown package '${selectedPackage}', must be one of: ${nugetPackages[*]}"
		exit 1
	fi
	if [ -n "$libName" ] || [ -n "$targetName" ] || [ -n "$packageName" ]; then
		echo "Options -l, -t and -n cannot be used with -package."
		exit 1
	fi
	if [[ $(type -t extend_pn_fnc_select_package) != function ]]; then
		echo "ERROR: extend_pn_fnc_select_package function must be defined when nugetPackages is set."
		exit 1
	fi
	# Options passed on the command line must come last to override the package ones
	declare -a bu_pn_commandLineCmakeOpt=("${add_cmake_opt[@]}")
	add_cmake_opt=()
	extend_pn_fnc_select_package "$selectedPackage"
	add_cmake_opt+=("${bu_pn_commandLineCmakeOpt[@]}")
	# Use a dedicated output folder for each package, so they can be built side by side
	if [ $outputFolderSet -eq 0 ]; then
		outputFolder="${defaultOutputFolder}_${selectedPackage}"
	fi
elif [ -n "$selectedPackage" ]; then
	echo "Option -package is not supported, no package list (nugetPackages) defined by the calling script."
	exit 1
fi

# Error if the nugetSource is empty
if [ -z "$nugetSource" ]; then
	echo "NuGet source is mandatory, please provide it using -s option."
	exit 1
fi

# Require exactly one package target selection
if [ -z "$libName" ] && [ -z "$targetName" ]; then
	echo "Library name (-l) or CMake target (-t) is mandatory."
	exit 1
fi
if [ -n "$libName" ] && [ -n "$targetName" ]; then
	echo "Options -l and -t are mutually exclusive."
	exit 1
fi
if [ -n "$libName" ]; then
	publishTargetName="${libName}-csharp-nuget-push"
	if [ -z "$packageName" ]; then
		packageName="$libName"
	fi
else
	publishTargetName="${targetName}-nuget-push"
	if [ -z "$packageName" ]; then
		packageName="$targetName"
	fi
fi

# Meta-package mode: nothing to build, delegate to the dedicated script (run from the caller folder so its NuGet.config files are used)
if [ $doMeta -eq 1 ]; then
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
