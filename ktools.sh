#!/bin/bash

#
# Copyright (c) 2020 Premiere Global Services, Inc.
# Licensed under MIT License
#

export KTOOLS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export KTOOLS_VERSION=0.5.0

###
#
# Ktools simplifies installing and working with k8s related tools across
# multiple repos, machines, and ci/cd builds. Various tools like kubectl, helm,
# kops, vault, stim, and terraform are installed as bash functions which run the
# tools as docker containers. This makes it easy to switch between versions of
# tools and also use the same tools in dev, ops, and ci/cd. Ktools also provides
# a number of convenience functions to make working with k8s tools easier.
#
# You can execute a command using one of the tools via ktools or source ktools
# in your shell and run the command like you usually would. Or even better,
# source ktools in your .bashrc or .bash_profile to have the tools automatically
# in any shell you launch.
#
# You can also put ktools in a repo to use it in a script or ci build. You can
# configure ktools to not use the containerized tools if you are running in an
# environment that already has the tools installed. For example, if you are
# using the kubernetes plugin for jenkins and the build is already running in a
# container.
#
# Prereqs:
# docker - to run containerized versions of tools (needs client and daemon)
# grep and sed - used by some of the functions
#
# Gotchas/Limitations:
# 1. The current working directory is mounted into the tool container so you
#    generally can't reference files outside the working directory
# 2. Docker For Desktop on Mac (and maybe Windows) uses a VM that is detached
#    from the host machine network so features like kubectl port-forward or
#    proxy that rely on a port being exposed require native kubectl
#
# Note: ktools has been mostly tested/used with bash. It may work with other
# shells but hasn't been verified.
#
###

# You can set these variables before sourcing or executing ktools to
# pre-configure ktools

# https://github.com/kubernetes/kubectl
# https://hub.docker.com/r/lachlanevenson/k8s-kubectl
export KUBECTL_IMAGE=${KUBECTL_IMAGE:-"lachlanevenson/k8s-kubectl"}
export KUBECTL_VERSION=${KUBECTL_VERSION:-"1.13.2"}

# https://github.com/helm/helm
# https://hub.docker.com/r/dtzar/helm-kubectl
export HELM_IMAGE=${HELM_IMAGE:-"dtzar/helm-kubectl"}
export HELM_VERSION=${HELM_VERSION:-"2.16.1"}

# https://github.com/hashicorp/vault
# https://hub.docker.com/_/vault
export VAULT_IMAGE=${VAULT_IMAGE:-"vault"}
export VAULT_VERSION=${VAULT_VERSION:-"1.5.0"}
export VAULT_ADDR=${VAULT_ADDR:-""}

# https://github.com/PremiereGlobal/stim
# https://hub.docker.com/r/premiereglobal/stim
export STIM_IMAGE=${STIM_IMAGE:-"premiereglobal/stim"}
export STIM_VERSION=${STIM_VERSION:-"0.1.7"}

# https://github.com/kubernetes/kops
# https://hub.docker.com/r/aztek/kops/tags
export KOPS_IMAGE=${KOPS_IMAGE:-"aztek/kops"}
export KOPS_VERSION=${KOPS_VERSION:-"1.13.2"}
export KOPS_STATE_STORE=${KOPS_STATE_STORE:-""}

# https://github.com/hashicorp/terraform
# https://hub.docker.com/r/hashicorp/terraform
export TERRAFORM_IMAGE=${TERRAFORM_IMAGE:-"hashicorp/terraform"}
export TERRAFORM_VERSION=${TERRAFORM_VERSION:-"0.11.14"}


ktools_platform="unknown"
case "$(uname -s)" in
  Linux)
    ktools_platform="linux"
    ;;
  Darwin)
    ktools_platform="osx"
    ;;
  CYGWIN*|MINGW*|MSYS*)
    ktools_platform="windows"
    ;;
esac

ktools_useContainerizedCliTools=true

if [[ "$ktools_platform" == "unknown" ]]; then
  echo "Unknown platform $(uname -s). There may be unexpected behavior." >&2
fi

if [[ "$ktools_platform" == "windows" ]]; then
  PATH_FIX="/"
fi

ktools_isSourced="false"
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  ktools_isSourced="true"
fi

# TODO: add checks for prereqs like docker, grep, sed, or maybe have
# those checks be more local to the functions that use them

function check_awscreds() {
  if [[ -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
    echo "Your AWS credentials are not set in env variables!  Run:"
    echo "  stim vault login"
    echo "  \$(stim aws login -a <aws-account> -r <role> -s)"
    if [[ "$ktools_isSourced" == "true" ]]; then
      return 1
    else
      exit 1
    fi
  fi
}


###
#
#   CLI Tools
#
###

# https://github.com/kubernetes/kubectl
function kubectl() {
  if [[ "$ktools_useContainerizedCliTools" == "false" ]]; then
    command kubectl "$@"
    return $?
  fi

  local OPTIND
  local dockerArgs=()
  local envArgs=()
  local cmd
  local use_native_kubectl

  if [[ "$1" == "--docker-args" ]]; then
    dockerArgs=($(echo "$2"))
    shift 2
  fi

  if [[ "$*" =~ (port-forward|exec|attach|proxy|edit) ]]; then
    cmd="$(echo "$*" | grep -o -E 'port-forward|exec|attach|proxy|edit')"

    # only port-forward and proxy have issues on mac, the others just need the
    # interactive flags
    if [[ "$ktools_platform" == "osx" ]] && [[ "$(type kubectl)" =~ "function" ]] && [[ "$*" =~ (port-forward|proxy) ]]; then
      echo "Warning: The containerized 'kubectl "$cmd"' will not properly forward ports to an OSX host." >&2
      if [[ -n "${dockerArgs[@]}" ]]; then
        echo "Docker args were used. Attempting to use containerized kubectl..." >&2
      else
        command kubectl > /dev/null 2>&1
        if [[ $? == 0 ]]; then
          echo "Native kubectl command was detected" >&2
          echo "Switching to use native kubectl..." >&2
          use_native_kubectl="true"
        else
          echo "You may want to install the native kubectl command for OSX." >&2
        fi
      fi
    elif [[ "$ktools_platform" == "windows" ]] && [[ "$(type kubectl)" =~ "function" ]]; then
      echo "Warning: The containerized 'kubectl "$cmd"' has issues with tty connections on a Windows host." >&2
      if [[ -n "${dockerArgs[@]}" ]]; then
        echo "Docker args were used. Attempting to use containerized kubectl..." >&2
      else
        command kubectl > /dev/null 2>&1
        if [[ $? == 0 ]]; then
          echo "Native kubectl command was detected" >&2
          echo "Switching to use native kubectl..." >&2
          use_native_kubectl="true"
        else
          echo "You may want to install the native kubectl command for Windows." >&2
        fi
      fi
    fi

    if [[ -z "${dockerArgs[@]}" ]]; then
      dockerArgs=("-it")
    fi
  fi

  mkdir -p "$HOME/.kube"
  mkdir -p "$HOME/.minikube"

  # If the end user has $KUBECONFIG set in env var, remap paths to the 
  # container mountpoint and pass it along.
  if [[ -n $KUBECONFIG ]]; then
      envArgs=("-e KUBECONFIG=${KUBECONFIG/#$HOME//root}")
  fi

  if [[ "$use_native_kubectl" == "true" ]]; then
    command kubectl "$@"
  else
    # TODO: derive the version from the current cluster if not set unless
    # running kubectl version or config commands
    docker run --rm \
      "${dockerArgs[@]}" \
      ${envArgs[@]} \
      --mount type=bind,source="$HOME"/.kube,target=/root/.kube \
      --mount type=bind,source="$HOME"/.minikube,target=$HOME/.minikube \
      --mount type=bind,source="$(pwd)",target="$(pwd)" \
      --network="host" \
      -w "$PATH_FIX$(pwd)" \
      $KUBECTL_IMAGE:v$KUBECTL_VERSION "$@"
  fi
}

function lenny() {
  kubectl "$@"
}

# https://github.com/helm/helm
function helm() {
  if [[ "$ktools_useContainerizedCliTools" == "false" ]]; then
    command helm "$@"
    return $?
  fi

  local OPTIND
  local dockerArgs=()
  local envArgs=()

  if [[ "$1" == "--docker-args" ]]; then
    dockerArgs=($(echo "$2"))
    shift 2
  fi

  mkdir -p "$HOME/.kube"
  mkdir -p "$HOME/.helm"
  mkdir -p "$HOME/.minikube"

  # If the end user has $KUBECONFIG set in env var, remap paths to the 
  # container mountpoint and pass it along.
  if [[ -n $KUBECONFIG ]]; then
      envArgs=("-e KUBECONFIG=${KUBECONFIG/#$HOME//root}")
  fi

  docker run --rm \
    "${dockerArgs[@]}" \
    ${envArgs[@]} \
    --mount type=bind,source="$HOME"/.kube,target=/root/.kube \
    --mount type=bind,source="$HOME"/.helm,target=/root/.helm \
    --mount type=bind,source="$HOME"/.minikube,target=$HOME/.minikube \
    --mount type=bind,source="$(pwd)",target="$(pwd)" \
    --network="host" \
    -w "$PATH_FIX$(pwd)" \
    $HELM_IMAGE:$HELM_VERSION helm "$@"
}

# https://github.com/hashicorp/vault
function vault() {
  if [[ "$ktools_useContainerizedCliTools" == "false" ]]; then
    command vault "$@"
    return $?
  fi

  local OPTIND
  local dockerArgs=()
  local envArgs=()
  local interactiveArgs=""

  if [[ "$1" == "--docker-args" ]]; then
    dockerArgs=($(echo "$2"))
    shift 2
  fi

  mkdir -p "$HOME/.stim"
  touch "$HOME/.vault-token"

  docker run --rm \
    "${dockerArgs[@]}" \
    ${envArgs[@]} \
    --cap-add=IPC_LOCK \
    -e VAULT_ADDR \
    -e VAULT_TOKEN \
    --mount type=bind,source="$HOME"/.stim,target=/home/vault/.stim \
    --mount type=bind,source="$HOME"/.aws,target=/home/vault/.aws \
    --mount type=bind,source="$HOME"/.vault-token,target=/home/vault/.vault-token \
    --mount type=bind,source="$HOME"/.kube,target=/home/vault/.kube \
    --mount type=bind,source="$(pwd)",target="$(pwd)" \
    -w "$PATH_FIX$(pwd)" \
    $VAULT_IMAGE:$VAULT_VERSION "$@"
}

# stim is a tool that makes it easier to work with vault and k8s and aws
# https://github.com/PremiereGlobal/stim
function stim() {
  if [[ "$ktools_useContainerizedCliTools" == "false" ]]; then
    command stim "$@"
    return $?
  fi

  local OPTIND
  local dockerArgs=()
  local envArgs=()
  local interactiveArgs=""

  if [[ "$1" == "--docker-args" ]]; then
    dockerArgs=($(echo "$2"))
    shift 2
  fi

  mkdir -p "$HOME/.stim"
  mkdir -p "$HOME/.aws"
  mkdir -p "$HOME/.kube"
  touch "$HOME/.vault-token"

  # If the end user has $KUBECONFIG set in env var, remap paths to the 
  # container mountpoint and pass it along.
  if [[ -n $KUBECONFIG ]]; then
      envArgs=("-e KUBECONFIG=${KUBECONFIG/#$HOME//root}")
  fi

  function dockerStim() {
    local versionSuffix=""
    local args=("$@")
    # there is a separate image tag for stim deploy that includes extra dependencies
    if [[ "$1" == "deploy" ]]; then
      versionSuffix="-deploy"
      # the deploy container has bash -c as an entrypoint so we need to add stim
      # to args and return as a single string. Wrapped in an array since the
      # normal container has stim as the entrypoint and needs the args as an array
      args=("stim $*")
    fi
    docker run --rm \
      "${dockerArgs[@]}" \
      ${interactiveArgs} \
      ${envArgs[@]} \
      -e VAULT_ADDR \
      -e AWS_SECRET_ACCESS_KEY \
      -e AWS_ACCESS_KEY_ID \
      -e VAULT_TOKEN \
      --mount type=bind,source="$HOME"/.stim,target=/stim \
      --mount type=bind,source="$HOME"/.aws,target=/root/.aws \
      --mount type=bind,source="$HOME"/.vault-token,target=/root/.vault-token \
      --mount type=bind,source="$HOME"/.kube,target=/root/.kube \
      --mount type=bind,source="$(pwd)",target="$(pwd)" \
      -w "$PATH_FIX$(pwd)" \
      "$STIM_IMAGE:v${STIM_VERSION}${versionSuffix}" "${args[@]}"
  }

  function isVaultTokenValid() {
    local vaultToken="$1"
    if [[ -z "$vaultToken" && -n "$VAULT_TOKEN" ]]; then
      vaultToken="$VAULT_TOKEN"
    elif [[ -z "$vaultToken" && -f ~/.vault-token ]]; then
      vaultToken=$(cat ~/.vault-token)
    fi
    if [[ -n "$vaultToken" ]] && vault token lookup $vaultToken &>/dev/null; then
      return 0
    else
      return 1
    fi
  }

  # check if we have a valid vault token to determine if we should run
  # with interactive mode (without a valid token it will have to be interactive)
  if ! isVaultTokenValid; then
    interactiveArgs="-it"
    dockerStim "$@"
  else
    # the user has a valid token so try running non-interactive first and if it
    # exits non zero, try it interactive. this is because some commands need to
    # be interactive but some commands will when interactive
    dockerStim "$@"
    local exitCode=$?
    if [ $exitCode -ne 0 ]; then
      echo "Detected input (exitCode $exitCode). Retrying with interactive opts" >&2
      interactiveArgs="-it"
      dockerStim "$@"
    fi
  fi
}

# https://github.com/kubernetes/kops
function kops() {
  if [[ "$ktools_useContainerizedCliTools" == "false" ]]; then
    command kops "$@"
    return $?
  fi

  local OPTIND
  local dockerArgs=()
  local envArgs=()

  if [[ "$1" == "--docker-args" ]]; then
    dockerArgs=($(echo "$2"))
    shift 2
  fi
  if [[ "$*" =~ (delete|edit) ]]; then
    if [[ -z "${dockerArgs[@]}" ]]; then
      dockerArgs=("-it")
    fi
  fi

  mkdir -p "$HOME/.aws"
  mkdir -p "$HOME/.kube"

  # If the end user has $KUBECONFIG set in env var, remap paths to the 
  # container mountpoint and pass it along.
  if [[ -n $KUBECONFIG ]]; then
      envArgs=("-e KUBECONFIG=${KUBECONFIG/#$HOME//root}")
  fi

  check_awscreds || return 1

  docker run --rm \
    "${dockerArgs[@]}" \
    ${envArgs[@]} \
    -e AWS_SECRET_ACCESS_KEY \
    -e AWS_ACCESS_KEY_ID \
    -e KOPS_STATE_STORE \
    --mount type=bind,source="$HOME"/.aws,target=/root/.aws,readonly \
    --mount type=bind,source="$HOME"/.kube,target=/root/.kube \
    --mount type=bind,source="$(pwd)",target="$(pwd)" \
    -w "$PATH_FIX$(pwd)" \
    --entrypoint "/usr/local/bin/kops" \
    $KOPS_IMAGE:$KOPS_VERSION "$@"
}

# https://github.com/hashicorp/terraform
function terraform() {
  if [[ "$ktools_useContainerizedCliTools" == "false" ]]; then
    command terraform "$@"
    return $?
  fi

  local OPTIND
  local dockerArgs=()
  local tf_vars=()

  if [[ "$1" == "--docker-args" ]]; then
    dockerArgs=($(echo "$2"))
    shift 2
  fi

  # get a list of TF_VAR prefixed env variables to pass into the container
  tf_vars=($(export | grep TF_VAR  | sed -e 's/export/-e/' -e 's/declare -x/-e/' -e 's/=.*$//'))

  check_awscreds || return 1

  docker run -it --rm \
    -e AWS_SECRET_ACCESS_KEY \
    -e AWS_ACCESS_KEY_ID \
    "${dockerArgs[@]}" \
    "${tf_vars[@]}" \
    --mount type=bind,source="$(pwd)",target="$(pwd)" \
    --network="host" \
    -w "$PATH_FIX$(pwd)" \
    $TERRAFORM_IMAGE:$TERRAFORM_VERSION "$@"
}



###
#
#   Convenience Functions
#
###


# This assumes one context per cluster generally
function kswitch() {
  local OPTIND
  local quiet
  local cluster
  local namespace
  local currentContext
  local currentContextNamespace

  function kswitchusage {
    echo "Usage: kswitch [-qn] <cluster-name>"
    echo ""
    echo "Switch to the cluster and optionally switch to the specified namespace"
    echo ""
    echo "Options:"
    echo "  -q - quiet mode"
    echo "  -n - namespace to use"
  }

  while getopts ":qn:h" opt; do
    case $opt in
      q)
        quiet=true
        ;;
      n)
        namespace="$OPTARG"
        ;;
      \?|h)
        kswitchusage
        return 0
        ;;
    esac
  done
  shift $(($OPTIND - 1))

  if [[ -z "$1" ]]; then
    kswitchusage >&2
    return 1
  fi
  cluster="$1"

  # If someone entered the short cluster name, convert to full name if found
  if [[ $cluster != *"."* ]]; then
    cluster="$(kclustername -o full $cluster || echo "$cluster")"
  fi
  currentContext="$(kcurrent)"
  if [[ "$currentContext" != "$cluster" ]]; then
    if [[ -z "$(kubectl config get-clusters | grep $cluster)" ]]; then
      local namespaceArg=""
      if [[ -n "$namespace" ]]; then
        namespaceArg="-n $namespace"
      fi
      kubeconfig -t stim $namespaceArg "$cluster" || return $?
    else
      kubectl config use-context $cluster || return $?
    fi
  elif [[ $quiet != "true" ]]; then
    echo "Context is already set to $cluster"
  fi

  # TODO: should we actually create a new context per cluster-namespace?
  if [[ -n "$namespace" ]]; then
    # check if we need to switch the context namespace
    currentContextNamespace=$(knamespace -c $cluster)
    if [[ "$currentContextNamespace" != "$namespace" ]]; then
      knamespace -c $cluster $namespace >> /dev/null
      if $? -ne 0; then
        echo "Failed to set the namespace on the context" >&2
        return 1
      elif [[ $quiet != "true" ]]; then
        echo "Context namespace switched from '$currentContextNamespace' to '$namespace'"
      fi
    fi
  fi
}

function kubeconfig() {
  local OPTIND
  local tool="stim"
  local contextName=""
  local contextNameArg=""
  local namespace=""
  local namespaceArg=""

  function kubeconfigusage() {
    echo "Usage: kubeconfig [-t] <cluster-name>"
    echo ""
    echo "Get the kube config for a k8s cluster using stim or kops"
    echo "stim requires vault access and kops requires AWS access"
    echo "In order to be non-interactive when using stim you must pass -n"
    echo ""
    echo "Options:"
    echo "  -t Use the specified tool to get the config. (default: stim)"
    echo "  -n Set the k8s namespace for the context"
    echo "  -c The kubectl context name to use"
    echo "  -h Show this help"
    echo "  <cluster-name> - the cluster name, can be the short name"
  }

  while getopts ":t:c:n:h" opt; do
    case $opt in
      t)
        if [[ -z "$2" || "$2" != "kops" && "$2" != "stim" ]]; then
          kubeconfigusage >&2
          echo "-t option had an invalid value" >&2
          return 1
        fi
        tool="$OPTARG"
        ;;
      n)
        namespace="$OPTARG"
        namespaceArg="-n $OPTARG"
        ;;
      c)
        contextName="$OPTARG"
        contextNameArg="-t $OPTARG"
        ;;
      \?|h)
        kubeconfigusage
        return 0
        ;;
    esac
  done
  shift $(($OPTIND - 1))

  if [[ -z "$1" ]]; then
    kubeconfigusage >&2
    echo "Missing cluster" >&2
    return 1
  fi
  cluster="$1"

  # If someone entered the short cluster name, add the suffix
  if [[ $cluster != *"."* ]]; then
    echo "Cannot look up config for a new cluster without the full name" >&2
    return 1
  fi

  if [[ -z "$contextName" ]]; then
    contextName="$cluster"
    contextNameArg="-t $cluster"
  fi

  if [[ "$tool" == "stim" ]]; then
    stim kube config -c ${cluster} ${namespaceArg} ${contextNameArg} -r
  else
    # kops
    kops export kubecfg $cluster || return $?
    if [[ -n "$namespace" ]]; then
      kubectl config set-context $contextName --namespace $namespace >> /dev/null
    fi
  fi
}

function kcurrent() {
  local OPTIND
  local shortName
  local context

  while getopts ":sh" opt; do
    case $opt in
      s)
        shortName="true"
        ;;
      \?|h)
        echo ""
        echo "Usage: kcurrent"
        echo ""
        echo "Displays current cluster context"
        echo ""
        echo "Options:"
        echo "  -s Show short name"
        echo "  -h Show this help"
        echo ""
        return 0
        ;;
    esac
  done

  context=""
  if [[ -e ~/.kube/config ]]; then
    if [[ ! -r ~/.kube/config ]]; then
      echo "Permissions on the local ~/.kube/config are incorrect" >&2
      echo "Requesting access to set proper permissions..." >&2
      sudo -k chown $(id -u):$(id -g) ~/.kube/config >&2
    fi
    # A much faster way to get the current context, the last part gets the last field
    context="$(cat ~/.kube/config | grep current-context | { read x; echo "${x##* }"; })"
  else
    # Fallback if the config file isn't in the default location
    context="$(kubectl config current-context)"
  fi

  if [[ "$shortName" == "true" ]]; then
    echo "${context%%.*}"
  else
    echo "$context"
  fi
}

function kclustername() {
  local OPTIND
  local validFormats=("opposite" "full" "short")
  local outputFormat="opposite"
  local inputFormat
  local inputCluster
  local clusterName
  local shortClusterName

  function kclusternameusage {
    echo ""
    echo "Usage: kclustername <cluster>"
    echo ""
    echo "Given a short or full cluster name print the cluster name in"
    echo "the given output format. Opposite means opposite of the input."
    echo "full is the full name. Short means the name up to the first '.' (dot)"
    echo ""
    echo "Options:"
    echo "  -o Output format: full, short, opposite (default is opposite)"
    echo "  -h Show this help"
    echo ""
  }

  while getopts ":o:h" opt; do
    case $opt in
      o)
        outputFormat="${OPTARG}"
        if [[ " ${validFormats[*]} " != *" $outputFormat "* ]]; then
          kclusternameusage >&2
          echo "Output format '$outputFormat' was not valid" >&2
          return 1
        fi
        ;;
      \?|h)
        kconfigusage
        return 0
        ;;
    esac
  done
  shift $(($OPTIND - 1))

  if [[ -z "$1" ]]; then
    kclusternameusage >&2
    return 1
  fi
  inputCluster="$1"

  if [[ $inputCluster != *"."* ]]; then
    inputFormat="short"
    # TODO: should we be able to do this with clusters not in kubeconfig?
    clusterName=$(kubectl config get-clusters | grep "^$inputCluster") || return 1
  else
    inputFormat="full"
    # TODO: should this check that the name is a valid cluster
    clusterName="$inputCluster"
  fi
  shortClusterName="${inputCluster%%.*}"

  if [[ "$outputFormat" == "short" ]] || [[ "$outputFormat" == "opposite" && "$inputFormat" == "full" ]]; then
    echo "$shortClusterName"
  else
    echo "$clusterName"
  fi
}

function kclusters() {
  kubectl config get-clusters
}

function kcontexts() {
  kubectl config get-contexts -o name
}

function knamespace() {
  local OPTIND
  local context
  if [[ "$1" == "-c" ]]; then
    context="$(kclustername -o full $2 || echo "$2")"
    shift 2
  else
    context="$(kcurrent)"
  fi

  if [[ -z "$1" ]]; then
    local contextLine="$(kubectl config get-contexts | grep "^[ *]*$context")"
    if [[ -z "$contextLine" ]]; then
      echo "Error: The context '$context' was not found" >&2
      return 1
    fi
    echo "${contextLine##* }"
    return
  fi
  
  kubectl config set-context $context --namespace="$1"
}

function kpod() {
  local search=$1
  local results
  local numResults
  local podName

  if [[ -z "$search" ]]; then
    echo "Usage: kpod <search-string>" >&2
    return 1
  fi

  results="$(kubectl get pods --no-headers -o name | grep -E $search)"
  numResults="$(echo "$results" | wc -l)"
  if [[ $numResults -gt 1 ]]; then
    echo "Search term '$search' matched more than one pod:" >&2
    echo "${results#pod/*}"
    return 1
  fi
  if [[ -z "$results" ]]; then
    echo "No pod was found matching '$search'." >&2
    return 1
  fi
  podName="${results#pod/*}"
  echo "$podName"
}

function klogs() {
  local search=$1
  local result

  if [[ -z "$search" ]]; then
    echo "Usage: klogs <search-string>" >&2
    return 1
  fi

  result="$(kpod $search)"
  if [[ $? == 0 ]]; then
    kubectl logs --timestamps=true $result
  else
    echo "$result" >&2
    return 1
  fi
}

function kversion() {
  local tool="$1"

  if [[ -z "$tool" || ! "$tool" =~ ^(kubectl|helm|vault|stim|kops|terraform|k8s-cluster|vault-server|tiller)$ ]]; then
    echo "Usage kversion <tool>"
    echo "  tool - kubectl, helm, vault, stim, kops, terraform, k8s-cluster, vault-server, tiller"
    return 1
  fi
  # echo "The version for $tool is"
  if [[ "$tool" == "helm" ]]; then
    helm version --template '{{ .Client.SemVer }}' | sed 's/^v//'
  elif [[ "$tool" == "tiller" ]]; then
    helm version --template '{{ .Server.SemVer }}' | sed 's/^v//'
  elif [[ "$tool" == "kubectl" ]]; then
    kubectl version --short --client | grep Client | sed 's/Client Version: v//'
  elif [[ "$tool" == "k8s-cluster" ]]; then
    kubectl version --short | grep Server | sed 's/Server Version: v//'
  elif [[ "$tool" == "kops" ]]; then
    kops version | sed 's/^Version *//' | sed 's/[[:blank:]].*//'
  elif [[ "$tool" == "terraform" ]]; then
    terraform version | grep "Terraform v" | sed 's/^Terraform v*//'
  elif [[ "$tool" == "stim" ]]; then
    stim version | sed 's/^stim\/v*//'
  elif [[ "$tool" == "vault" ]]; then
    # this is the cli
    vault version | grep "Vault v" | sed 's/^Vault v*//'
  elif [[ "$tool" == "vault-server" ]];  then
    # the last part takes everything after the last space e.g. 'version: 1.5.0' -> 1.5.0
    vault status -format yaml | grep version | { read x; echo "${x##* }"; }
  fi
  return $?
}

# This function only works when sourced
# This is a convenience function for getting aws credentials
# If you run `awscreds -a <aws-account> -r <role>` this will export the aws
# credentials as AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in the current
# shell non-interactively.
function awscreds() {
  stim vault login
  echo "Generating aws credentials"
  
  $(stim aws login -s "${@}")
  if [ $? -eq 0 ]; then
    echo "Your federated aws credentials have been exported"
    echo "Test them out by running a command that requires aws login"
  else
    echo "There was an error exporting federated aws credentials"
    return 1
  fi
}

function execute_cmd() {
  local cmd="$1"
  shift 1

  if [[ -z "$cmd" ]]; then
    usage >&2
    return 1
  elif [[ "$cmd" == "help" ]]; then
    usage
    return 0
  elif [[ "$cmd" =~ ^(kubectl|lenny|helm|vault|stim|kops|terraform|kswitch|kclustername|kcurrent|kcontexts|kubeconfig|kclusters|klogs|knamespace|kpod|kversion)$ ]]; then
    $cmd "$@"
  elif [[ "$cmd" =~ ^(config|kvm|kconfig|awscreds)$ ]]; then
    if [[ "$ktools_isSourced" == "true" ]]; then
      $cmd "$@"
    else
      echo "The '$cmd' command is only available when ktools is sourced. Run '. ktools.sh; ktools $cmd'" >&2
      return 1
    fi
  else
    echo "'$cmd' is not a valid command." >&2
    usage
    return 1
  fi
}

function usage() {
  echo "ktools - A set of tools for executing dockerized kubernetes commands (and related tools)"
  echo ""
  echo "Commands:"
  echo "  ktools - print out usage or specify one of the other commands after it"
  echo "    to execute the command"
  echo ""
  # this is only available if the tools were sourced
  if [[ "$ktools_isSourced" == "true" ]]; then
  echo "  ktools config or (kconfig) - set config properties (like enabling or disabling containerized tools)"
  echo "    run without args to see supported config properties"
  echo ""
  echo "  kvm - set the version a tool (containerized tools must be enabled)"
  echo "    tool - kubectl, helm, kops, stim, vault, terraform"
  echo "    version - a semver version or 'auto' to pull from the current cluster"
  echo ""
  fi
  echo "  kversion - get the version of cli tools and servers"
  echo "    tool - kubectl, helm, kops, k8s-cluster, tiller, stim, vault, vault-server, terraform"
  echo ""
  echo ""
  echo "  kubectl (lenny) - Runs a dockerized version of kubectl"
  echo "    --docker-args - Takes a string of arguments to pass to 'docker run'"
  echo ""
  echo "  helm - Runs a dockerized version of helm"
  echo "    --docker-args - Takes a string of arguments to pass to 'docker run'"
  echo ""
  echo "  vault - Runs a dockerized version of vault"
  echo "    --docker-args - Takes a string of arguments to pass to 'docker run'"
  echo ""
  echo "  stim - Runs a dockerized version of stim"
  echo "    --docker-args - Takes a string of arguments to pass to 'docker run'"
  echo "    Note: stim will run non-interactive first and if that fails it will"
  echo "          fall back to interactive mode"
  echo ""
  echo "  kops - Runs a dockerized version of kops"
  echo "    --docker-args - Takes a string of arguments to pass to 'docker run'"
  echo ""
  echo "  terraform - Runs a dockerized version of terraform"
  echo "    --docker-args - Takes a string of arguments to pass to 'docker run'"
  echo ""
  echo ""
  echo "  awscreds - Get federated aws credentials from vault via stim"
  echo ""
  echo "  kclustername <cluster> - Given a short or full cluster name print the cluster name"
  echo "    -o <output-format> - Options: opposite (default), full, short"
  echo "    cluster - The name of the cluster. Can also use the short name (everything before the first dot)"
  echo ""
  echo "  kclusters - View the names of the clusters in your kubeconfig"
  echo ""
  echo "  kcontexts - View the names of the contexts in your kubeconfig"
  echo ""
  echo "  kcurrent - View the current cluster context name"
  echo ""
  echo "  kswitch - Switch the current cluster context (will get kube config if missing)"
  echo "    cluster - The name of the cluster. Can also use the short name (everything before the first dot)"
  echo ""
  echo "  kubeconfig - Get the kube config for the cluster"
  echo "    -c      - The name to use for the context (defaults to full cluster name)"
  echo "    -n      - The namespace to set in the context (will prompt if not specified)"
  echo "    -t      - what tool to get the config from. Options: stim or kops (default is stim)"
  echo "    cluster - The name of the cluster. Can also use the short name (everything before the first dot)"
  echo ""
  echo "  knamespace - Switch the current context namespace"
  echo "    namespace - The namespace to switch to"
  echo ""
  echo "  klogs - Get logs for a pod"
  echo "    search-string - A regex matched against a pod name (i.e. 'service-name.*')"
  echo ""
  echo "  kpod - Get the name of a pod"
  echo "    search-string - A regex matched against a pod name (i.e. 'service-name.*')"
  echo ""
  echo "Source the ktools.sh script to export these commands in your shell. '. ktools.sh'"
  echo "Pass the '--ktools-modify-prompt' option when sourcing to display the current cluster context in your prompt."
  echo "Pass the '--ktools-disable-containers' option when sourcing to use native cli tools for kubectl, helm, and kops rather than the containerized ones."
}

if [[ "$ktools_isSourced" == "true" ]]; then
  ktools_modifyPrompt=false

  ## It turns out that if you source a script without any args, it is passed
  ## all the args from the script that sourced it so we should prefix args
  ## added here and not use getopts

  for arg in "$@"
  do
      case $arg in
        "--ktools-modify-prompt")
          ktools_modifyPrompt=true
          ;;

        "--ktools-disable-containers")
          ktools_useContainerizedCliTools=false
          ;;
      esac
  done

  # Change prompt if --ktools-modify-prompt option is passed
  if [[ "$ktools_modifyPrompt" == "true" ]]; then
    ktools_k8sPrompt="k8s:(\$(kcurrent -s)) "
    if [[ ! -z "$BASH_VERSION" ]]; then
      ktools_k8sPrompt="\[\033[01;32m\]k8s:(\[\033[01;95m\]\$(kcurrent -s)\[\033[01;32m\])\[\033[0m\] "
    elif [[ ! -z "$ZSH_VERSION" ]]; then
      ktools_k8sPrompt="%{$fg_bold[green]%}k8s:(%{$fg_bold[magenta]%}\$(kcurrent -s)%{$fg_bold[green]%})%{$reset_color%} "
    fi
    if [[ ! "$PS1" =~ k8s:(.*) ]]; then
      export ktools_origPrompt="$PS1"
      PS1="$PS1$ktools_k8sPrompt"
    fi
  fi

  function kconfig() {
    local propertyName="$1"
    local propertyValue="$2"
    if [[ -z "$propertyName" ]]; then
      echo "Usage: kconfig <property-name> [property-value]"
      echo ""
      echo "  If the property-value is not specified, the current value will be printed"
      echo ""
      echo "  Properties:"
      echo "    containers: true|false - whether to use containerized tools or system tools"
      echo "    vault-addr: <string> - the vault api url to use, e.g. https://vault.example.com"
      echo "    kops-state-store: <string> - the kops store to use, e.g. s3://my-kops-cluster-state"
      return 1
    fi

    if [[ "$propertyName" == "containers" ]]; then
      if [[ -z "$propertyValue" ]]; then
        echo $ktools_useContainerizedCliTools
      elif [[ "$propertyValue" == "true" || $propertyValue == "false" ]]; then
        ktools_useContainerizedCliTools="$propertyValue"
        echo "containers set to $propertyValue"
      else
        echo "Valid values for containers are: true, false" >&2
        return 1
      fi
    elif [[ "$propertyName" == "vault-addr" ]]; then
      if [[ -z "$propertyValue" ]]; then
        echo "$VAULT_ADDR"
      else
        export VAULT_ADDR="$propertyValue"
      fi
    elif [[ "$propertyName" == "kops-state-store" ]]; then
      if [[ -z "$propertyValue" ]]; then
        echo "$KOPS_STATE_STORE"
      else
        export KOPS_STATE_STORE="$propertyValue"
      fi
    else
      echo "'$propertyName' is not a valid config property." >&2
      echo "Run config without a property name to see supported properties" >&2
      return 1
    fi
  }

  function kvm() {
    local tool="$1"
    local version="$2"

    function kvmusage {
      echo "Usage kvm <tool> <version>"
      echo "  tool - kubectl, helm, vault, stim, kops, terraform"
      echo "  version - the semver version to install or 'auto' to fetch from the relevant server (kubectl or vault only)"
    }

    if [[ "$ktools_useContainerizedCliTools" == "false" ]]; then
      echo "kvm currently only works if containerized tools are enabled" >&2
      echo "run 'ktools config containers true' to enable containerized tools" >&2
      return 1
    fi

    if [[ -z "$tool" || -z "$version" || ! "$tool" =~ ^(kubectl|helm|vault|stim|kops|terraform)$ ]]; then
      kvmusage >&2
      return 1
    fi

    if [[ "$version" == "$oldVersion" ]]; then
      echo "The version for $tool is already set to $version"
      return
    fi

    if [[ "$version" == "auto" ]]; then 
      if [[ "$tool" == "kubectl" ]]; then
        local cluster=$(kcurrent -s)
        version="$(kversion k8s-cluster)"
        if [[ "$version" == "" ]]; then
          echo "Failed to get k8s version from $cluster." >&2
          return 1
        fi
        echo "k8s version on $cluster is $version, using that version for kubectl"
      elif [[ "$tool" == "vault" ]]; then
        version=$(kversion vault-server)
        if [[ "$version" == "" ]]; then
          echo "Failed to get vault version from the configured vault server." >&2
          return 1
        else
          echo "Vault version on $VAULT_ADDR is $version. Using that version for vault cli"
        fi
      elif [[ "$tool" == "helm" ]]; then
        local cluster=$(kcurrent -s)
        version="$(kversion tiller)"
        if [[ "$version" == "" ]]; then
          echo "Failed to get tiller version from $cluster. The cluster might be using helm 3" >&2
          return 1
        fi
        echo "Tiller version on $cluster is $version, using that version for helm"
      else
        echo "$tool doesn't support auto versioning" >&2
        return 1
      fi
    fi

    local versionVarName="$(echo $tool | awk '{ print toupper($0) }')_VERSION"
    local oldVersion="${!versionVarName}"

    # remove a prepended v from the version
    if [[ "$version" == v* ]]; then
      version="${version#v*}"
    fi

    echo "Changing version for $tool to $version"
    declare -x "$versionVarName=$version"

    # confirm that the version is valid
    newVersion=$(kversion "$tool" 2> /dev/null)
    if [[ $? -ne 0 || -z "$newVersion" ]]; then
      echo "Failed to switch $tool to version $version. Either the version is invalid or there is not a docker image for that version." >&2
      echo "Please check the $tool releases and the DockerHub tags for the image being used." >&2
      declare -x "$versionVarName=$ooldVersion"
      return 1
    fi
    echo "Successfully changed version for $tool from "$ooldVersion" to $newVersion"
  }

  # Export the functions for further use
  function ktools() {
    # if no args, print usage
    if [[ -z "$1" ]]; then
      usage
    fi

    if [[ "$1" == "config" ]]; then
      kconfig "${@:2}"
    else
      execute_cmd "$@"
    fi
  }
  export -f \
    kubectl \
    lenny \
    helm \
    vault \
    stim \
    terraform \
    kops \
    kversion \
    kvm \
    kclusters \
    kcontexts \
    kclustername \
    kcurrent \
    knamespace \
    kswitch \
    kubeconfig \
    klogs \
    kpod \
    check_awscreds \
    awscreds \
    kconfig \
    ktools \
    > /dev/null
else
  # Run commands if script is executed
  execute_cmd "$@" || exit 1
fi
