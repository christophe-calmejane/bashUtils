#!/usr/bin/env bash
# Useful script to notarize a binary

notarizeFile()
{
	local fileName="$1"
	local profileName="$2"

	echo -n "Sending binary for notarization... "
	local uploadResult # We must declare the variable before assigning in order to get the return code in $?
	uploadResult=$(xcrun notarytool submit "${fileName}" -p "${profileName}" --wait)
	if [ $? -eq 0 ]; then
		local regexPattern="Processing complete[[:space:]]+id:[[:space:]]+([0-9a-z\-]+)[[:space:]]+status:[[:space:]]+([a-zA-Z]+)"
		if [[ $uploadResult =~ $regexPattern ]]; then
			local uuid="${BASH_REMATCH[1]}"
			local status="${BASH_REMATCH[2]}"
			if [[ "$status" == "Accepted" ]]; then
				echo "done"
				local fileToStaple="${fileName}"
				# Check if the file is a ZIP archive, if so we need to unzip it first in a temporary directory
				if [[ "${fileName}" == *.zip ]]; then
					local tempDir=$(mktemp -d)
					echo -n "Unzipping binary to temporary directory... "
					unzip -q "${fileName}" -d "${tempDir}"
					# Find the first '.app' in the unzipped directory
					fileToStaple=$(find "${tempDir}" -type d -name "*.app" | head -n 1)
					if [ -z "${fileToStaple}" ]; then
						echo "failed: No .app found in the ZIP archive"
						exit 1
					fi
					echo "done"
				fi
				echo -n "Stapling binary... "
				local stapleResult # We must declare the variable before assigning in order to get the return code in $?
				stapleResult=$(xcrun stapler staple "${fileToStaple}")
				if [ $? -eq 0 ]; then
					echo "done"
					return
				else
					echo "failed: $stapleResult"
					exit 1
				fi
			else
				echo "failed"
				echo "Check log using: xcrun notarytool log $uuid -p ${profileName}"
				return
			fi
		fi
	fi
	echo "failed: $uploadResult"
	exit 1
}

printHelp()
{
	echo "Usage: notarize_binary.sh <Binary Path> <Keychain Profile>"
	echo ""
	echo "In order to create a Keychain profile (just once), run:"
	echo "	xcrun notarytool store-credentials YourProfileName --apple-id YourAccountEmailAdrs --password YourAppSpecificPwd --team-id YourTeamID"
	echo ""
	echo "You will first need to generate an application specific password if you don't have one already (you cannot use your Apple ID account password for security reasons):"
	echo "	- Sign in to your [Apple ID account page](https://appleid.apple.com/account/home) (https://appleid.apple.com/account/home)"
	echo "	- In the Security section, click Generate Password below App-Specific Passwords"
	echo "	- Follow the steps on your screen"
}

if [ $# -ne 2 ]; then
	echo "ERROR: Missing parameters"
	printHelp
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "ERROR: Binary does not exist: $1"
	printHelp
	exit 1
fi

notarizeFile "$1" "$2"

exit 0
