# Gloo-SP-5913 Reproducer


## Installation

Add Gloo EE Helm repo:
```
helm repo add glooe https://storage.googleapis.com/gloo-ee-helm
```

Export your Gloo Edge License Key to an environment variable:
```
export GLOO_EDGE_LICENSE_KEY={your license key}
```

Install Gloo Edge:
```
cd install
./install-gloo-edge-enterprise-with-helm.sh
```

> NOTE
> The Gloo Edge version that will be installed is set in a variable at the top of the `install/install-gloo-edge-enterprise-with-helm.sh` installation script.

## Setup the environment

Run the `install/setup.sh` script to setup the environment:

- Deploy the HTTPBin service
- Deploy the VirtualServices

```
./setup.sh
```

Note that in this environment we've configured the validation webhook to:
- Reject invalid resources (resources that would result in an error state)
- Reject resources that would result in a warning

This is a key configuration setting for this reproducer!!!

Also, we've configured the `replaceInvalidRoutes` option, that causes invalid routes to be still accepted but replaced by the a standard (error) response.

## Reproducer

The Gloo Edge discovery service automatically creates an `Upstream` resource for the deploted `httpbin` K8S service:

```
kubectl -n gloo-system get upstream
```

You will see the `httpbin-httpbin-8000` `Upstream` in that list.

Delete the `httpbin` K8S service:

```
kubectl -n httpbin delete svc httpbin
```

Note that the `Upstream` is still there:

```
kubectl -n gloo-system get upstream
```

The reason for this is that we still have a `VirtualService` that references the `httpbin-httpbin-8000` `Upstream`, and deleting that `Upstream` would result in a "Warning" on the given `VirtualService`. Hence, when the Discovery service tries to delete the `Upstream`, that delete is rejected by the validation webhook, as it would result in the `VirtualService` going into a "Warning" state.

You can check the logs of the Discovery and Gloo pods to see the log messages that show the rejection of the Upstream deletion:

```
kubectl -n gloo-system logs -f discovery-{id}
```

```
kubectl -n gloo-system logs -f gloo-{id}
```

The problem in this specific case is that, because we've configured the "replace invalid route" option, the intend is that the VirtualService is properly accepted and the invalid routes are replaced. However, even with this setting, the status of the VirtualGateway is set to "Warning", causing the validating webhook to reject the removal of the Upstream.

When you now delete the `VirtualService` that is referencing the `httpbin-httpbin-8000` `Upstream`, the `Upstream` will eventually be removed (after the discovery cycle runs):

```
kubectl -n gloo-system delete vs vs
```

## Conclusion
By configuring the validation webhook to reject updates that would result in Gloo resources going into a "Warning" state (i.e. `gloo.gateway.validation.alwaysAcceptResources: false` and `gloo.gateway.validation.allowWarnings: false`), the automatic deletion of the `Upstream` by the discovery service is rejected, as there is still a `VirtualService` referencing the `Upstream`. After deleting the given `VirtualService`, the `Upstream` will be automatically deleted on the next discovery run.

The issue here is that it is expected that, because the "Replace Invalid Route" options is enabled, the Upstream should just be automatically deleted.
