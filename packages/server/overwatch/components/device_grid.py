import reflex as rx

from nixstasis.components.device_card import device_card
from nixstasis.states.device_state import DeviceState


def devices_grid() -> rx.Component:
    # Device grid
    grid = rx.grid(
        rx.foreach(DeviceState.filtered_devices, device_card),
        columns="2",
        spacing="6",
        width="100%",
        style={
            "grid_template_columns": "repeat(1, minmax(0, 1fr))",
            "@media (min-width: 1024px)": {
                "grid_template_columns": "repeat(2, minmax(0, 1fr))",
            },
        },
    )

    # Empty state
    empty_state = rx.flex(
        rx.icon("search-x", size=48, color="var(--gray-9)"),
        rx.heading(
            "No Devices Found",
            size="5",
            weight="bold",
            color="gray",
            margin_top="4",
        ),
        rx.text(
            "Your search or filter did not match any devices.",
            size="2",
            color="gray",
            margin_top="1",
        ),
        direction="column",
        align="center",
        justify="center",
        style={
            "background_color": "var(--gray-2)",
            "border": "2px dashed var(--gray-6)",
            "border_radius": "var(--radius-4)",
            "grid_column": "1 / -1",
        },
        class_name="py-30",
    )
    empty_state = rx.grid(
        empty_state,
        gap="1rem",
        grid_template_columns=[
            "1fr",
            "repeat(1, 1fr)",
            "repeat(2, 1fr)",
            "repeat(3, 1fr)",
            "repeat(3, 1fr)",
        ],
        width="100%",
        padding_y="20",
    )

    return rx.cond(
        DeviceState.filtered_devices.length() > 0,
        grid,
        empty_state,
    )
