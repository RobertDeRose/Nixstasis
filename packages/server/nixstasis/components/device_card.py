from textwrap import dedent
from uuid import UUID

import reflex as rx

from nixstasis.components.reader_modal import reader_modal
from nixstasis.models import Device
from nixstasis.states.device_state import DeviceState


def status_badge(status: rx.Var[str]) -> rx.Component:
    """Status badge with online/offline indicator."""
    is_online = status == "online"

    return rx.badge(
        rx.flex(
            rx.icon(rx.cond(is_online, "plug", "unplug")),
            rx.text(status.capitalize(), size="2", weight="medium"),
            spacing="1",
            align="center",
        ),
        color_scheme=rx.cond(is_online, "green", "red"),
        size="3",
        style={
            "position": "relative",
            "top": "-1.1em",
            "right": "-1.1em",
        },
    )


def connect_button(device: Device) -> rx.Component:
    ssh_command = dedent(f"""
        proxy=(
            proxycommand ncat
            --proxy-type http
            --proxy device.<domain>:2022 %h %p
        )
        ssh -o "${{proxy[*]}}" checkpoint@{device.remote_connection_string}-ssh
        """).strip()

    return rx.popover.root(
        rx.popover.trigger(
            rx.button("Connect", rx.icon("arrow-right", size=16), variant="solid"),
        ),
        rx.popover.content(
            rx.flex(
                rx.hstack(
                    rx.link(
                        rx.button("Open Cockpit", rx.icon("plane", size=16), variant="surface", color_scheme="indigo"),
                        href=f"https://{device.remote_connection_string}.device.<domain>",
                        is_external=True,
                    ),
                    # rx.spacer(),
                    rx.button("Copy SSH Command", rx.icon("copy", size=16), variant="surface"),
                    on_click=lambda: rx.set_clipboard(ssh_command),
                ),
                rx.heading("SSH ", size="3"),
                rx.text.em("Copy and paste the below command into a terminal", style={"font-size": ".85em"}),
                rx.code_block(code=ssh_command, language="shell-session", style={"font-size": ".75em"}),
                direction="column",
                spacing="3",
                justify="between",
            ),
            size="2",
            align="end",
        ),
    )


def handle_access_button_click(device_id: UUID | None = None):
    return DeviceState.request_remote_access(device_id)


def access_button(device: rx.Var[Device]) -> rx.Component:
    is_offline = device.status != "online"
    disabled = rx.cond((device.remote_access_requested & ~device.remote_connection_string) | is_offline, True, False)
    device_id = rx.cond(~disabled, device.id, None)

    return rx.cond(
        device.remote_connection_string,
        connect_button(device),
        rx.button(
            rx.cond(
                device.remote_access_requested,
                rx.fragment("Pending...", rx.icon("lock-keyhole", size=16)),
                rx.fragment("Request Access", rx.icon("lock-keyhole", size=16)),
            ),
            variant="solid",
            disabled=disabled,
            on_click=lambda: handle_access_button_click(device_id),
        ),
    )


def data_list_item(icon: str, label: str, value: rx.Var) -> rx.Component:
    """Single info row with icon, label, and value."""
    return rx.data_list.item(
        rx.data_list.label(
            rx.flex(
                rx.icon(icon, size=16, color=rx.color("gray", 10)),
                rx.text(label, size="2", color="gray", weight="medium"),
                spacing="1",
            )
        ),
        rx.data_list.value(rx.cond(value, value, "N/A")),
        align="center",
    )


def device_card(device: Device) -> rx.Component:
    """Enhanced device card using Reflex components."""

    return rx.card(
        # Header with title and status
        rx.vstack(
            rx.hstack(
                rx.heading(rx.cond(device.door, device.door, "... awaiting initial update")),
                rx.spacer(),
                status_badge(device.status),
                align="center",
                spacing="1",
                width="100%",
                margin="2",
            ),
            rx.grid(
                rx.data_list.root(
                    data_list_item("building", "Account", device.account),
                    data_list_item("binary", "S/W Version", device.software_version),
                    data_list_item("cpu", "F/W Version", device.firmware_version),
                ),
                rx.data_list.root(
                    data_list_item("store", "Store", device.store),
                    data_list_item("globe", "IP Address", device.ip_address),
                    data_list_item("fingerprint", "MAC Address", device.mac_address),
                ),
                gap="1rem",
                grid_template_columns=[
                    "1fr",
                    "repeat(1, 1fr)",
                    "repeat(2, 1fr)",
                ],
                width="100%",
            ),
            rx.flex(
                rx.flex(
                    rx.icon("clock", size=16, color="var(--gray-10)"),
                    rx.text("Last Seen:", size="2", color="gray", weight="medium"),
                    rx.text(
                        device.last_seen,
                        size="2",
                        weight="medium",
                    ),
                    align="center",
                    spacing="1",
                ),
                rx.flex(
                    rx.cond(device.readers, reader_modal(device)),
                    access_button(device),
                    align="center",
                    spacing="1",
                ),
                justify="between",
                align="center",
                width="100%",
                style={"border_top": "1px solid var(--gray-5)"},
                class_name="pt-4",
            ),
            size="3",
            # box_shadow=styles.box_shadow_style,
            style={
                "padding": "1em",
                # "box_shadow": "var(--shadow-3)",
                "transition": "all 0.2s ease",
                "&:hover": {
                    "box_shadow": "var(--shadow-4)",
                    "transform": "translateY(-2px)",
                    "border": f"10px {rx.color('accent')}",
                },
            },
        )
    )
