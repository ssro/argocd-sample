# ArgoCD Sample Application(s)

> NOTE:
> 
> This repository serves as a test bed for ArgoCD applications deployed using kustomize and/or helm (currently only kustomize). Feel free to run this on your local argo installation. It comprises only of a working set of nginx and httpd vanilla images. In case you'd like to expand on this or try new things, fork it then change all the `repoURL` paths in the files to reflect your own.

To use this repository you must have a working ArgoCD installation deployed into a kubernetes cluster.

Then all you have to do is to apply the `root-app.yaml` file to your cluster and watch all the apps in `apps` folder get deployed in the webUI of argo.

`kubectl apply -f root-app.yaml`

Have fun!
