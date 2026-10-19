# Operations

How to deploy, run, and recover a Nixstasis server and its managed devices. Everything here applies to the supported
Docker Compose deployment.

## Set up

- [Deployment](deployment.md): the services, starting a production stack, hostnames, and exposure.
- [Client Installation](client-installation.md): installing the agent on a device and pointing it at the server.

Every environment variable is in [Deployment Configuration](../reference/deployment-configuration.md).

## Run

- [Health Checks](health-checks.md): commands that confirm the stack is healthy; run them after every change.
- [Device Groups](device-groups.md): organizing devices and filtering the fleet.
- [Command Policies](command-policies.md): controlling which commands device scripts may run.
- [Stary Script Workbench](script-workbench.md): authoring, testing, and deploying scripts.

## Maintain and recover

- [Backup And Restore](backup-restore.md)
- [Secret Rotation](secret-rotation.md)
- [Upgrades And Rollbacks](upgrades-rollbacks.md)
- [Incident Response](incidents.md)
- [HA And Scaling](ha-scaling.md)
