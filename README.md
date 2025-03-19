# ArgoCD Sample Application(s)

> NOTE:
> 
> This repository serves as a test bed for ArgoCD applications deployed using kustomize and/or helm ~~(currently only kustomize)~~. Feel free to run this on your local argo installation. It comprises only of a working set of nginx and httpd vanilla images. In case you'd like to expand on this or try new things, fork it then change all the `repoURL` paths in the files to reflect your own.

To use this repository you must have ~~a working ArgoCD installation deployed into~~ a working kubernetes cluster.

## Prerequisites:

Deploy ArgoCD using helm (one time operation)

NOTE: make sure this step uses the same custom values (if any) as the ones [here](apps/argocd/application.yaml#L19-L96)

```
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo-cd/argo-cd --namespace=argocd --create-namespace --version 7.8.11 -f /path/to/values.yaml # in case you use custom values 
```

Ideally you should pass custom values to helm. [These](apps/argocd/application.yaml#L19-L96) would make the best fit, since it will not restart any pods after deploying the root-app (see below).

## Access ArgoCD

- access argo by doing a port-forward:

`kubectl port-forward svc/argocd-server 8080:443 -n argocd`

- get the initial password of argo for the `admin` user:

`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

- login to https://localhost:8080 (accept the self signed cert)

- link your github repo that contains the `root-app.yaml` to argo here https://localhost:8080/settings/repos

## Install the root-app

Then all you have to do is to apply the `root-app.yaml` file to your cluster and watch all the apps in `apps` folder get deployed in the webUI of argo.

`kubectl apply -f root-app.yaml`

Now there's ArgoCD deployed in the cluster managing itself and the rest of the apps

The initial helm installation can be safely ignored (but do not delete it) as it's not needed anymore for updating ArgoCD.

Have fun!
