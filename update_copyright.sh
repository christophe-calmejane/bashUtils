#!/usr/bin/env bash

# Check if a .git file or folder exists (we allow submodules, thus check file and folder), as well as a root cmake file
if [[ ! -e ".git" || ! -f "CMakeLists.txt" ]]; then
	echo "ERROR: Must be run from the root folder of your project (where your main CMakeLists.txt file is)"
	exit 1
fi

# Get absolute folder for this script
selfFolderPath="`cd "${BASH_SOURCE[0]%/*}"; pwd -P`/" # Command to get the absolute path

# Include utils functions
. "${selfFolderPath}utils.sh"

# Sanity checks
envSanityChecks "sed"

function updateCopyrightYear()
{
	local filePattern="$1"
	local newYear="$2"
	
	echo "Updating Copyright for all $filePattern files"
	find . -iname "$filePattern" -not -path "./3rdparty/*" -not -path "./externals/*" -not -path "./_*" -exec sed -i {} -r -e "s/Copyright \([cC]\) ([0-9]+)-([0-9]+)([,\ ])/Copyright \(C\) \1-$newYear\3/" \;
}

year="$(date "+%Y")"
updateCopyrightYear "*.[chi]pp" "$year"
updateCopyrightYear "*.[ch]" "$year"
updateCopyrightYear "*.mm" "$year"
updateCopyrightYear "*.in" "$year"
updateCopyrightYear "*.md" "$year"
updateCopyrightYear "*.txt" "$year"
updateCopyrightYear "*.sh" "$year"
updateCopyrightYear "LICENSE" "$year"
