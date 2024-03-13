#!/bin/sh

# VirtualServices
kubectl -n gloo-system delete virtualservice vs

# Delete httpbin namespace
kubectl delete namespace httpbin

# Delete the upstream (if needed)
kubectl -n gloo-system delete upstream httpbin-httpbin-8000