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
kubectl -n gloo-system delete vs api-example-com-vs
```

## Conclusion
By configuring the validation webhook to reject updates that would result in Gloo resources going into a "Warning" state (i.e. `gloo.gateway.validation.alwaysAcceptResources: false` and `gloo.gateway.validation.allowWarnings: false`), the automatic deletion of the `Upstream` by the discovery service is rejected, as there is still a `VirtualService` referencing the `Upstream`. After deleting the given `VirtualService`, the `Upstream` will be automatically deleted on the next discovery run.

The issue here is that it is expected that, because the "Replace Invalid Route" options is enabled, the Upstream should just be automatically deleted.

> [!NOTE]
> There is a setting in Gloo Edge that allows you to bypass/skip the validation webhook when you delete certain resources: `gloo.gateway.validation.webhook.skipDeleteValidationResources`. This allows you to configure that when an `Upstream` is deleted, the webhook should be skipped.
> ```
> gloo:
>   gateway:
>     # Configure Validating Admission Webhook to reject resources (normally invalid resources are only logged).
>     validation:
>       enabled: true
>       # Reject invalid resources (resources that would result in an error state)
>       alwaysAcceptResources: false
>       # Reject resources that would result in a warning
>       allowWarnings: false
>       # Disable validation webhook when deleting the following resources.
>       webhook:
>         skipDeleteValidationResources:
>         - upstreams
> ```

> [!NOTE]
> With the `skipDeleteValidationResources` configuration set to skip validation when deleting `Upstreams`, you can end up in an interesting scenario.
>
> With this setting enabled, execute the following steps:
> 1. Deploy the second httpbin service: `kubectl apply -f apis/httpbin2.yaml`
> 1. Deploy the `developer-example-com-vs.yaml` `VirtualService`: `kubectl apply -f virtualservices/developer-example-com-vs.yaml`
> 1. Remove the `httpbin` and `httpbin2` APIs: `kubectl delete -f apis/httpbin.yaml,apis/httpbin2.yaml`
> 
> You will now be in a situation where you have 2 `VirtualServices` `api-example-com-vs` and `developer-example-com-vs` that are both in "Warning" state.
>
> When you:
> * try to re-deploy the `httpbin` and `httpbin2` services, their Upstreams are not created, because the 2 `VirtualServices` are in warning state.
> * try to delete `api-example-com-vs`, you can't because `developer-example-com-vs` is still in a warning state. 
> * try to delete `developer-example-com-vs`, you can't because `api-example-com-vs` is still in a warning state.
> * try to delete `developer-example-com-vs` and `api-example-com-vs` at the same time, you can't because deletion of multiple resources is not an atomic operation in K8S ...
> 
> The only solution out of this that I was able to find is to configure the webhook to also not run on deletion of `VirtualServices` or creation of `Upstreams`.
>
> When I try to apply to reconfigure the webhook via a Helm upgrade, I can't because the pre-upgrade hook fails because of the fact that the system is in a "Warning" state on the `VirtualServices`. So you need to configure this setting directly on the `ValidatingWebhookConfiguration` CR (i.e. remove the `DELETE` operation on the `Virtualservices` configuration in the `rules` section of the CR). 
>
> When you now delete the virtualservices that are in a "Warning" state, the `Upstreams` for the redeployed `httpbin` and `httpbin2` services will be created on the next discover run. After this you can re-apply the `VirtualService` to get the system back into a working state.
>
> Manually creating the missing `Upstreams` to get the system out of "Warning" state does not work, as the creation of the `Upstreams` will get rejected by the validating webhook. To get the system out of this state, we would need to apply the 2 missing `Upstreams` at the same time to fix the 2 `VirtualServices`, but applying K8S resources is not an atomic operation, so you can't apply the 2 `Upstreams` at the same time. And hence, the validation webhook will always see one of the `VirtualServices` in a "Warning" state after applying an `Upstream`, and hence will reject the creation of that `Upstream`.