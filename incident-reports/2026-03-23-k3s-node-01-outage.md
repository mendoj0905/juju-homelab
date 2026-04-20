# Incident Report: k3s-node-01 Outage

**Date:** 2026-03-23
**Resolved:** 2026-03-26
**Duration:** ~3 days (11:44 Mar 23 – ~22:30 Mar 26)
**Severity:** Medium — workloads disrupted, cluster remained operational

---

## Summary

`k3s-node-01` (192.168.68.84) went offline unexpectedly on March 23 at approximately 11:44 and remained unreachable until March 26. The node rejoined the cluster on its own. No data loss was observed.

---

## Timeline

| Time (local) | Event |
| --- | --- |
| 2026-03-23 11:44 | Last log entry on k3s-node-01 — logs cut off with no shutdown/panic message |
| 2026-03-23 11:46 | Kubelet stops posting node status; control plane marks node `NotReady` |
| 2026-03-26 ~22:30 | Node comes back online, rejoins cluster as `Ready` |
| 2026-03-26 ~22:35 | Stuck `Terminating` pods force-deleted; workloads rescheduled to healthy nodes |

---

## Impact

The following pods were stuck in `Terminating` on the dead node and had to be force-deleted to reschedule:

| Namespace | Pod | Notes |
| --- | --- | --- |
| `cert-manager` | `cert-manager-webhook` | Rescheduled successfully |
| `monitoring` | `prometheus-monitoring-kube-prometheus-prometheus-0` | Rescheduled successfully |
| `n8n` | `n8n` | Rescheduled successfully |
| `nfs-provisioner` | `nfs-client-provisioner` | Rescheduled successfully |
| `nginx-test` | `nginx-test` | Rescheduled successfully |

Traefik, CoreDNS, and MetalLB were unaffected (running on other nodes).

---

## Root Cause

**Probable cause: sudden power loss or hardware failure.**

Log analysis showed no kernel panic, OOM kill, or graceful shutdown message — the journal simply stops at 11:44. The node came back online on its own after ~3 days, consistent with a power interruption rather than permanent hardware failure.

Pre-existing noise in logs (not causal):

- `Nameserver limits exceeded` — harmless k3s DNS warning; the node has 3 nameservers configured (`8.8.8.8`, `8.8.4.4`, `192.168.1.1`) which is the k3s limit. These errors appeared throughout the uptime period.

---

## Resolution

1. Node self-recovered and rejoined the cluster.
2. Force-deleted the 5 stuck `Terminating` pods:

   ```bash
   kubectl delete pod <pod> -n <namespace> --force --grace-period=0
   ```

3. All workloads rescheduled and confirmed `Running`.

---

## Follow-up Actions

- [ ] Check the Pi's power supply — RPi 4 is sensitive to undersized or shared PSUs
- [ ] Move the Pi to a UPS if not already protected
- [ ] Investigate why the node was unreachable for 3 days before self-recovering (power strip, breaker trip, etc.)
- [ ] Consider reducing the nameserver list to 2 entries to eliminate the DNS warning noise