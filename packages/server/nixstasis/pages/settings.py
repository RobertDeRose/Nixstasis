"""The settings page."""

import reflex as rx
from reflex.style import color_mode, set_color_mode

from ..components.color_picker import primary_color_picker, secondary_color_picker
from ..components.radius_picker import radius_picker
from ..components.scaling_picker import scaling_picker
from ..templates import template


def dark_mode_toggle() -> rx.Component:
    return rx.segmented_control.root(
        rx.segmented_control.item(
            rx.icon(tag="monitor", size=20),
            value="system",
        ),
        rx.segmented_control.item(
            rx.icon(tag="sun", size=20),
            value="light",
        ),
        rx.segmented_control.item(
            rx.icon(tag="moon", size=20),
            value="dark",
        ),
        on_change=set_color_mode,
        variant="classic",
        radius="large",
        value=color_mode,
    )


@template(route="/settings", title="Settings", icon="settings")
def settings() -> rx.Component:
    """The settings page.

    Returns:
        The UI for the settings page.

    """
    return rx.vstack(
        rx.heading("Settings"),
        # Light Mode
        rx.vstack(
            rx.hstack(
                rx.icon("sun-moon"),
                rx.heading("Appearance", size="5"),
                align="center",
            ),
            rx.hstack(
                dark_mode_toggle(),
                align="center",
            ),
            spacing="4",
            width="100%",
            align="start",
        ),
        # Primary color picker
        rx.vstack(
            rx.hstack(
                rx.icon("palette", color=rx.color("accent", 10)),
                rx.heading("Primary color", size="5"),
                align="center",
            ),
            primary_color_picker(),
            spacing="4",
            width="100%",
        ),
        # Secondary color picker
        rx.vstack(
            rx.hstack(
                rx.icon("blend", color=rx.color("gray", 10)),
                rx.heading("Secondary color", size="5"),
                align="center",
            ),
            secondary_color_picker(),
            spacing="4",
            width="100%",
        ),
        # Radius picker
        radius_picker(),
        # Scaling picker
        scaling_picker(),
        spacing="7",
        width="100%",
    )
