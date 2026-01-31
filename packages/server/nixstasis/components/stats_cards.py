import reflex as rx
from reflex.components.radix.themes.base import LiteralAccentColor

from nixstasis import styles
from nixstasis.states.device_state import DeviceState


def stat_card(
    icon: str,
    label: str,
    value: int,
    color: LiteralAccentColor,
) -> rx.Component:
    return rx.card(
        rx.vstack(
            rx.hstack(
                rx.badge(
                    rx.icon(tag=icon, size=34),
                    color_scheme="gray",
                    radius="full",
                    padding="0.7rem",
                    class_name=color,
                ),
                rx.vstack(
                    rx.text(label, size="4", weight="medium"),
                    rx.heading(
                        f"{value:,}",
                        size="6",
                        weight="bold",
                    ),
                    spacing="1",
                    height="100%",
                    align_items="start",
                    width="100%",
                ),
                height="100%",
                spacing="4",
                align="center",
                width="100%",
            ),
        ),
        size="3",
        width="100%",
        box_shadow=styles.box_shadow_style,
    )


def stats_cards() -> rx.Component:
    return rx.grid(
        stat_card("server", "Total Devices", DeviceState.total_devices, "text-gray-500"),
        stat_card("wifi", "Online", DeviceState.online_devices, "text-green-500"),
        stat_card("wifi-off", "Offline", DeviceState.offline_devices, "text-red-500"),
        gap="1rem",
        grid_template_columns=[
            "1fr",
            "repeat(1, 1fr)",
            "repeat(2, 1fr)",
            "repeat(3, 1fr)",
        ],
        width="100%",
    )
