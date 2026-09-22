# Xcode metadata

The repository pins its Xcode version in `.xcode-version`. Use that version when opening or saving the project so `project.pbxproj` is not rewritten by another serializer.

App target settings live in `Splitty/Config/App.xcconfig`. Keep machine-specific signing choices out of the project file. The tracked `Info.plist` is the complete source for app metadata; edit it as XML instead of through the target's Info editor.

`Localizable.xcstrings` contains manually managed localization keys. Automatic Swift string extraction is disabled because the app routes copy through `L10n`. After editing the catalog in Xcode, restore its deterministic ordering and formatting:

```sh
scripts/format-xcstrings.swift
```

Check the catalog without changing it:

```sh
scripts/format-xcstrings.swift --check
```
