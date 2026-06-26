# 0003 -- VM sizing, burstability, and lifecycle

Status: **Accepted**

## Context

The VM should run a console dev workload within a target budget of about
**$150/month** while staying responsive. Azure offers burstable (B-series) SKUs
that bank CPU credits while idle, and dedicated (D-series) SKUs that do not.
Burstable VMs **reset their banked credits on deallocate**. Auto-shutdown saves
money but costs availability and (for burstable) discards credits. These factors
interact, so sizing, burstability, and the start/stop lifecycle are one decision.

## Decision

- **Default (lean) profile: `Standard_B2as_v2`, burstable, always-on**, with a
  64 GB StandardSSD OS disk. Running continuously banks credits toward a full burst
  balance and still fits the budget (~$87/mo all-in 24/7). **No auto-shutdown** on
  this profile.
- **Heavy profile: a dedicated D-series (`Standard_D4as_v5`) with auto-shutdown.**
  Dedicated SKUs have no credits to lose on stop, so auto-shutdown is free of a
  burst penalty -- and is *required* here, because a 4-core dedicated VM run 24/7
  would break the $150 budget.
- **Rule of thumb:** *burstable -> always-on; dedicated -> auto-shutdown.*
- Because the lean default is always-on, the VM does **not** carry a managed-identity
  role to self-deallocate; that machinery is dropped.

## Consequences

- The everyday machine is cheap, responsive, and always reachable (just request
  access); tmux sessions persist because nothing stops the VM (see ADR 0006).
- Switching to the heavy profile for sustained high-CPU work (long compiles,
  indexing that would exhaust burst credits and throttle to baseline) brings
  auto-shutdown along automatically, keeping that profile within budget.
- "Disconnecting" never saves money on the lean profile -- only deallocating or
  deleting the VM does. This is called out prominently in client docs to avoid the
  expectation that closing SSH stops billing.
