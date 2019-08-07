# shipyard

### Purpose

Shipyard brings infrastructure as code to Spinnaker. It can create and manage projects, apps, and pipelines.

```
# Rendered pipelines are written here

build/

# default pipeline templates

base/

# projects and their base config, and app config
# if nothing if overwritten in an app or project dir, the defaults are used
# app overrides project, project overrides base

projects/*

# each project config is defined by a yard file

projects/*/yard.yaml
```

### Examples

Check out the delivery `yard.yaml`, `aps` is yaml-only and it uses the base templates. `weightwatchers` overrides the bake pipeline with one of it's own. `broker` overrides the bake pipeline and the prod pipelines.


### Running

Render the pipelines, files are written to `build/*`.
`ruby shipwright.rb`

Create projects, apps, upload the pipelines. You have to be connected to the VPN.

```
GATE_HOST=https://gate-spinnaker.devint.gcp.openx.org
GCLOUD_TOKEN=$(gcloud auth print-access-token)

GCLOUD_TOKEN=$GCLOUD_TOKEN GATE_HOST=$GATE_HOST ruby upload.rb
```

### TODO:

+ command line args for dry run
+ move lib to own gem
+ generate and use models
+ rewrite parser in a functional way
+ ability to sync with spinnaker instance, get diff, and resolve
