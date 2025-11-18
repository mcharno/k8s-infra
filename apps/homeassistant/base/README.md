
# Home Assistant

 

## Description

Home Assistant home automation platform.

 

## Persistent Storage

- Config: `/config`

 

## Network Requirements

- May need hostNetwork: true for device discovery

- Consider nodeSelector if USB devices are attached to specific nodes

 

## Deploy

```bash

kubectl apply -k apps/homeassistant/base/

```

 

## Notes

- Export configuration.yaml and other config files separately

- Some integrations may require special network or device access

