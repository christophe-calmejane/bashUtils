#!/usr/bin/env bash
# Useful script to notarize a binary

notarizeFile()
{
	local fileName="$1"
	local userName="$2"
	local password="$3"
	local bundleId="$4"

	echo -n "Sending binary for notarization... "
	local uploadResult=$(xcrun altool --notarize-app --primary-bundle-id "${bundleId}" --username "${userName}" --password "${password}" --file "${fileName}")
	local regexPattern="RequestUUID = ([^\n]+)"
	if [[ $uploadResult =~ $regexPattern ]]; then
		echo "done"
		local uuid="${BASH_REMATCH[1]}"
		echo -n "Waiting for Apple validation..."
		while true; do
			sleep 10
			local infoResult=$(xcrun altool -u "${userName}" --password "${password}" --notarization-info "${uuid}")
			local progressRegex="Status: in progress"
			local approvedRegex="Status Message: Package Approved"
			if [[ $infoResult =~ $progressRegex ]]; then
				echo -n "."
				continue
			elif [[ $infoResult =~ $approvedRegex ]]; then
				echo " done"
				break
			else
				echo " failed: $infoResult"
				exit 1
			fi
        done
		echo -n "Stapling binary... "
		local stapleResult=$(xcrun stapler staple "${fileName}")
		if [ $? -eq 0 ]; then
			echo "done"
		else
			echo "failed: $stapleResult"
			exit 1
		fi
	else
		echo "failed: $uploadResult"
		exit 1
	fi
}

printHelp()
{
	echo "Usage: notarize_binary.sh <Binary Path> <User Name> <Password> <Notarization Bundle Identifier>"
}

if [ $# -ne 6 ]; then
	echo "ERROR: Missing parameters"
	printHelp
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "ERROR: Binary does not exist: $1"
	printHelp
	exit 1
fi

notarizeFile "$1" "$2" "$3" "$4"

exit 0
