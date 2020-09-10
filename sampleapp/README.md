Sample app
==========

Example of exposing an app on a hostname with a custom domain which may not necessarily match the OpenShift route's domain.

TODO

```sh
kubectl create secret generic server-pfx --from-file=server.pfx=./server.pfx
```

References
----------

* https://thorsten-hans.com/6-steps-to-run-netcore-apps-in-azure-kubernetes
* https://docs.microsoft.com/en-us/aspnet/core/security/docker-https?view=aspnetcore-3.1
* https://medium.com/@tbusser/creating-a-browser-trusted-self-signed-ssl-certificate-2709ce43fd15
