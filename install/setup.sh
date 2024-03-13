#!/bin/sh

pushd ..

# Create httpbin namespace if it does not yet exist
kubectl create namespace httpbin --dry-run=client -o yaml | kubectl apply -f -

printf "\nDeploy HTTPBin service ...\n"
kubectl apply -f apis/httpbin.yaml

# Would be nice if kubectl had the "wait-for-creation" flag .... https://github.com/kubernetes/kubernetes/pull/122994
printf "\nWait a couple of seconds for the Upstream to get created and the admission webhook not reject the VirtualService that we're gonna deploy in the next step.\n"
sleep 4 

# VirtualServices
printf "\nDeploy VirtualServices ...\n"
kubectl apply -f virtualservices/api-example-com-vs.yaml

popd