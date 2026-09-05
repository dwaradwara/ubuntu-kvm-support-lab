# INC001 — Nginx Service Failure in KVM Guest

## Incident Summary

| Field | Details |
|---|---|
| Incident ID | INC001 |
| Date | 2026-09-03 |
| Status | Resolved |
| Environment | Ubuntu 24.04.4 LTS KVM guest |
| Guest Hostname | lab-guest-01 |
| Guest IP | 192.168.122.170 |
| Service | Nginx 1.24.0 |
| Hypervisor | KVM/QEMU with libvirt |

## Scenario

This incident was deliberately created in an Ubuntu KVM support lab to simulate a customer-facing service outage caused by an invalid Nginx configuration.

The objective was to diagnose the failure using standard Ubuntu service-management and logging tools, identify the precise root cause, restore service safely, and verify recovery.

## Healthy Baseline

Before introducing the failure, Nginx was confirmed healthy.

Command:

    systemctl status nginx --no-pager

Observed state:

    Active: active (running)

HTTP validation:

    curl -I http://localhost

Observed result:

    HTTP/1.1 200 OK
    Server: nginx/1.24.0 (Ubuntu)

The service was therefore confirmed operational before fault injection.

## Fault Injection

A backup of the known-good configuration was created:

    sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

A deliberate syntax error was introduced by appending an extra closing brace:

    echo '}' | sudo tee -a /etc/nginx/nginx.conf

Configuration validation was then performed:

    sudo nginx -t

Observed result:

    unexpected "}" in /etc/nginx/nginx.conf:84
    nginx: configuration file /etc/nginx/nginx.conf test failed

A service restart was attempted:

    sudo systemctl restart nginx

Result:

    Job for nginx.service failed because the control process exited with error code.
## Investigation

### 1. Check systemd service state

Command:

    systemctl status nginx --no-pager

Observed result:

    Active: failed (Result: exit-code)

The failed pre-start process was:

    ExecStartPre=/usr/sbin/nginx -t
    code=exited, status=1/FAILURE

This showed that Nginx was failing before the service process could start.

### 2. Inspect Nginx service logs

Command:

    sudo journalctl -u nginx --since "10 minutes ago" --no-pager

Relevant events:

    Stopping nginx.service
    nginx.service: Deactivated successfully.
    Starting nginx.service
    unexpected "}" in /etc/nginx/nginx.conf:84
    nginx: configuration file /etc/nginx/nginx.conf test failed
    nginx.service: Control process exited, code=exited, status=1/FAILURE
    nginx.service: Failed with result 'exit-code'
    Failed to start nginx.service

The journal confirmed that systemd attempted to start Nginx, but the configuration validation failed.

### 3. Validate configuration directly

Command:

    sudo nginx -t

Observed result:

    unexpected "}" in /etc/nginx/nginx.conf:84
    nginx: configuration file /etc/nginx/nginx.conf test failed

This identified the exact configuration file and line responsible for the failure.

## Root Cause

The root cause was an extra closing brace (`}`) added to:

    /etc/nginx/nginx.conf

at line 84.

Nginx performs a configuration validation step before startup.

The invalid syntax caused:

    nginx -t

to return exit status 1.

Because the `ExecStartPre` validation failed, systemd refused to start the Nginx service.

The failure was therefore caused by a configuration syntax error, not by a network issue, package failure, port conflict, or resource exhaustion.## Recovery

The known-good Nginx configuration was restored from the backup:

    sudo cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf

Before starting the service, the restored configuration was validated:

    sudo nginx -t

Observed result:

    nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
    nginx: configuration file /etc/nginx/nginx.conf test is successful

Nginx was then started:

    sudo systemctl start nginx

## Verification

The service state was checked:

    systemctl status nginx --no-pager

Observed result:

    Active: active (running)

The recovered service was also tested at the HTTP layer:

    curl -I http://localhost

Observed result:

    HTTP/1.1 200 OK
    Server: nginx/1.24.0 (Ubuntu)

The service was therefore confirmed operational after recovery.

## Prevention

The following controls would reduce the chance of this failure occurring in a production environment:

1. Validate Nginx configuration before every reload or restart:

       sudo nginx -t

2. Keep Nginx configuration files under version control.

3. Maintain a known-good backup before making production configuration changes.

4. Prefer configuration validation followed by reload:

       sudo nginx -t && sudo systemctl reload nginx

5. Monitor systemd service failures and Nginx logs after configuration changes.

6. Use change-review procedures for production configuration modifications.

## Troubleshooting Sequence

The investigation followed this sequence:

    Service outage
        |
        v
    systemctl status nginx
        |
        v
    ExecStartPre failure identified
        |
        v
    journalctl -u nginx
        |
        v
    nginx -t
        |
        v
    Syntax error located at nginx.conf line 84
        |
        v
    Restore known-good configuration
        |
        v
    Validate configuration
        |
        v
    Start Nginx
        |
        v
    Verify active state and HTTP 200

## Support Engineer Takeaway

The key diagnostic observation was that Nginx was not crashing after startup.

The service was failing before startup during the systemd `ExecStartPre` configuration-validation stage.

That distinction narrowed the investigation immediately toward configuration validation instead of runtime causes such as port conflicts, application crashes, networking problems, or resource exhaustion.

`systemctl status` identified the failed startup stage.

`journalctl` provided the chronological service-event history.

`nginx -t` identified the exact syntax error and line number.

The recovery was performed only after validating the restored configuration, and service health was confirmed both at the systemd layer and at the HTTP layer.
