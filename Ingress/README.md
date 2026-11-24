# `Constructs/Ingress`

This is a FOSS constructs library containing useful things for accepting real internet traffic.

## `LoadBalancer`

`LoadBalancer.Proxy` runs replicas of [HAProxy](https://www.haproxy.org) and
hands back a `Rule` constructor. Each rule names a frontend, the requests it
matches and the backends that serve them; the proxy collects every rule
declared against it — from any repository of its organization — into its
configuration.

```scl
import Constructs/Ingress/LoadBalancer

export let ingress = LoadBalancer.Proxy({
	name: "edge",
	replicas: 2,
	replica: { cpu: 500, memory: 268435456, ipv4: true },
	frontends: #{
		.http: { port: 80, mode: .http },
		.https: { port: 443, mode: .http, tls: .terminate },
	},
})
```

### What it declares

- One [`Skyr/Net`](https://skyr.foo/~docs/scl/reference/Skyr/Net.md) network,
  named after the ingress and handed back as `ingress.network`. It is
  dual-stack: `networkCidr` and `networkCidr6` choose its ranges.
- Per replica, a `Net.Gateway` and a
  [`Skyr/Container`](https://skyr.foo/~docs/scl/reference/Skyr/Container.md)
  Pod routed through it. The gateway is the replica's public face — a gateway
  forwards a given port to one target, so each replica has one of its own — and
  its addresses outlive the proxy behind it, which is replaced whenever its
  configuration changes.
- Per public frontend, a `Gateway.Port` for each address family the replica is
  published on: IPv6 always, IPv4 as well with `replica.ipv4`.

### Ports

A frontend's `port` is the one clients connect to. Inside a replica the proxy
runs unprivileged and cannot bind a port below 1024, so such a frontend listens
30000 above its port and the gateway forwards the public port there. Nothing
outside the replica can tell.

A frontend with `public: false` is published on no gateway. It answers on the
replicas' own addresses on the ingress network, on its `port` as written — which
therefore has to be 1024 or above.

### Redirect HTTP to HTTPS

To redirect all requests from port 80 to HTTPS, set `redirectTo` on the
cleartext HTTP frontend. Its value is the key of a TLS-terminating HTTP
frontend in the same proxy:

```scl
frontends: #{
	.http: { port: 80, mode: .http, redirectTo: .https },
	.https: { port: 443, mode: .http, tls: .terminate },
},
```

`http://example.com/shows?month=may` now receives a `301 Moved Permanently` to
`https://example.com/shows?month=may`. The hostname, path and query come from
the request. A non-default destination port is included (`:8443`, for example).
There is no hostname or path filter: put the rules and their certificates on
`.https`, not on the redirecting frontend. Without `redirectTo`, routing is
unchanged.

### Backends

A replica reaches a backend over the ingress network, so a backend needs a NIC
on it. Name the backend by an address on that network, or by a name published on
it, which the replicas re-resolve as it moves:

```scl
import Skyr/Container
import Std/Option

let api = Container.Pod({
	name: "api",
	scratch: 1073741824,
	nics: #{ "edge": { network: ingress.network } },
	containers: #{ "api": { image: apiImage.url, cpu: 500, memory: 268435456 } },
})

let apiName = ingress.network.dns.A({
	name: "api",
	addresses: [Option.unwrap(api.nics["edge"]?.ipv4)],
})

ingress.Rule({
	frontend: .http,
	matchers: [.host("api.example.com")],
	backends: [{ address: apiName.fqdn, port: 8080 }],
})
```

A name is one server, however many addresses it answers with: the proxy picks
one of them and the rest get no traffic. To serve everything behind a name —
the replicas of a `Rollout.ReplicaSet`, say — tell the backend how many
`servers` the name stands for. Each then gets a server of its own, health
checked on its own and balanced with the others, and follows the name as its
addresses change:

```scl
let web = ingress.network.dns.A({
	name: "web",
	addresses: [for (replica in set.replicas) replica.host],
})

ingress.Rule({
	frontend: .http,
	matchers: [.host("example.com")],
	backends: [{ address: web.fqdn, port: 8080, servers: 3 }],
})
```

A workload cannot be on two networks whose ranges overlap, so give the ingress
network ranges clear of the other networks its backends are on. Attaching to the
network and publishing names on it from another repository are the network
owner's to grant: `resource:AttachPodToNetwork` (or `AttachMachineToNetwork`)
and `resource:AttachDnsRecordToNetwork` on the network.

### Addresses

`ingress.addresses` lists each replica's public addresses, ready for the records
of a zone:

```scl
import Skyr/DNS

let zone = DNS.Zone({ domain: "example.com" })

zone.AAAARecord({ name: "@", addresses: [for (a in ingress.addresses) a.ipv6] })
zone.ARecord({
	name: "@",
	addresses: [for (a in ingress.addresses) if (a.ipv4 != nil) a.ipv4],
})
```

### Forwarded headers

A frontend in `mode: .http` tells its backends how the client reached it, with
three headers set on every request:

| Header | Value |
| --- | --- |
| `X-Forwarded-Proto` | `https` on a frontend that terminates TLS, `http` on one that does not |
| `X-Forwarded-Host` | the `Host` the client asked for, port included if it sent one |
| `X-Forwarded-For` | the client's address |

The proxy is the edge, so it sets these rather than appends to them: whatever a
client sends under these names is discarded, and a backend can trust what it
reads. `Host` itself reaches the backend as the client sent it. A `tcp`
frontend, terminating TLS or not, has no headers to set and adds none.
