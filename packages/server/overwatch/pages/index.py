"""The overview page of the app."""

import reflex as rx

from .. import styles
from ..components.device_grid import devices_grid
from ..components.stats_cards import stats_cards
from ..states.device_state import DeviceState
from ..templates import template


def search_bar() -> rx.Component:
    return rx.flex(
        rx.input(
            rx.input.slot(rx.icon("search"), padding_left="0"),
            placeholder="Search by name, IP, or MAC Address",
            size="3",
            width="100%",
            max_width="450px",
            radius="large",
            style=styles.ghost_input_style,
            class_name="pl-2 border",
        ),
        justify="between",
        align="center",
        width="100%",
    )


def filter_button(label: str, status: str) -> rx.Component:
    is_active = DeviceState.filter_status == status
    return rx.button(
        label,
        on_click=DeviceState.set_filter_status(status),
        color_scheme=rx.cond(is_active, "accent", "gray"),
        class_name="first:ml-3",
    )


def controls_bar() -> rx.Component:
    return rx.flex(
        search_bar(),
        rx.hstack(
            filter_button("All", "all"),
            filter_button("Online", "online"),
            filter_button("Offline", "offline"),
            align="end",
        ),
        justify="between",
        align="center",
        width="100%",
    )


@template(route="/", title="Dashboard", icon="layout-grid", on_load=DeviceState.on_load)
def index() -> rx.Component:
    """The overview page.

    Returns:
        The UI for the overview page.

    """
    return rx.vstack(
        rx.moment(interval=1000, on_change=DeviceState.on_load, display="none"),
        stats_cards(),
        controls_bar(),
        devices_grid(),
        spacing="8",
        width="100%",
    )
