# CloudAMQP

Modules on the `cloudamqp/cloudamqp` provider.

## Modules

| Module | What it manages | Submodules |
|---|---|---|
| [`cloudamqp-res-vpc`](../../src/modules/cloudamqp-res-vpc/) | A VPC that dedicated instances join | — |
| [`cloudamqp-res-instance`](../../src/modules/cloudamqp-res-instance/) | A broker instance, with its private link and firewall | — |

## Keep the VPC in its own module

An instance can bring its own VPC through `vpc_subnet`, but that VPC lives and dies with the instance.
`cloudamqp-res-vpc` plus the instance's `vpc_id` keeps the network separate: several instances can
share it, and replacing an instance leaves the network in place. A private link is built on the
instance, not the VPC, but the instance must be in a VPC to have one.

## The private link is only the service end

`private_link` creates the CloudAMQP side and publishes `private_link.service_name`. The consumer's
endpoint lives in the consumer's own cloud and configuration. On Azure, that is a private endpoint with
a **manual** connection that targets `service_name` as an alias, since the Private Link Service sits in
CloudAMQP's subscription. [`azure-res-network-privateendpoint`](azure.md#manual-connection-approval) takes it as
`private_connection_resource_alias` with `is_manual_connection = true`.

## The firewall replaces the whole rule set

`cloudamqp_security_firewall` owns every rule on the instance. Pass the complete set: a rule left out of
`firewall.rules` is removed, not left alone. Rules are keyed by name, and the key doubles as the rule's
description unless one is given.

Leaving `firewall` null manages no firewall at all, and the instance keeps whatever rules CloudAMQP gave
it. That is not the same as a closed firewall.

## Custom domains are not part of the instance

`cloudamqp_custom_domain` only succeeds once its hostname already resolves to the instance, and the DNS
record that makes it resolve needs the instance's `host`. Inside one module that is fine. When DNS is
owned by a different configuration, the order is instance, then DNS record, then custom domain, so the
custom domain cannot sit inside the instance module.

## Tags are strings

CloudAMQP tags are a `list(string)`, not a key/value map, so the `map(string)` tags an Azure
configuration carries cannot be passed through. Both modules default `tags` to `[]`.
