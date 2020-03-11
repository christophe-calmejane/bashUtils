# Bash Utils
Copyright (C) 2020, Christophe Calmejane

## What is it?

Bash Utils is a collection of bash scripts designed to improve developers productivity.

### notarize_binary.sh

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
