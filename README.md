# ArgoCD Sample Application(s)

To use this repository you must have a working ArgoCD installation deployed into a kubernetes cluster

Then all you have to do is to apply the `root-app.yaml` file to your cluster and watch all the apps in `apps` folder get deployed into the `project-nginx` project of ArgoCD

`kubectl apply -f root-app.yaml`

