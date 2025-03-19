# ArgoCD Sample Application(s)

> NOTE:
> 
> This repository serves as a test bed for ArgoCD applications deployed using kustomize and/or helm ~~(currently only kustomize)~~. Feel free to run this on your local argo installation. It comprises only of a working set of nginx and httpd vanilla images. In case you'd like to expand on this or try new things, fork it then change all the `repoURL` paths in the files to reflect your own.

To use this repository you must have ~~a working ArgoCD installation deployed into~~ a working kubernetes cluster.

## Prerequisites:

Deploy ArgoCD using helm

```
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo-cd/argo-cd --namespace=argocd --create-namespace --version 7.8.11 # (use "-f /path/to/values.yaml", in addition, for custom values) 
```

Ideally you should pass custom values to helm. [These](apps/argocd/application.yaml#L19-L96) would make the best fit, since it will not restart any pods after deploying the root-app (see below).

## Install the root-app

Then all you have to do is to apply the `root-app.yaml` file to your cluster and watch all the apps in `apps` folder get deployed in the webUI of argo.

`kubectl apply -f root-app.yaml`

Now there's ArgoCD deployed in the cluster managing itself and the apps

Have fun!
