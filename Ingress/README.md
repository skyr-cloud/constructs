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
