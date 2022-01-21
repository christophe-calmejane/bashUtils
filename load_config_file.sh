#!/usr/bin/env bash

loadConfigFile()
{
	if [ -z $configFileLoaded ]; then
		configFileLoaded=1

		parseFile "${configFile}" knownOptions[@] params
	fi
}

if [ -z $configFileIncluded ]; then
	configFileIncluded=1

	# Config file name
	if [ -z ${configFile} ]; then
		configFile=".config"
	fi

	declare -A params=()
	declare -a knownOptions=("identity" "signtool_options" "notarization_username" "notarization_password" "use_sparkle" "appcast_releases" "appcast_betas" "appcast_releases_fallback" "appcast_betas_fallback" "symbols_symstore_path" "symbols_windows_pdb_server_path" "symbols_macos_dsym_server_path")

	# Default values
	params["identity"]=""
	params["notarization_username"]=""
	params["notarization_password"]="@keychain:AC_PASSWORD"
	params["use_sparkle"]=false
	params["appcast_releases"]="https://localhost/appcast-release.xml"
	params["appcast_betas"]="https://localhost/appcast-beta.xml"
	params["appcast_releases_fallback"]="https://localhost/appcast-release.xml"
	params["appcast_betas_fallback"]="https://localhost/appcast-beta.xml"
	params["signtool_options"]="/a /sm /q /fd sha256 /tr http://timestamp.sectigo.com /td sha256"

	if [[ $(type -t extend_lcf_fnc_init) == function ]]; then
		extend_lcf_fnc_init knownOptions params
	fi
fi
