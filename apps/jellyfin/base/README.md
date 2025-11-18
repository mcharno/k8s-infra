
# Jellyfin

 

## Description

Jellyfin media server deployment.

 

## Persistent Storage

- Config: `/config`

- Media: `/media` (consider NFS or hostPath for large media libraries)

- Cache: `/cache`

 

## Notes

- May require hardware acceleration configuration for transcoding

- Consider nodeSelector for GPU nodes if using hardware transcoding

 

## Deploy

```bash

kubectl apply -k apps/jellyfin/base/

```

