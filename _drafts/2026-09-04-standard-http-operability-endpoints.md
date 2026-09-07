---
layout: post
title: Standard HTTP Operability Endpoints
date: '2026-09-04T11:42:14.000+0100'
author: Robert Elliot
tags:
---

A standard set of HTTP endpoints a service should expose for the infrastructure that runs it. Recommendations first,
reasoning after.

## Recommendations

One port, the one that serves traffic. Everything operability lives under `/-/`. Restrict access to `/-/` by path at
the ingress.

| Endpoint     | For                 | Response                                                                                                     | Content-Type                                                 | Format                          |
|--------------|---------------------|--------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------|---------------------------------|
| `/-/live`    | Restart checks      | 200 `pass`, or 503 `fail` if the process is broken. `checks` lists the liveness checks.                      | `application/health+json`                                    | [IETF health check draft][ietf] |
| `/-/ready`   | Routing checks      | 503 `fail` while starting, draining or not the leader, else 200 `pass`. `checks` lists the lifecycle checks. | `application/health+json`                                    | [IETF health check draft][ietf] |
| `/-/status`  | Humans and alerting | Always 200. `checks` lists everything: liveness, lifecycle, pressure, dependencies.                          | `application/health+json`                                    | [IETF health check draft][ietf] |
| `/-/info`    | Humans and tooling  | The process's OpenTelemetry Resource, dotted keys nested.                                                    | `application/json`                                           | [OTel resource semconv][otel]   |
| `/-/metrics` | Scrapers            | Current metric values.                                                                                       | `application/openmetrics-text; version=1.0.0; charset=utf-8` | [OpenMetrics][openmetrics]      |

Wire the platform's checks up like this:

| Check                         | Endpoint                                 |
|-------------------------------|------------------------------------------|
| Docker `HEALTHCHECK`          | `/-/live`                                |
| ECS container health check    | `/-/live`                                |
| ALB target group health check | `/-/live` on ECS, `/-/ready` elsewhere   |
| K8S liveness probe            | `/-/live`                                |
| K8S readiness probe           | `/-/ready`                               |
| K8S startup probe             | `/-/ready`                               |

What fails what:

| State                                                            | `/-/live` | `/-/ready` | `/-/status`         |
|------------------------------------------------------------------|-----------|------------|---------------------|
| **Broken**: deadlock, leaked memory, wedged event loop           | fail      | fail       | fail                |
| **Lifecycle**: starting up, draining on shutdown, not the leader | pass      | fail       | pass, noted         |
| **Under pressure**: high CPU, GC storms, saturated pools         | pass      | pass       | warn                |
| **Dependency down**: DB, message broker, upstream API            | pass      | pass       | warn, check details |

Dependency failures are handled in the application, by returning 503 with `Retry-After` on the routes that need the
dependency, not by the infrastructure taking the instance out.

503 is the failure code because every caller agrees on it: the kubelet fails on anything outside 200-399, the ALB
matcher defaults to 200, and `curl -f` exits non-zero on 400 and above. In practice a broken process more often times
out than answers 503, so probe timeouts matter as much as the response.

`/-/info` looks like:

```json
{
  "service": {
    "name": "orders",
    "version": "2.14.0",
    "instance": { "id": "orders-7c9d8f-x2kq" }
  },
  "deployment": { "environment": { "name": "prod" } },
  "vcs": { "ref": { "head": { "revision": "a3f9c1e" } } },
  "process": { "runtime": { "name": "OpenJDK Runtime Environment", "version": "21.0.4" } }
}
```

## Why

### The health checks that will call you

| Check                         | Who runs it              | Where from                    | Question it answers                  | On failure                                         |
|-------------------------------|--------------------------|-------------------------------|--------------------------------------|----------------------------------------------------|
| Docker `HEALTHCHECK`          | Docker daemon            | Inside the container (`exec`) | Is this process working?             | Status flag set to `unhealthy`. Nothing else.      |
| ECS container health check    | ECS agent (same syntax)  | Inside the container (`exec`) | Is this container working?           | Task stopped and replaced.                         |
| ALB target group health check | Load balancer nodes      | Over the network              | Should I route traffic here?         | Target taken out of rotation. On ECS, task killed. |
| K8S liveness probe            | kubelet                  | From the node                 | Is this process stuck?               | Container restarted.                               |
| K8S readiness probe           | kubelet                  | From the node                 | Should this pod receive traffic?     | Pod removed from Service endpoints. Not restarted. |
| K8S startup probe             | kubelet                  | From the node                 | Has this container finished booting? | Liveness suppressed until it passes.               |

Two mechanisms are at work: _restart_ checks (Docker, ECS, liveness) and _routing_ checks (ALB, readiness). Only K8S
keeps them cleanly separate.

Some wrinkles:

- Docker's `HEALTHCHECK` on its own restarts nothing. It flips a flag that something else - Swarm, Compose
  `depends_on: condition: service_healthy`, an `autoheal` sidecar, ECS - has to act on.
- ALB checks are routing checks, but ECS treats an ALB-unhealthy target as a failed task and replaces it. So on ECS
  a routing check becomes a restart check, which is why the wiring table above sends the ALB to `/-/live` on ECS.
- Docker and ECS run the check _inside_ the container, so the image needs `curl` or equivalent. ALB and the kubelet
  probe over the network, so they also prove the port is bound and reachable.
- K8S's startup probe has rough equivalents in ECS's `startPeriod` on the container health check and
  `healthCheckGracePeriodSeconds` on the service for ALB checks.

The consequence: a check that fails when a downstream dependency is down is appropriate as a routing check and
harmful as a restart check, since restarting will not fix the dependency. On ECS, where routing checks trigger
restarts, a dependency outage cascades into every task being cycled.

### What can actually go wrong

Four kinds of unhealthy, and they want different responses.

**Broken** - deadlock, leaked memory, wedged event loop. Only a restart will fix it. Fail everything.

**Lifecycle** - starting up, draining on shutdown, not the leader. Instance-specific and will resolve itself. Fail
routing, pass restart.

**Under pressure** looks like a routing failure - take the hot instance out until it cools. But if load is even, every
instance is hot. Failing readiness across the fleet leaves the Service with no endpoints, and each instance that drops
out sends more load to the survivors. Readiness is a tool for one hot instance; autoscaling is the tool for a hot fleet.
On ECS the question is moot: the ALB check is the only routing check and ECS turns it into a restart check, so pressure
must pass everything.

**Dependency down** is worse. It is fleet-wide by nature, so failing readiness everywhere means callers get connection
refused instead of a meaningful 503, new pods never go ready so unrelated rollouts stall, and when the dependency
returns the fleet is not already up and waiting. Instead: return 503 with `Retry-After` on the routes that need the
dependency, keep serving the ones that do not, and report dependency status on `/-/status` for humans and alerting.
Nothing an orchestrator acts on should include dependency checks. Keeping `/-/status` separate is what stops someone
wiring a DB check into the liveness probe later because it was already there.

The exception is a per-instance dependency - a sidecar, a local cache, a node that cannot reach the DB while its peers
can. That is a genuine readiness case, but from inside the process it is indistinguishable from the dependency being
down for everyone. Only monitoring, which sees the whole fleet, can tell the two apart. So leave it out of readiness
and alert on it instead.

Which means that for a stateless service, readiness is mostly about **lifecycle**: the start and end of an instance's
life, plus a handful of stateful special cases (leader election, rebalancing, deliberate withdrawal for debugging).

### One port

A separate management port was for putting operability traffic on a different network interface, which meant something
on a rack server and means nothing in a pod or an `awsvpc` task, where every port shares one network namespace. Worse,
a separate connector usually has its own acceptor and thread pool, so it can answer "alive" while the listener that
actually takes traffic is deadlocked. Restrict access by path at the ingress instead.

### The prefix

Group the endpoints under a prefix, so a single ingress rule covers them and they cannot collide with application
routes. Spring uses `/actuator`, a control-theory word for the part that acts on a system, which nobody outside Spring
recognises. Quarkus uses `/q`. Prometheus, Alertmanager, Thanos, Loki and GitLab use `/-/`, which is the one with
prior art outside a single framework.

### Body formats

There is no ratified standard for a health check body. The nearest is the [IETF draft][ietf] "Health Check Response
Format for HTTP APIs", which reached version 06 in 2021 and expired. It defines `application/health+json` with
`status` of `pass`, `warn` or `fail`, and a `checks` map of named sub-checks each with their own `status`,
`observedValue`, `observedUnit`, `time` and `output`. The media type was never registered with IANA, but libraries in
most languages implement the draft and it is the format people reach for. The alternative is Eclipse MicroProfile
Health, an actual spec, but it is `application/json` with `UP`/`DOWN` and no `warn`, and `warn` is exactly what
`/-/status` needs for pressure and dependency states.

All three endpoints return the same shape: a `status` and the `checks` that produced it. They differ only in which
checks are included. `/-/live` folds the liveness checks, `/-/ready` the lifecycle checks, `/-/status` everything.
Including `checks` in the probe responses is not just for humans: the kubelet records the response body of a failed
`httpGet` probe in the pod's events, so `kubectl describe pod` shows which check failed rather than just "503".

For metrics, [OpenMetrics][openmetrics] is the Prometheus exposition format formalised. Scrapers content-negotiate;
an old one will ask for `text/plain; version=0.0.4` and should get it.

### Info format

There is no standard for what an info endpoint returns. Spring's is freeform, populated by whatever contributors are on
the classpath. But there is a standard vocabulary for describing a running process: the OpenTelemetry Resource
[semantic conventions][otel]. `service.name`, `service.version`, `service.instance.id`,
`deployment.environment.name`, `process.runtime.name`, `container.image.tags`, `k8s.pod.name`, `cloud.region`,
`vcs.ref.head.revision`. Every span and metric the process emits already carries these, so `/-/info` has a precise
definition: the Resource this process attaches to its telemetry. What it returns must match what you see in your
tracing UI, which is a useful thing to be able to check.

Serialise the SDK's `Resource` with the dotted keys nested, which is how Datadog's span overview displays them.
Nesting is safe because the conventions forbid a namespace also being a key. Two attributes to filter out:
`process.command_line` and `process.executable.path` are populated by the standard detectors and can leak secrets.

[ietf]: https://datatracker.ietf.org/doc/html/draft-inadarei-api-health-check-06
[otel]: https://opentelemetry.io/docs/specs/semconv/resource/
[openmetrics]: https://github.com/prometheus/OpenMetrics/blob/main/specification/OpenMetrics.md
