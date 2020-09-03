# Ktools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Ktools is a set of containerized kubernetes-related tools and convenience
functions. It is an easier way to manage your tools across dev, ci builds,
deploys, and ops as well as across teams and platforms. You can also switch
versions of tools on the fly.

## Prereqs

All you need is `bash`, some version of `docker` (the client and the daemon),
`grep` and `sed`.

## Tools it provides

* kops - for managing the k8s cluster itself
* kubectl - for managing workloads on the cluster
* helm - for installing a set of k8s resources
* stim - for interacting with vault to get kube config or login to aws or get
  secrets from vault before deploying
* vault - for secret management
* terraform - for managing cloud infrastructure as code


## Usage

Either download the ktools.sh script and make it executable or clone the ktools
repo.

Then you can execute commands via ktools

```bash
cd path/to/ktools/
./ktools.sh kubectl config current-context
./ktools.sh helm ls
```

Or you can source ktools which allows you to run commands like you would with
normally installed tools. Sourcing ktools effectively installs the tools by
adding functions to your shell which run the tools in a docker container.
Technically it lazy installs a tool the first time you run it.

```bash
cd path/to/ktools/
. ./ktools.sh
kubectl config current-context
helm ls
```

The best way to use ktools is to source it in your `.bashrc` or `.bash_profile`
and have it indicate the current k8s cluster you are pointed at.

```bash
echo ". ~/path/to/ktools/ktools.sh --ktools-modify-prompt" > ~/.bashrc
```

### kvm

If you have sourced ktools, it can act as a version manager for the tools it
provides. If you aren't able to switch to a version, check that the version is
valid and also check that the docker image for the version has been published.
See the links at the top of ktools to the DockerHub pages for each tool

```bash
kversion kubectl # print the current version of the kubectl client
kvm kubectl 1.16.14 # switch to kubectl 1.16.14

kversion ks8 # print the version of k8s on the current cluster you are pointed at
```

kvm let's you specify a version of 'auto' for kubectl and vault (and helm if
using the older helm 2). It will hit the currently configured server/cluster to
determine the corresponding version of the client that is needed.

```bash
kvm kubectl auto # use the same kubectl version as the cluster's k8s version
kvm vault auto # use the vault cli version that matches the vault server
```


## Gotchas
There are a few limitations when running cli tools in a docker container.

The main limitation is that the current working directory is mounted into the
container which means you can't reference stuff outside the
current working dir. The relevant dot files and dirs to the tool are also bind
mounted. For example if you are using ktools and try 
`kubectl apply -f ../mytemplate.yaml`, it is not going to work because 
mytemplate.yaml is not in the directory that was mounted in the container.
Ktools could technically be updated to handle this case but it currently does
not handle it correctly.

You also can't bind mount when already inside a docker container. So if you are
running a script inside a docker container that uses ktools, you can't use the
containerized version of the tools.

Docker For Desktop on Mac (and maybe Windows) uses a VM that is detached from
the host machine network so features like kubectl port-forward or proxy that
rely on a port being exposed require native kubectl

## Initial Authors/Contributors

* Devin Wilson ([dwilson6](https://github.com/dwilson6))
* John Langewisch ([jahndis](https://github.com/jahndis))
* Craig Lewis ([clewis](https://github.com/clewis))
* Nico Pampe ([NicoPampe](https://github.com/NicoPampe))
* Justin Martinez ([jmartine](https://github.com/jmartine))
* Kenji Chapa ([kchapa](https://github.com/kchapa))