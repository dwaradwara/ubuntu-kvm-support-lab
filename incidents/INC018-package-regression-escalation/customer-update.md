# INC018 — Customer Update

> Simulated customer-facing communication for the controlled lab incident.

## Impact

We confirmed that the service became unavailable immediately after the package was upgraded from version `1.0` to `1.1`.

The service process exited during startup and the health endpoint on port `18080` became unreachable.

## Confirmed findings

The package history shows the upgrade from `1.0` to `1.1` at **13:47:53 UTC**.

At the same time:

- the service restarted
- the new process exited with status `42`
- systemd marked the service failed
- port `18080` stopped listening
- the health endpoint returned connection refused

The previous version `1.0` had returned HTTP 200 immediately before the change.

## Workaround

We rolled the package back to the known-good `1.0` version and restarted the service.

We also placed a temporary hold on the package to prevent the affected version from being installed again during the investigation.

## Validation

The service is now:

- active and running
- responding successfully on the health endpoint
- running package version `1.0`
- protected by the temporary package hold

Observed health response:

```text
status=ok version=1.0
```

## Current status

**Service restored.**

The rollback is a mitigation. In an equivalent production issue, the package defect would still need to be tracked through the appropriate engineering and release process before the hold could be removed.

## Permanent resolution

No unverified release date should be provided.

In a real Ubuntu case, support would update the customer when a corrected and appropriately verified package is available for the affected Ubuntu series.
