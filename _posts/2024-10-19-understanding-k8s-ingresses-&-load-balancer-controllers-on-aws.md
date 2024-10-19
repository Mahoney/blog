---
layout: post
title: Understanding K8S Ingresses & Load Balancer Controllers on AWS
date: '2024-10-19T12:40:38.000+0100'
author: Robert Elliot
tags:
---

Some notes from my recent battles with AWS NLBs & the Ingress-Nginx Controller.

In order to expose a K8S cluster running on AWS EC2 instances (as an EKS cluster does) you will need an ELB in some
form to load balance across the EC2 instances hosting the cluster. The ELB can either _be_ a K8S ingress or it can be
a route to the K8S ingress - that is, the actual ingress running inside the K8S cluster is exposed on ports on the
EC2 instances, and the ELB balances across those nodes.

## Types of AWS Load Balancer Controller

There are two types of AWS Load Balancer Controller.

1. The legacy in-tree controller

   This is baked into an EKS kubernetes cluster without any installation. You do not see any Pods or Service or Ingress
   Class for it as resources inside the cluster.

   It will create an NLB for any K8S Service with `spec: type: LoadBalancer` which will proxy to that service.

   It is legacy and deprecated.

2. The [AWS Load Balancer Controller][aws_lbc]

   This is an external controller. It can be installed via helm. It will create resources (a Deployment, Pods, an
   Ingress Class) in the cluster.

   It will create an NLB for any K8S Service with `spec: type: LoadBalancer` which will proxy to that service.

   It will create an ALB for any K8S Ingress with `spec: ingressClassName: alb`.

   It is the recommended way to integrate with AWS load balancers.

   Prior to v2 it was called the [AWS ALB Ingress Controller][aws_alb_ingress]
   which is deprecated.

   [Installation is documented here][aws_lbc_install].

### Differences between the Controller types

Importantly, many of the [documented annotations][aws_lbc_annotations] are not supported by the legacy in-tree
controller. This includes the [`service.beta.kubernetes.io/aws-load-balancer-proxy-protocol`][aws_load_balancer_proxy_protocol]
we will discuss below.

Some of the [documented annotations][aws_lbc_annotations] have different default values. Notably
[`service.beta.kubernetes.io/aws-load-balancer-scheme`][aws_load_balancer_scheme] (whether the provisioned ELB should be
`internal` or `internet-facing`) defaults to `internet-facing` on the AWS Load Balancer Controller but `internal` on the
legacy in-tree controller.

## The Ingress-Nginx Controller

The [Ingress-Nginx Controller][ingress_nginx] is probably the preferred K8S Ingress Class when running on AWS. It allows
you to manage your ingress costs inside the cluster, by making your K8S Services have `spec: type: ClusterIP` and
exposing them via an Ingress with `spec: ingressClassName: nginx`, whereas using a K8S Service with
`spec: type: LoadBalancer` or an Ingress with `spec: ingressClassName: alb` will create further costly AWS ELBs. A
single NLB can then act as the front door to the Ingress-Nginx Controller.

Installation of the Ingress-Nginx Controller creates, among other things, a K8S Service and Deployment. The K8S Service
will have `spec: type: LoadBalancer`, which on AWS with the AWS Load Balancer Controller installed will provision an NLB
to proxy traffic to the exposed port(s) on the EC2 instances, which in turn will forward that traffic to the nginx pods.

### Configuring the provisioned NLB

The nature of the provisioned NLB can be controlled by adding [AWS annotations][aws_lbc_annotations] to the nginx K8S
Service. For our purposes important values are:

- [`service.beta.kubernetes.io/aws-load-balancer-scheme`][aws_load_balancer_scheme]

  Not a URI scheme, instead whether the provisioned ELB should be `internal` or `internet-facing`.

- [`service.beta.kubernetes.io/aws-load-balancer-ssl-cert`][aws_load_balancer_ssl_cert]

  The ARN of an [AWS Certificate Manager][aws_acm] TLS certificate that will be served by the NLB to allow it to serve
  https requests.
- [`service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: '*'`][aws_load_balancer_proxy_protocol]

  If present, the generated Target Groups will be configured to send the [Proxy Protocol v2](#proxy-protocol-v2) header.

### Installing the Ingress-Nginx Controller

#### Via Manifest

The Ingress-Nginx team [provide a manifest for installing the controller with TLS terminated at the NLB][ingress_nginx_nlb_tls].
It requires setting a couple of values, documented in the linked installation instructions. However, it has several
quirks to be aware of:

1. It does not enable [Proxy Protocol v2](#proxy-protocol-v2) on either the NLB or nginx

   See [Enabling Proxy Protocol v2](#enabling-proxy-protocol-v2)

2. It only creates one replica of the nginx pod

   As the pods are exposed on the EC2 instances forming the cluster's nodes as the registered targets of the NLB's
   target group(s), this means that all but one of the registered targets will be considered unhealthy.

   This can be fixed by adding `spec: replicas: 2` (or however many EC2 nodes you have) to the Deployment manifest.

3. It does not specify a value for [`service.beta.kubernetes.io/aws-load-balancer-scheme`][aws_load_balancer_scheme]

   So whether your NLB is internet facing will depend on the default, which [differs per AWS controller
   type](#differences-between-the-controller-types).

   This can be fixed by adding [`metadata: annotation: service.beta.kubernetes.io/aws-load-balancer-scheme`][aws_load_balancer_scheme]
   to the Service manifest.

4. It takes control of redirecting `http` to `https`, preventing management of this at the Ingress resource level

   [Full discussion below](#http-to-https-redirection).

##### Enabling Proxy Protocol v2

[Proxy Protocol v2](#proxy-protocol-v2) can be enabled as so:

1. On the NLB side by adding
   [`metadata: annotation: service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: '*'`][aws_load_balancer_proxy_protocol]
   to the Service manifest
2. On the nginx side by adding `data: use-proxy-protocol: "true"` to the ConfigMap manifest

##### http to https redirection

The nlb-with-tls-termination manifest implements http to https redirection by exposing an extra port 2443 named
`tohttps` on the nginx Pods, adding a special listener on port 2443 to nginx via `data: http-snippet:` on the ConfigMap
that always returns a 308 to https, and then specifying that the http port on the Service manifest has a target port of
`tohttps`, which configures the NLB's Target Group for port 80 to route traffic to port 2443 on the nginx pod
(ultimately - there is a further port mapping on the EC2 instance to get to 2443).

Given that it does not enable [Proxy Protocol v2](#proxy-protocol-v2), it makes sense for the manifest to do this, as
most services that serve over TLS will want a redirect from http to https and without the Proxy Protocol nginx cannot
know what the original protocol was. An NLB cannot do the redirect, so it has to happen at the nginx level.

This breaks if you enable [Proxy Protocol v2](#proxy-protocol-v2), because the `http-snippet` on the ConfigMap will not
be updated to expect the proxy protocol header despite adding `data: use-proxy-protocol: "true"` to the ConfigMap
resource.

Redirecting via a custom port is unnecessary if you have a `spec: tls: hosts` array on the Ingress resource **AND** you
have [Proxy Protocol v2](#proxy-protocol-v2) enabled (so that nginx knows if the request were actually via https), as
that will configure nginx to send redirects from http to https for all rules in that Ingress resource by default, and
will also allow you to disable this behaviour per Ingress by adding
`metadata: annotations: nginx.ingress.kubernetes.io/ssl-redirect: "false"` to the Ingress resource.

The Ingress redirect only works if you specify a `spec: tls: hosts` array on the Ingress resource. I'm not sure if this
is an odd thing to do if TLS is being terminated downstream of the ingress at the NLB.

If you need precise control over which services have and do not have http to https redirects, it can be achieved with
the following steps:

1. [Enable Proxy Protocol v2](#enabling-proxy-protocol-v2).
2. Change the Service manifest - find the `spec: ports` port with name `http` and change its `targetPort` from `tohttps`
   to `http`.
3. Change the Deployment manifest - find the `spec: template: spec: containers` container with name `controller`. Delete
   the port with name `tohttps`.
4. Change the ConfigMap manifest - delete the `data: http-snippet`.
5. Make any Ingress resources you have that should redirect from http to https have a `spec: tls: hosts` containing all
   the hosts they serve, and `metadata: annotations: nginx.ingress.kubernetes.io/ssl-redirect: "false"` if they should
   serve over http.

Other options I have not yet explored in full:

1. Terminate TLS at nginx rather than the ELB. Then it makes sense to have `spec: tls: hosts` on the Ingress resources,
   and there is no need to worry about Proxy Protocol v2. Requires getting the certificate into K8S so nginx can serve
   it.
2. Use an ALB rather than an NLB by adding `metadata: annotations: service.beta.kubernetes.io/aws-load-balancer-type: alb`
   to the Service manifest. This should remove the need to have Proxy Protocol v2 enabled.

#### Via Helm

There is an [Ingress-Nginx Controller Helm chart][ingress_nginx_helm]. I have not experimented with it yet but it may
be possible to use it to avoid tweaking a downloaded manifest.

## Proxy Protocol v2

Typically, a network layer 4 device like an NLB cannot provide any further information to the upstream services to which
it proxies. The bits are simply sent "as is". This is a problem with TLS terminated at the NLB, because a typical
HTTP request does not contain the requested scheme within the body of the request. Consequently, the fact that the
original scheme was `https` is lost to upstream services. Upstream services may need to construct URLs with that
knowledge.

The [Proxy Protocol v2][proxy_protocol] specifies a way for Layer 4 devices like an NLB to provide proxy information to
upstream services via a header sent _before_ the rest of the request (including before the request line). The [Target
Groups for AWS NLBs can be configured to send it][aws_proxy_protocol] (in the console, edit the Target Group's
"Attributes"), and [nginx can be configured to expect it][nginx_proxy_protocol].

Ideally applications do not need this information - they should return links as URI references rather than URLs, either
omitting the scheme (e.g. `//example.com/my/thing`) or the entire authority (e.g. `/my/thing`). However, some frameworks
insist on returning URLs for e.g. the [`Location` header][location_header], reconstructing the scheme from the
`X-Forwarded-Proto` or [`Forwarded` header][forwarded_header], falling back on the scheme the process is listening for,
because previous (obsolete) versions of the HTTP specification
[required the `Location` header to contain a URL][rfc_2616_location_header].

If http to https redirection is expected to happen upstream of an NLB then proxy information will be required.

[aws_lbc]: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/
[aws_alb_ingress]: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v1.1/
[aws_lbc_annotations]: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.0/guide/service/annotations/
[aws_load_balancer_proxy_protocol]: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.9/guide/service/annotations/#proxy-protocol-v2
[aws_load_balancer_scheme]: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.9/guide/service/annotations/#lb-scheme
[aws_load_balancer_ssl_cert]: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.9/guide/service/annotations/#ssl-cert
[aws_lbc_install]: https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
[aws_acm]: https://us-east-1.console.aws.amazon.com/acm/home
[ingress_nginx]: https://kubernetes.github.io/ingress-nginx/
[proxy_protocol]: https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt
[nginx_proxy_protocol]: https://nginx.org/en/docs/stream/ngx_stream_proxy_module.html#proxy_protocol
[aws_proxy_protocol]: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html#target-group-attributes
[location_header]: https://www.rfc-editor.org/rfc/rfc9110.html#name-location
[forwarded_header]: https://www.rfc-editor.org/rfc/rfc7239.html
[rfc_2616_location_header]: https://www.rfc-editor.org/rfc/rfc2616#section-14.30
[ingress_nginx_nlb_tls]: https://kubernetes.github.io/ingress-nginx/deploy/#tls-termination-in-aws-load-balancer-nlb
[ingress_nginx_helm]: https://kubernetes.github.io/ingress-nginx/deploy/#quick-start
