ZIP_NAME := "pressure-mapper"

[working-directory("plugin")]
build-plugin:
    dotnet publish

[working-directory("plugin")]
zip-plugin:
    7z a {{ZIP_NAME}}.zip metadata.json ./bin/Release/net8.0/publish/*.dll

get-plugin: build-plugin zip-plugin
    cp plugin/{{ZIP_NAME}}.zip {{ZIP_NAME}}.zip
