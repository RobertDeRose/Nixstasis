
# Nixstasis overview

- Project kind: `application`

## Purpose

Monitor managed IoT devices and provide operators with secure, on-demand remote access and state visibility.

## Intended users

Operators and administrators managing Atomix IoT device fleets, plus the managed-device agents that communicate with the control plane.

## Current scope

A Go device agent for registration, telemetry, commands, scripts, and FRP lifecycle; an Elixir/Phoenix control plane with APIs, LiveView monitoring, approvals, alerts, reporting, and E2E validation; and a Docker Compose deployment using Caddy, FRPS, and PostgreSQL.

Future behavior belongs in [Planned features](../planned-features.md) until delivered.

## Boundaries

Docker Compose under deploy/compose is the supported server deployment path; GoReleaser is the supported client release path; Caddy/AuthCrunch owns public browser ingress authentication; Phoenix owns device and application authorization; abandoned server package deployment assets are excluded.
