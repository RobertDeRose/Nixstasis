# Client Identity

Works out who the device is, and keeps its registration secrets and runtime credentials safe on disk.

## Owns

- `packages/client/internal/identity/`: identity detection (`detect.go` and `interface.go`), the credential store
  (`store.go`), and enrollment state (`enrollment.go`).
- The runtime identity file at `config.IdentityPath()` and the temporary registration state at
  `config.RegistrationPath()`, both owner-only.

## Entry points

- `ResolveMAC` settles which MAC identifies the device. It uses `ResolveInterface` and `DetectServerInterface` to pick
  the network interface, and `GetPrimaryMAC` to read that interface's MAC.
- `GetPrimaryIP` and `GenerateDeviceName` fill in the rest of the device's details.
- `NewToken` generates the registration proof and the proposed runtime token.
- `Store` loads and saves credentials: `LoadEnrollment` and `SaveEnrollment` for registration state, `Load` and `Save`
  for the UUID and runtime token, and `Remove` to clear state.

## Boundaries

- **Which interface identifies the device:** set `identity.interface` (`NIXSTASIS_IDENTITY_INTERFACE`) to name it. If
  that interface is missing or has no MAC, the client stops with an error; it never falls back to another one. Left
  empty, the client picks the interface that traffic to the server leaves through: it resolves the `api.url` host, or
  the HTTPS proxy when one applies, and opens a UDP socket towards it. That only consults the routing table and sends
  no packets, and it works the same whether the server is on the internet or an intranet.
- **When detection can't finish yet:** until DNS resolves and a route exists, detection retries, starting after one
  second and doubling up to a minute between tries. A server on loopback fails straight away, because no physical
  interface identifies it. An interface without a MAC, such as a VPN tunnel carrying the route to the server, can never
  identify the device; set `identity.interface` on those devices.
- **The MAC stays fixed:** `register` saves the MAC with the registration secrets before its first request, and with the
  runtime credentials after approval. Retries, restarts, and heartbeats reuse it, so the device keeps the MAC the server
  knows even if its routes change. A configured interface is always read directly, and overrides the saved MAC.
  `poll` saves the MAC on an identity that was stored without one.
- **Registration secrets:** before the first registration the client generates a random proof and a distinct proposed
  runtime token and stores them atomically. After approval the server exchanges the proof for that token; the client
  then saves the UUID and token together and removes the registration state.
- **Recovery:** after a lost response or a restart the client reuses the saved secrets, so if the exchange already went
  through it gets the same token back. Registration state wins over the identity file. If the registration state is
  damaged, registration stops rather than generating a new proof. If saving the identity fails, the registration state keeps
  the new credentials for the next attempt.
- **File format:** identity files are JSON, holding the UUID and the runtime token that approved devices need for
  heartbeats, results, and payloads.
- This package uses only the Go standard library; [Client Transport](client-transport.md) and the `register` and `poll`
  commands depend on it.
