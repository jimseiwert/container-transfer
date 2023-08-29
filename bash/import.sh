#!/bin/bash

# Set required parameters
REGISTRY_URL="https://myregistry.com"
REGISTRY_USERNAME="myusername"
REGISTRY_PASSWORD="mypassword"
FILE_PATH="PathToFile.tar.gz"

# Set the path to the tar.gz file
DIRECTORY=$(basename "$FILE_PATH" .tar.gz)

# Make Directory
mkdir -p "$DIRECTORY"

# Untar the file into the destination folder
echo "Untarring file at $(date)"
tar xv -f "$FILE_PATH" -C "./$DIRECTORY" > /dev/null
echo "Untarring file complete at $(date)"

# Get the image name and tag from the manifest
REPOSITORY_NAME=$(jq -r '.[0].RepoTags[0] | if index("/") then sub("^.*?/"; "") else . end'  "./$DIRECTORY/manifest.json")
TAG=$(echo "$REPOSITORY_NAME" | awk -F: '{print $NF}')
REPOSITORY_NAME=$(echo "$REPOSITORY_NAME" | cut -d: -f1)

# Get Config File Name
CONFIG_FILE=$(jq -r '.[0].Config'  "./$DIRECTORY/manifest.json")

# Create manifest JSON object
CONFIG_DIGEST=sha256:$(sha256sum "./$DIRECTORY/$CONFIG_FILE" | cut -d ' ' -f1)
CONFIG_SIZE=$(wc -c "./$DIRECTORY/$CONFIG_FILE" | awk '{print $1}')

ARCHITECTURE=$(jq -r '.architecture'  "./$DIRECTORY/$CONFIG_FILE")
OS=$(jq -r '.os'  "./$DIRECTORY/$CONFIG_FILE")

echo "Repository Name: $REPOSITORY_NAME"
echo "Tag: $TAG"
echo "ARCHITECTURE: $ARCHITECTURE"
echo "OS: $OS"


# Create manifest JSON object
JSON_OBJECT=$(jq -n --arg config_size "$CONFIG_SIZE" --arg config_digest "$CONFIG_DIGEST" --arg architecture "$ARCHITECTURE" --arg os "$OS" '{schemaVersion: 2, mediaType: "application/vnd.docker.distribution.manifest.v2+json", config: {mediaType: "application/vnd.docker.container.image.v1+json", size:  ($config_size | tonumber), digest: $config_digest,   "platform": {"architecture": $architecture,"os": $os}}, layers: []}')

echo "Loading Docker images at $(date)"
for layer in $(jq -r '.[0].Layers[]' "./$DIRECTORY/manifest.json"); do
    # Get the layer file name
    LAYER="${layer%/layer.tar}"

    #Get Digest
    LAYER_DIGEST=sha256:$(sha256sum "./$DIRECTORY/$layer" | cut -d ' ' -f1)

    #Check if layer exists
    echo "Checking layer $LAYER_DIGEST"
    RESPONSE=$(curl -s -I -X HEAD -u "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" "$REGISTRY_URL/v2/$REPOSITORY_NAME/blobs/$LAYER_DIGEST")

    if [[ "$RESPONSE" == *"200 OK"* ]]; then
        echo "Layer exists in the registry, skipping"
    else
        echo "Layer does not exist in the registry, uploading"

        #Getting upload url
        LOCATION_HEADER=$(curl -s -I -X POST -u "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" "$REGISTRY_URL/v2/$REPOSITORY_NAME/blobs/uploads/" | grep -i "location:" | tr -d '\r\n')
        UPLOAD_URL=$REGISTRY_URL$(echo "$LOCATION_HEADER" | awk '{print $2}' | tr -d '\r\n')
        #upload layer
        curl -X PUT -u "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" -H "Content-Type: application/tar" --data-binary "@$DIRECTORY/$layer" "$UPLOAD_URL&digest=$LAYER_DIGEST"
    fi

    # Append the layer object to the layers array
    LAYER_SIZE=$(wc -c "./$DIRECTORY/$layer"  | awk '{print $1}')
    LAYER_OBJECT=$(jq -n --arg layer_size "$LAYER_SIZE" --arg layer_digest "$LAYER_DIGEST" '{mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: ($layer_size | tonumber), digest: $layer_digest}')
    JSON_OBJECT=$(echo "$JSON_OBJECT" | jq --argjson layer_object "$LAYER_OBJECT" '.layers += [$layer_object]')
done

# Upload Config
echo "Uploading Config"
LOCATION_HEADER=$(curl -s -I -X POST -u "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" "$REGISTRY_URL/v2/$REPOSITORY_NAME/blobs/uploads/" | grep -i "location:" | tr -d '\r\n')
UPLOAD_URL=$REGISTRY_URL$(echo "$LOCATION_HEADER" | awk '{print $2}' | tr -d '\r\n')
curl -s -X PUT -u "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" -H "Content-Type: application/json" --data-binary @./$DIRECTORY/$CONFIG_FILE "$UPLOAD_URL&digest=$CONFIG_DIGEST"

#Write manifest to disk
echo "$JSON_OBJECT" > "./$DIRECTORY/manifest.json"

#Upload Manifests
echo "Uploading Manifest"
curl -X PUT -u "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" -H "Content-Type: application/vnd.docker.distribution.manifest.v2+json" --data-binary @./$DIRECTORY/manifest.json "$REGISTRY_URL/v2/$REPOSITORY_NAME/manifests/$TAG"

echo "Remove Directory"
rm -rf "./$DIRECTORY"

echo "Loading Docker images complete at $(date)"
