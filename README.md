# Bash Utils
Copyright (C) 2020-2025, Christophe Calmejane

# What is it?

Bash Utils is a collection of bash scripts designed to improve developers productivity.

## Directly callable scripts

Scripts designed to be called directly from the command line.

## fix_files.sh

Script to batch process files, correcting them (chmod, end of line, clang-format).

## list_includes.sh

Script to list includes files to generate a PCH file.

## update_copyright.sh

Script to update the copyright year of files.

# Indirectly callbable scripts

Scripts designed to be called from another script.

## notarize_binary.sh

Script to automate Apple Notarization process.

You can store your password in the keychain for easier process.
You will first have to generate an app-specific password:
- Sign in to your [Apple ID account page](https://appleid.apple.com/account/home).
- In the Security section, click Generate Password below App-Specific Passwords.
- Follow the steps on your screen.
- Store the generate app-specific password in the keychain using this command
  - xcrun altool --store-password-in-keychain-item "AC_PASSWORD" -u _"YourAppleID"_ -p _"GeneratedPassword"_

`Usage: notarize_binary.sh <Binary Path> <User Name> <Password> <Notarization Bundle Identifier>`
- `<Binary Path>` is the path to the binary you want to notarize. It should either be a zip, an application bundle, or a dmg
- `<User Name>` is _YourAppleID_
- `<Password>` is "@keychain:AC_PASSWORD"
- `<Notarization Bundle Identifier>` is any bundle identifier you want (might be different than the actual application)

## gen_cmake.sh

Script to generate a CMake solution.

## gen_install.sh

Script to generate a product installer.

## load_config_file.sh

Script to load and parse a config file.

## utils.sh

Set of useful bash functions.
