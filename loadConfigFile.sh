#!/usr/bin/env bash

# Parse config file
configFile=".config"
declare -A params=()
declare -a knownOptions=("identity" "signtool_options" "notarization_username" "notarization_password" "use_appcast" "appcast_releases" "appcast_betas" "appcast_releases_fallback" "appcast_betas_fallback" "symbols_symstore_path" "symbols_windows_pdb_server_path" "symbols_macos_dsym_server_path")

# Default values
params["identity"]=""
params["notarization_username"]=""
params["notarization_password"]="@keychain:AC_PASSWORD"
params["use_appcast"]=false
params["appcast_releases"]="https://localhost/appcast-release.xml"
params["appcast_betas"]="https://localhost/appcast-beta.xml"
params["appcast_releases_fallback"]="https://localhost/appcast-release.xml"
params["appcast_betas_fallback"]="https://localhost/appcast-beta.xml"
params["signtool_options"]="/a /sm /q /fd sha256 /tr http://timestamp.sectigo.com /td sha256"

loadConfigFile()
{
	parseFile "${configFile}" knownOptions[@] params

	# Quick check for identity in keychain
	if isMac ; then
		local identityString="${params["identity"]}"
		if [ "x$identityString" == "x" ]; then
			echo "ERROR: macOS requires valid signing identity. Specify it in the ${configFile} file among one of the following valid IDs:"
			security find-identity -v -p codesigning | grep -Po "^[[:space:]]+[0-9]+\)[[:space:]]+[0-9A-Z]+[[:space:]]+\"\KDeveloper ID Application: [^(]+\([^)]+\)(?=\")"
			exit 1
		fi
		security find-identity -v -p codesigning | grep "Developer ID" | grep "$identityString" &> /dev/null
		if [ $? -ne 0 ]; then
			echo "ERROR: Invalid identity value in '${configFile}' file (not found in keychain, or not valid for codesigning, use 'gen_cmake.sh -ids' to get a list of valid identities): $identityString"
			exit 1
		fi
	fi
}
