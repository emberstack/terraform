# FortiGate

39 modules on `fortinetdev/fortios`, plus one nested submodule. The largest family
in the repository, and the one with the most provider-specific behaviour to know about.

Module names carry an extra platform segment — `fortios-<kind>-fortigate-<service>-<resource>` — with
one exception: `fortios-utl-network-cidr` is pure arithmetic and touches no device.

## Perpetual diffs are the dominant failure mode

The `fortios` provider returns values for attributes you never set. Left alone, this produces a plan
that never converges: apply, plan, and the same diff is still there.

Three mitigations are used, and **each one is explained in a banner where it appears**. A bare
`ignore_changes` list is unreadable six months later — if you add one, say why.

**1. Deliberately omitted defaults.** Where the provider computes a value, the module leaves the
attribute unset rather than sending a default that would fight the device. Several modules had a
`default` removed for exactly this reason; don't add one back to "complete" the interface.

**2. `lifecycle { ignore_changes }`.** Eight modules in this family use it:

`fortios-ptn-fortigate-system-interface`, `fortios-ptn-fortigate-system-ntp-interface`,
`fortios-ptn-fortigate-system-settings`, `fortios-ptn-fortigate-wirelesscontroller-vap-nac`,
`fortios-res-fortigate-switchcontroller-managedswitch`, `fortios-res-fortigate-systemdhcp-server`,
`fortios-res-fortigate-wirelesscontroller-wtp`, `fortios-res-fortigate-wirelesscontroller-wtpprofile`.

**3. `dynamic_sort_subtable`.** The provider returns sub-tables in device order rather than configured
order; setting this makes the comparison order-insensitive. Used in exactly one module today,
`fortios-res-fortigate-system-dnsdatabase`, where the record sub-table is affected.

### The cost

`ignore_changes` is not free: an attribute inside it is no longer managed, so out-of-band changes on
the device go undetected. That trade is deliberate and per-attribute — read the banner before assuming
an attribute in the list is a bug rather than a decision.

## Out-of-band modules

Four modules go around the `fortios` provider because it cannot express what they need — one through
a second provider, three by shelling out to `pwsh` from a `local-exec` provisioner. All four have
runtime requirements that are **not** Terraform inputs, and of the three that shell out, only
`fortios-ptn-fortigate-system-ntp-interface` lets the caller turn certificate verification back on.

### `fortios-ptn-fortigate-switchcontroller-managedswitch-ports`

Per-port switch configuration, which the `fortios` provider does not cover. Drives the FortiOS CMDB
REST API through `magodo/restful`.

The parent fans a `ports` map out to one child module instance per port; the child owns the single
`restful_resource` so the REST wiring lives in one place. Ports are keyed by name, so there is no
positional churn when one is added or removed.

**The caller configures the `restful` provider** — base URL and bearer token — the same way it
configures `fortios`. The module declares the requirement and nothing else.

This is also the one layout exception in the repository: the child sits at `port/` rather than
`modules/port/`.

### `fortios-ptn-fortigate-system-ntp-interface`

Adds a single NTP listener interface. The provider exposes `system/ntp` as a whole-object resource,
so there is no way to add one listener without owning the entire NTP configuration — this module
drives the CMDB REST endpoint through `local-exec` instead.

It tracks ownership: the current state is read first, and a flag records whether *this* module created
the listener. A pre-existing listener is left alone on destroy — the module only removes what it
added.

> **Runtime contract**, read from the environment at apply time, mirroring how the `fortios` provider
> itself is configured:
>
> - `pwsh` (PowerShell 7+) on `PATH`. Windows PowerShell 5.1 will not do — it has neither
>   `-SkipCertificateCheck` nor the splatting form used here.
> - `FORTIOS_ACCESS_HOSTNAME` — FortiGate host, no scheme.
> - `FORTIOS_ACCESS_TOKEN` — REST API token.
>
> The `insecure` input defaults to `true` because FortiGates ship with self-signed certificates. At
> that default the API token travels over a connection whose certificate is not verified. Set it to
> `false` once the appliance presents a trusted certificate.

### `fortios-ptn-fortigate-system-interface`

Assembles an interface with its DHCP server, DNS service and firewall address objects through the
provider, and can additionally register that interface as an NTP listener. That last step hits the
same whole-object limitation as the module above and is solved the same way — a `local-exec` REST
call, with the same ownership tracking, so a pre-existing listener survives destroy.

The provisioner is opt-in: `ntp_listener` defaults to `false` and nothing shells out until it is set.
The variable's description presents it as a plain boolean and says nothing about `pwsh`, so on a
runner without PowerShell 7 the first sign of trouble is a mid-apply `pwsh: command not found` —
against live hardware, after the interface and its dependents have already been created.

> **Runtime contract**, only when `ntp_listener = true`:
>
> - `pwsh` (PowerShell 7+) on `PATH`. This is the requirement that actually bites.
> - `FORTIOS_ACCESS_HOSTNAME` and `FORTIOS_ACCESS_TOKEN` — the `fortios` provider's own environment
>   variables, so a caller that configures the provider from the environment already has them.
> - `-SkipCertificateCheck` is hardcoded. There is no `insecure` input, so the API token always
>   travels over a connection whose certificate is not verified.

### `fortios-ptn-fortigate-wirelesscontroller-vap-nac`

Binds a NAC profile onto a VAP. The provider builds the VAP, its VLAN sub-interfaces and the NAC
profile, but the binding cannot live on the VAP resource itself: the profile's onboarding VLAN is
one of the VAP's own sub-interfaces, so a native `nac_profile` reference would close a dependency
cycle. A `terraform_data` provisioner PUTs the two fields over REST instead, and the VAP keeps them
in `ignore_changes` so the two do not fight over ownership.

Here the provisioner is **unconditional**: no `count`, no `for_each`, no flag to skip it. It runs
last, once the VAP, the sub-interfaces and the NAC profile already exist on the device, so a runner
without `pwsh` fails every apply of this module — halfway through, with the wireless objects created
and unbound.

> **Runtime contract**, always:
>
> - `pwsh` (PowerShell 7+) on `PATH`.
> - `FORTIOS_ACCESS_HOSTNAME` and `FORTIOS_ACCESS_TOKEN`, as above.
> - `-SkipCertificateCheck` is hardcoded, with no `insecure` input to disable it.

## Hide FortiConverter prompt

This one is *not* out-of-band — a `cli-script` action is a native CMDB object, so the provider handles
it. It is here because it shares the other four's problem: a runtime requirement that is not an input.

`fortios-ptn-fortigate-hide-forticonverter-prompt` is single-purpose and deliberately not
parameterized. A `cli-script` automation action runs the `diagnose` command; a stitch fires it on the
built-in `Reboot` trigger, which the module references rather than redefines. The diag setting is
non-persistent, so re-running on every reboot is what makes it stick.

A `cli-script` action is used because the REST CMDB API has no generic CLI passthrough — but a
`cli-script` action *is* a CMDB object, making this the supported way to run a `diagnose` command
declaratively and have it drift-tracked.

> **This module needs an operator-level API token for every command, `plan` included.** A reader admin
> profile cannot read `system/automation-*` objects — FortiOS returns 404 rather than a permission
> error, so plan sees phantom drift and proposes recreating resources that already exist.

## `fortios-utl-network-cidr`

Pure CIDR arithmetic — no provider, no resources, no device. Give it an address and netmask, get back
the network in CIDR notation, prefix length, usable host count, first/last usable address, and the
usable and full ranges as `first-last` strings.

Two prefix lengths are special-cased, because neither follows the usual "network and broadcast are
unusable" arithmetic:

- **`/32`** reports `1` usable host, and first, last and range all resolve to the address itself.
- **`/31`** reports `2` usable hosts. A point-to-point link has no network or broadcast address
  (RFC 3021), so both addresses are usable and `ipv4_range` matches `ipv4_usable_range`. Either end
  of the link produces identical output — `10.0.10.5/31` and `10.0.10.4/31` both report
  `10.0.10.4-10.0.10.5`.

The same maths is duplicated in `fortios-res-fortigate-system-interface` and
`fortios-ptn-fortigate-system-interface`, which compute it from a configured or live interface
address respectively. All three are kept in sync.

## Modules

### Firewall

| Module | What it manages |
|---|---|
| [`fortios-res-fortigate-firewall-policy`](../../src/modules/fortios-res-fortigate-firewall-policy/) | Firewall policy rule |
| [`fortios-res-fortigate-firewall-service`](../../src/modules/fortios-res-fortigate-firewall-service/) | Custom firewall service |
| [`fortios-res-fortigate-firewallschedule-recurring`](../../src/modules/fortios-res-fortigate-firewallschedule-recurring/) | Recurring schedule |
| [`fortios-ptn-fortigate-firewall-address-collection`](../../src/modules/fortios-ptn-fortigate-firewall-address-collection/) | Addresses and address groups from one map |
| [`fortios-ptn-fortigate-firewall-customtag-collection`](../../src/modules/fortios-ptn-fortigate-firewall-customtag-collection/) | Custom tags from one map |

### DNS

| Module | What it manages |
|---|---|
| [`fortios-res-fortigate-system-dns`](../../src/modules/fortios-res-fortigate-system-dns/) | System DNS resolver settings |
| [`fortios-res-fortigate-system-dnsdatabase`](../../src/modules/fortios-res-fortigate-system-dnsdatabase/) | Authoritative DNS zone |
| [`fortios-res-fortigate-system-dnsserver`](../../src/modules/fortios-res-fortigate-system-dnsserver/) | DNS service on an interface |
| [`fortios-res-fortigate-dnsfilter-profile`](../../src/modules/fortios-res-fortigate-dnsfilter-profile/) | DNS filter profile |
| [`fortios-res-fortigate-dnsfilter-domain-filter`](../../src/modules/fortios-res-fortigate-dnsfilter-domain-filter/) | Domain filter list |

### Routing and SD-WAN

| Module | What it manages |
|---|---|
| [`fortios-res-fortigate-router-static`](../../src/modules/fortios-res-fortigate-router-static/) | Static route |
| [`fortios-ptn-fortigate-router-static-collection`](../../src/modules/fortios-ptn-fortigate-router-static-collection/) | Static routes from one map |
| [`fortios-res-fortigate-system-sdwan`](../../src/modules/fortios-res-fortigate-system-sdwan/) | SD-WAN zones, members, health checks and rules |

### Switch controller

| Module | What it manages |
|---|---|
| [`fortios-res-fortigate-switchcontroller-managedswitch`](../../src/modules/fortios-res-fortigate-switchcontroller-managedswitch/) | Managed FortiSwitch |
| [`fortios-res-fortigate-switchcontroller-fortilinksettings`](../../src/modules/fortios-res-fortigate-switchcontroller-fortilinksettings/) | FortiLink settings |
| [`fortios-ptn-fortigate-switchcontroller-managedswitch-ports`](../../src/modules/fortios-ptn-fortigate-switchcontroller-managedswitch-ports/) | [Per-port configuration via REST](#fortios-ptn-fortigate-switchcontroller-managedswitch-ports) |

### System

| Module | What it manages |
|---|---|
| [`fortios-res-fortigate-system-interface`](../../src/modules/fortios-res-fortigate-system-interface/) | Network interface |
| [`fortios-res-fortigate-systemdhcp-server`](../../src/modules/fortios-res-fortigate-systemdhcp-server/) | DHCP server on an interface |
| [`fortios-res-fortigate-system-automationstitch`](../../src/modules/fortios-res-fortigate-system-automationstitch/) | Automation stitch |
| [`fortios-res-fortigate-system-external-resource`](../../src/modules/fortios-res-fortigate-system-external-resource/) | External threat/address feed |
| [`fortios-res-fortigate-vpncertificate-remote`](../../src/modules/fortios-res-fortigate-vpncertificate-remote/) | Remote certificate |
| [`fortios-ptn-fortigate-system-interface`](../../src/modules/fortios-ptn-fortigate-system-interface/) | Interface with its DHCP server, DNS service and matching firewall address objects — [optional NTP listener via REST](#fortios-ptn-fortigate-system-interface) |
| [`fortios-ptn-fortigate-system-settings`](../../src/modules/fortios-ptn-fortigate-system-settings/) | Global, NTP and VDOM settings together |
| [`fortios-ptn-fortigate-system-ntp-interface`](../../src/modules/fortios-ptn-fortigate-system-ntp-interface/) | [Single NTP listener interface via REST](#fortios-ptn-fortigate-system-ntp-interface) |
| [`fortios-ptn-fortigate-hide-forticonverter-prompt`](../../src/modules/fortios-ptn-fortigate-hide-forticonverter-prompt/) | [Automation stitch that suppresses the FortiConverter GUI prompt](#hide-forticonverter-prompt) |

### User authentication

| Module | What it manages |
|---|---|
| [`fortios-res-fortigate-user-setting`](../../src/modules/fortios-res-fortigate-user-setting/) | Global user authentication settings |
| [`fortios-res-fortigate-user-saml`](../../src/modules/fortios-res-fortigate-user-saml/) | SAML identity provider |
| [`fortios-res-fortigate-user-nacpolicy`](../../src/modules/fortios-res-fortigate-user-nacpolicy/) | NAC policy |

### Wireless controller

| Module | What it manages |
|---|---|
| [`fortios-res-fortigate-wirelesscontroller-settings`](../../src/modules/fortios-res-fortigate-wirelesscontroller-settings/) | Wireless controller settings |
| [`fortios-res-fortigate-wirelesscontroller-vap`](../../src/modules/fortios-res-fortigate-wirelesscontroller-vap/) | Virtual AP (SSID) |
| [`fortios-res-fortigate-wirelesscontroller-wtp`](../../src/modules/fortios-res-fortigate-wirelesscontroller-wtp/) | Individual access point |
| [`fortios-res-fortigate-wirelesscontroller-wtpprofile`](../../src/modules/fortios-res-fortigate-wirelesscontroller-wtpprofile/) | AP profile |
| [`fortios-res-fortigate-wirelesscontroller-ssidpolicy`](../../src/modules/fortios-res-fortigate-wirelesscontroller-ssidpolicy/) | SSID policy |
| [`fortios-res-fortigate-wirelesscontroller-mpskprofile`](../../src/modules/fortios-res-fortigate-wirelesscontroller-mpskprofile/) | Multi-pre-shared-key profile |
| [`fortios-res-fortigate-wirelesscontroller-nacprofile`](../../src/modules/fortios-res-fortigate-wirelesscontroller-nacprofile/) | Wireless NAC profile |
| [`fortios-res-fortigate-wirelesscontroller-arrpprofile`](../../src/modules/fortios-res-fortigate-wirelesscontroller-arrpprofile/) | Automatic radio resource provisioning profile |
| [`fortios-res-fortigate-wirelesscontroller-widsprofile`](../../src/modules/fortios-res-fortigate-wirelesscontroller-widsprofile/) | Wireless IDS profile |
| [`fortios-ptn-fortigate-wirelesscontroller-vap-nac`](../../src/modules/fortios-ptn-fortigate-wirelesscontroller-vap-nac/) | VAP bound to a NAC profile and its quarantine interface — [NAC binding via REST](#fortios-ptn-fortigate-wirelesscontroller-vap-nac) |

### Utility

| Module | What it does |
|---|---|
| [`fortios-utl-network-cidr`](../../src/modules/fortios-utl-network-cidr/) | [CIDR arithmetic](#fortios-utl-network-cidr) — no provider, no resources |

## Sensitive inputs

Pre-shared keys and secrets are marked `sensitive` in
`fortios-res-fortigate-wirelesscontroller-vap`, `-mpskprofile` and
`fortios-ptn-fortigate-wirelesscontroller-vap-nac`. `-vap` can generate a key with `random_password`,
which puts the generated value in state by design.

## Re-binding NAC on an existing VAP

`fortios-ptn-fortigate-wirelesscontroller-vap-nac` binds the NAC profile onto the VAP with a REST
`PUT` from a `terraform_data` provisioner, because the provider has no field for it that survives
`ignore_changes` on the VAP itself.

`terraform_data` only re-runs its create-time provisioner when it is **replaced**, and only
`triggers_replace` replaces it — changing `input` updates in place. The module sets both from the
same local, so a renamed VAP or a changed profile now re-binds rather than silently leaving the
device on the old one.

**Existing deployments take one replacement.** `triggers_replace` moves from `null` to a value, which
forces a single replace per binding: unbind (`nac=disable`) then rebind. Clients on that VAP see a
NAC re-auth. It does not recur — afterwards the binding is replaced only when it genuinely changes.

To avoid even that, seed the value into state so config already matches and the plan comes back
empty. `triggers_replace` is dynamically typed, so it is not a bare object in state — it needs the
`{value, type}` wrapper, and a plain object is rejected with
*`invalid key "vap_name" in dynamically-typed value`*:

```json
"triggers_replace": {"value": {"nac_profile": "<profile>", "vap_name": "<vap>"},
                     "type": ["object", {"nac_profile": "string", "vap_name": "string"}]}
```

## Who owns NTP listener interfaces

NTP listener interfaces are owned by `fortios-ptn-fortigate-system-ntp-interface`, one instance per
listener. `fortios-ptn-fortigate-system-settings` owns only the scalar NTP settings — `ntpsync`,
`server_mode` and `syncinterval` — and exposes nothing for listeners or servers.

That split is not a workaround, it is the only shape that works. `fortios_system_ntp` is a
whole-object resource, so any listener list set on it is the *complete* list and silently removes
anything absent from it. Keeping `interface` in `ignore_changes` is what lets the sibling add
listeners over REST without this module reverting them on the next apply.
