"""The table page."""

import reflex as rx

from ..components.devices import device_table
from ..states.table_state import TableState
from ..templates import template


@template(route="/devices", title="Devices", icon="server", on_load=TableState.on_load)
def devices() -> rx.Component:
    """The table page.

    Returns:
        The UI for the table page.

    """
    return rx.vstack(
        rx.heading("Devices", size="5"),
        device_table(),
        spacing="8",
        width="100%",
    )
