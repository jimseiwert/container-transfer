# Container Transfer
 Script to Effortlessly Move a Docker Saved tar.gz Archive to an Alternative Container Registry via the Docker API v2 REST Endpoint, Bypassing the Need for the Docker Daemon

This is a common script needed for transferring images to air gap environments or other environments with docker / docker desktop can't be installed or you wish to run a smaller utility that only focuses on import / export.

The design was an alternative to [docker save](https://docs.docker.com/engine/reference/commandline/save/) and [docker load](https://docs.docker.com/engine/reference/commandline/load/)
## How To use

### Assumptions / Still needed
- This assumes you already ran a docker save on the source image and have the tar.gz file on the destination network. 
- Docker export script coming soon
- Tested against Azure Container Registry, not tested against others yet
- Powershell script untested, just a port of the bash file

### Importing / Saving Source Images
    - Run the script from this repo under {{shell choice}}/import.(sh,ps1)
    - Provide Parameter inputs

The import scripts by performing the fulling actions
- untar the provided *tar.gz
- inspect the manifest and config files for the following items
    - image name
    - image tag
    - operating system designed for
    - architecture of image
    - required layers
- The layers are uploaded one at a time verifying the sha256 matches the uploaded file
- The config and manifest is then uploaded with the new values


Feel free to contribute by doing a pull request for additional functionality or bug fixes as needed. Some future items will include chunking of the layer files to assist with larger layers / lower throughput scenarios