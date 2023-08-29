# Set the registry URL and credentials
$REGISTRY_URL="https://myregistry.com"
$REGISTRY_USERNAME="myusername"
$REGISTRY_PASSWORD="mypassword"
$FILE_PATH="PathToFile.tar.gz"


# Set the working directory
$DIRECTORY = Split-Path -Path $FILE_PATH -LeafBase

# Make Directory
New-Item -ItemType Directory -Path $DIRECTORY -Force | Out-Null

# Untar the file into the destination folder
Write-Output "Untarring file at $(Get-Date)"
tar -xv -f $FILE_PATH -C $DIRECTORY > $null
Write-Output "Untarring file complete at $(Get-Date)"

# Get the image name and tag from the manifest
$REPOSITORY_NAME = (Get-Content "$DIRECTORY/manifest.json" | ConvertFrom-Json)[0].RepoTags[0] -replace '^.*/'
$TAG = $REPOSITORY_NAME.Split(':')[-1]
$REPOSITORY_NAME = $REPOSITORY_NAME.Split(':')[0]

# Get Config File Name
$CONFIG_FILE = (Get-Content "$DIRECTORY/manifest.json" | ConvertFrom-Json)[0].Config

# Create manifest JSON object
$CONFIG_DIGEST = 'sha256:{0}' -f ((Get-FileHash "$DIRECTORY/$CONFIG_FILE" -Algorithm SHA256).Hash)
$CONFIG_SIZE = (Get-Item "$DIRECTORY/$CONFIG_FILE").Length

$ARCHITECTURE = (Get-Content "$DIRECTORY/$CONFIG_FILE" | ConvertFrom-Json).architecture
$OS = (Get-Content "$DIRECTORY/$CONFIG_FILE" | ConvertFrom-Json).os

Write-Output "Repository Name: $REPOSITORY_NAME"
Write-Output "Tag: $TAG"
Write-Output "ARCHITECTURE: $ARCHITECTURE"
Write-Output "OS: $OS"

# Create manifest JSON object
$JSON_OBJECT = @{
    schemaVersion = 2
    mediaType = "application/vnd.docker.distribution.manifest.v2+json"
    config = @{
        mediaType = "application/vnd.docker.container.image.v1+json"
        size = [int]$CONFIG_SIZE
        digest = $CONFIG_DIGEST
        platform = @{
            architecture = $ARCHITECTURE
            os = $OS
        }
    }
    layers = @()
} | ConvertTo-Json

Write-Output "Loading Docker images at $(Get-Date)"
foreach ($layer in (Get-Content "$DIRECTORY/manifest.json" | ConvertFrom-Json)[0].Layers) {
    # Get the layer file name
    $LAYER = $layer -replace '/layer.tar$'

    #Get Digest
    $LAYER_DIGEST = 'sha256:{0}' -f ((Get-FileHash "$DIRECTORY/$layer" -Algorithm SHA256).Hash)

    #Check if layer exists
    Write-Output "Checking layer $LAYER_DIGEST"
    $RESPONSE = Invoke-RestMethod -Method Head -Uri "$REGISTRY_URL/v2/$REPOSITORY_NAME/blobs/$LAYER_DIGEST" -Credential (New-Object System.Management.Automation.PSCredential ($REGISTRY_USERNAME, (ConvertTo-SecureString $REGISTRY_PASSWORD -AsPlainText -Force)))

    if ($RESPONSE.StatusCode -eq 200) {
        Write-Output "Layer exists in the registry, skipping"
    }
    else {
        Write-Output "Layer does not exist in the registry, uploading"

        #Getting upload url
        $LOCATION_HEADER = Invoke-RestMethod -Method Post -Uri "$REGISTRY_URL/v2/$REPOSITORY_NAME/blobs/uploads/" -Credential (New-Object System.Management.Automation.PSCredential ($REGISTRY_USERNAME, (ConvertTo-SecureString $REGISTRY_PASSWORD -AsPlainText -Force))) -Headers @{ "Content-Type" = "application/json" } -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop
        $UPLOAD_URL = $REGISTRY_URL + ($LOCATION_HEADER.Headers.Location -replace '\r\n')

        #upload layer
        Invoke-RestMethod -Method Put -Uri "$UPLOAD_URL&digest=$LAYER_DIGEST" -Credential (New-Object System.Management.Automation.PSCredential ($REGISTRY_USERNAME, (ConvertTo-SecureString $REGISTRY_PASSWORD -AsPlainText -Force))) -Headers @{ "Content-Type" = "application/tar" } -Body (Get-Content "$DIRECTORY/$layer" -Raw) -UseBasicParsing -ErrorAction Stop
    }

    # Append the layer object to the layers array
    $LAYER_SIZE = (Get-Item "$DIRECTORY/$layer").Length
    $LAYER_OBJECT = @{
        mediaType = "application/vnd.docker.image.rootfs.diff.tar.gzip"
        size = [int]$LAYER_SIZE
        digest = $LAYER_DIGEST
    }
    $JSON_OBJECT = $JSON_OBJECT | ConvertFrom-Json
    $JSON_OBJECT.layers += $LAYER_OBJECT
    $JSON_OBJECT = $JSON_OBJECT | ConvertTo-Json
}

# Upload Config
Write-Output "Uploading Config"
$LOCATION_HEADER = Invoke-RestMethod -Method Post -Uri "$REGISTRY_URL/v2/$REPOSITORY_NAME/blobs/uploads/" -Credential (New-Object System.Management.Automation.PSCredential ($REGISTRY_USERNAME, (ConvertTo-SecureString $REGISTRY_PASSWORD -AsPlainText -Force))) -Headers @{ "Content-Type" = "application/json" } -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop
$UPLOAD_URL = $REGISTRY_URL + ($LOCATION_HEADER.Headers.Location -replace '\r\n')
Invoke-RestMethod -Method Put -Uri "$UPLOAD_URL&digest=$CONFIG_DIGEST" -Credential (New-Object System.Management.Automation.PSCredential ($REGISTRY_USERNAME, (ConvertTo-SecureString $REGISTRY_PASSWORD -AsPlainText -Force))) -Headers @{ "Content-Type" = "application/json" } -Body (Get-Content "$DIRECTORY/$CONFIG_FILE" -Raw) -UseBasicParsing -ErrorAction Stop

#Write manifest to disk
Write-Output "$JSON_OBJECT" | Out-File -FilePath "$DIRECTORY/manifest.json"

#Upload Manifests
Write-Output "Uploading Manifest"
Invoke-RestMethod -Method Put -Uri "$REGISTRY_URL/v2/$REPOSITORY_NAME/manifests/$TAG" -Credential (New-Object System.Management.Automation.PSCredential ($REGISTRY_USERNAME, (ConvertTo-SecureString $REGISTRY_PASSWORD -AsPlainText -Force))) -Headers @{ "Content-Type" = "application/vnd.docker.distribution.manifest.v2+json" } -Body (Get-Content "$DIRECTORY/manifest.json" -Raw) -UseBasicParsing -ErrorAction Stop

Write-Output "Remove Directory"
Remove-Item -Path $DIRECTORY -Recurse -Force

Write-Output "Loading Docker images complete at $(Get-Date)"