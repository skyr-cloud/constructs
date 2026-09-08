# `Constructs/Schema`

This is a FOSS constructs library for reading dynamic data — the `Any` values a
JSON, YAML or TOML parser hands back — as statically typed SCL values. A schema
is an ordinary function, so schemas nest to the shape of the document they read,
and a value that does not fit stops the deployment with a message naming the
path into the document, what was expected there, and what was found.

## Reading a document

Given a `services.json` of

```json
{
	"region": "eu-north-1",
	"services": [
		{ "name": "web", "port": 8080, "replicas": 3 },
		{ "name": "api", "port": 9000 }
	]
}
```

a schema for it is written out of one combinator per shape, and the types come
out of the schema rather than being asserted onto it:

```scl
import Constructs/Schema/Decode
import Std/Encoding

type Service { name: Str, port: Int, replicas: Int? }

type Deployment { region: Str, services: [Service] }

let service = Decode.record(fn(field: Decode.Field) {
	name: field("name", Decode.str),
	port: field("port", Decode.int),
	replicas: field("replicas", Decode.optional(Decode.int)),
} as Service)

let deployment = Decode.record(fn(field: Decode.Field) {
	region: field("region", Decode.str),
	services: field("services", Decode.list(service)),
} as Deployment)

let decoded = deployment(Encoding.fromJson(document))
```

`decoded.services` is a `[Service]`, `decoded.services[0].port` is the `Int`
`8080` — JSON has one number type, so the document's `8080` arrives as a float
and is read back as the whole number it is — and the second service's
`replicas` is `nil`, because the document leaves it out.

Writing `"port": "9000"` instead of `"port": 9000` in that second service stops
the decode with the path down to it:

```
at $.services[1].port: expected Int, got "9000"
```
