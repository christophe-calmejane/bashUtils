#!/usr/bin/env bash

FIX_FILES_VERSION="2.1"

echo "Fix-Files version $FIX_FILES_VERSION"
echo ""

# Get absolute folder for this script
selfFolderPath="`cd "${BASH_SOURCE[0]%/*}"; pwd -P`/" # Command to get the absolute path

# Include util functions
. "${selfFolderPath}utils.sh"

# Check if a .git file or folder exists (we allow submodules, thus check file and folder), as well as a root cmake file
if [[ ! -e ".git" || ! -f "CMakeLists.txt" ]]; then
	echo "ERROR: Must be run from the root folder of your project (where your main CMakeLists.txt file is)"
	exit 1
fi

do_clang_format=1
do_line_endings=1
do_chmod=1

while [ $# -gt 0 ]
do
	case "$1" in
		-h)
			echo "Usage: fix_files.sh [options]"
			echo " -h -> Display this help"
			echo " --no-clang-format -> Do not run clang-format on source files (Default: Run clang-format, but only if .clang-format file found)"
			echo " --no-line-endings -> Do not force line endings on source files (Default: Change line-endings)"
			echo " --no-chmod -> Do not run chmod on all files to fix executable bit (Default: Run chmod)"
			exit 3
			;;
		--no-clang-format)
			do_clang_format=0
			;;
		--no-line-endings)
			do_line_endings=0
			;;
		--no-chmod)
			do_chmod=0
			;;
		*)
			echo "ERROR: Unknown option '$1' (use -h for help)"
			exit 4
			;;
	esac
	shift
done

function applyFormat()
{
	local filePattern="$1"
	local inputArray="$2[@]"
	local filterName="$3"
	local count=0

	echo -n "Clang-formatting $filterName files: "

	for filePath in "${!inputArray}"
	do
		local fileName="${filePath##*/}"
		if [[ $fileName =~ $filePattern ]]; then
			clang-format -i -style=file "$filePath" &> /dev/null
			count=$(($count + 1))
		fi
	done

	echo "$count file(s) processed"
}

function applyFileAttributes()
{
	local filePattern="$1"
	local attribs="$2"
	local inputArray="$3[@]"
	local filterName="$4"
	local count=0

	echo -n "Setting file attributes for $filterName files: "

	for filePath in "${!inputArray}"
	do
		local fileName="${filePath##*/}"
		if [[ $fileName =~ $filePattern ]]; then
			chmod -f "$attribs" "$filePath" &> /dev/null
			count=$(($count + 1))
		fi
	done

	echo "$count file(s) processed"
}

function applyLineEndings()
{
	local filePattern="$1"
	local inputArray="$2[@]"
	local filterName="$3"
	local count=0

	echo -n "Converting to unix endings $filterName files: "

	for filePath in "${!inputArray}"
	do
		local fileName="${filePath##*/}"
		if [[ $fileName =~ $filePattern ]]; then
			dos2unix "$filePath" &> /dev/null
			count=$(($count + 1))
		fi
	done

	echo "$count file(s) processed"
}

function listFiles()
{
	local outputArray=$1
	readarray -d '' $outputArray < <(find . -not -path "./.git/*" -not -path "./3rdparty/*" -not -path "./externals/*" -not -path "./_*" -type f -print0)
}

# List all files
declare -a listOfAllFiles=()
listFiles listOfAllFiles

# Clang-format files
if [[ $do_clang_format -eq 1 && -f ./.clang-format ]]; then
	which clang-format &> /dev/null
	if [ $? -eq 0 ]; then
		cf_version="$(clang-format --version)"
		regex="clang-format version 7\.0\.0 \(tags\/RELEASE_700\/final[ 0-9]*\/WithWrappingBeforeLambdaBodyPatch\)"
		if [[ ! "$cf_version" =~ $regex ]]; then
			echo "Incorrect clang-format: Version 7.0.0 with WrappingBeforeLambdaBody patch required (found: $cf_version)"
			exit 1
		fi
		applyFormat ".+\.[chi]pp(\.in)?$" listOfAllFiles "C++"
		applyFormat ".+\.[ch](\.in)?$" listOfAllFiles "C"
		applyFormat ".+\.mm(\.in)?$" listOfAllFiles "Objective-C"
		applyFormat ".+\.frag(\.in)?$" listOfAllFiles "Fragment Shader"
		applyFormat ".+\.vert(\.in)?$" listOfAllFiles "Vertex Shader"
	else
		echo "clang-format required"
		exit 1
	fi
fi

# Change line endings
if [ $do_line_endings -eq 1 ]; then
	which dos2unix &> /dev/null
	if [ $? -eq 0 ]; then
		applyLineEndings ".+\.[chi]pp(\.in)?$" listOfAllFiles "C++"
		applyLineEndings ".+\.[ch](\.in)?$" listOfAllFiles "C"
		applyLineEndings ".+\.mm(\.in)?$" listOfAllFiles "Objective-C"
		applyLineEndings ".+\.js(\.in)?$" listOfAllFiles "JavaScript"
		applyLineEndings ".+\.txt(\.in)?$" listOfAllFiles "Text"
		applyLineEndings ".+\.cmake(\.in)?$" listOfAllFiles "CMake"
		applyLineEndings ".+\.md(\.in)?$" listOfAllFiles "Markdown"
		applyLineEndings ".+\.sh(\.in)?$" listOfAllFiles "Shell Script"
		applyLineEndings ".+\.qs(\.in)?$" listOfAllFiles "Qt Installer Script"
		applyLineEndings ".+\.frag(\.in)?$" listOfAllFiles "Fragment Shader"
		applyLineEndings ".+\.vert(\.in)?$" listOfAllFiles "Vertex Shader"
		applyLineEndings ".+\.php(\.in)?$" listOfAllFiles "php"
		applyLineEndings ".+\.xml(\.in)?$" listOfAllFiles "XML"
		applyLineEndings ".+\.i(\.in)?$" listOfAllFiles "SWIG Interface"
	else
		echo "dos2unix command not found, not changing file line endings"
	fi
fi

# Fix file attributes
if [ $do_chmod -eq 1 ]; then
	which chmod &> /dev/null
	if [ $? -eq 0 ]; then
		# Text/source files (non-executable)
		chmod -f a-x .clang-format .editorconfig .gitattributes .gitignore .gitmodules COPYING COPYING.LESSER LICENSE &> /dev/null
		applyFileAttributes ".+\.[chi]pp(\.in)?$" "a-x" listOfAllFiles "C++"
		applyFileAttributes ".+\.[ch](\.in)?$" "a-x" listOfAllFiles "C"
		applyFileAttributes ".+\.mm(\.in)?$" "a-x" listOfAllFiles "Objective-C"
		applyFileAttributes ".+\.js(\.in)?$" "a-x" listOfAllFiles "JavaScript"
		applyFileAttributes ".+\.txt(\.in)?$" "a-x" listOfAllFiles "Text"
		applyFileAttributes ".+\.cmake(\.in)?$" "a-x" listOfAllFiles "CMake"
		applyFileAttributes ".+\.md(\.in)?$" "a-x" listOfAllFiles "Markdown"
		applyFileAttributes ".+\.patch$" "a-x" listOfAllFiles "Patch"
		applyFileAttributes ".+\.qrc(\.in)?$" "a-x" listOfAllFiles "Qt Resource"
		applyFileAttributes ".+\.ui(\.in)?$" "a-x" listOfAllFiles "Qt UI"
		applyFileAttributes ".+\.qs(\.in)?$" "a-x" listOfAllFiles "Qt Installer Script"
		applyFileAttributes ".+\.frag(\.in)?$" "a-x" listOfAllFiles "Fragment Shader"
		applyFileAttributes ".+\.vert(\.in)?$" "a-x" listOfAllFiles "Vertex Shader"
		applyFileAttributes ".+\.php(\.in)?$" "a-x" listOfAllFiles "php"
		applyFileAttributes ".+\.xml(\.in)?$" "a-x" listOfAllFiles "XML"
		applyFileAttributes ".+\.i(\.in)?$" "a-x" listOfAllFiles "SWIG Interface"

		# Other files (non-executable)
		applyFileAttributes ".+\.svg$" "a-x" listOfAllFiles "SVG Image"
		applyFileAttributes ".+\.png$" "a-x" listOfAllFiles "PNG Image"

		# Other files (executable)
		applyFileAttributes ".+\.sh$" "a+x" listOfAllFiles "Shell Script"
		applyFileAttributes ".+\.bat$" "a+x" listOfAllFiles "Batch Script"
		applyFileAttributes "^(pre|post)install(\.in)?$" "a+x" listOfAllFiles "PKG Script"
		
		# Binary files (executable)
		applyFileAttributes ".+\.exe$" "a+x" listOfAllFiles "EXEcutable"
		applyFileAttributes ".+\.dll$" "a+x" listOfAllFiles "DLL"
	else
		echo "chmod command not found, not changing file attributes"
	fi
fi
