ZIP_NAME := "pressure-mapper"
CS_PLATFORM := if os() == "windows" { "win" } else { os() }

# Probably need to fix this for arm at some point

CS_ARCH := if arch() == "x86_64" { "x64" } else { arch() }
CS_RID := CS_PLATFORM + "-" + CS_ARCH

[working-directory("plugin")]
build-plugin:
    dotnet publish -r {{ CS_RID }}

[working-directory("plugin")]
zip-plugin:
    7z a {{ ZIP_NAME }}.zip metadata.json ./bin/Release/net8.0/{{ CS_RID }}/publish/*.dll

get-plugin: build-plugin zip-plugin
    cp plugin/{{ ZIP_NAME }}.zip {{ ZIP_NAME }}.zip

[working-directory("plugin")]
clean:
    rm -rf bin obj {{ ZIP_NAME }}.zip
