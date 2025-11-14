import reflex as rx

from nixstasis.models import Device, Reader


def reader_row(reader: Reader) -> rx.Component:
    return rx.table.row(
        rx.table.row_header_cell(reader.position),
        rx.table.cell(reader.serial_number),
        rx.table.cell(reader.status),
        rx.table.cell(reader.inventory),
        rx.table.cell(reader.finalized),
        rx.table.cell(reader.profile),
        rx.table.cell(reader.tx_band),
        rx.table.cell(reader.model),
        rx.table.cell(reader.version),
    )


def reader_modal(device: Device) -> rx.Component:
    return rx.dialog.root(
        rx.dialog.trigger(
            rx.button("View Readers", rx.icon("heater", size=16), variant="soft"),
        ),
        rx.dialog.content(
            rx.flex(
                rx.heading("Attached Readers"),
                rx.table.root(
                    rx.table.header(
                        rx.table.row(
                            rx.table.column_header_cell("Position"),
                            rx.table.column_header_cell("Serial Number"),
                            rx.table.column_header_cell("Status"),
                            rx.table.column_header_cell("Inventory"),
                            rx.table.column_header_cell("Finalized"),
                            rx.table.column_header_cell("Profile"),
                            rx.table.column_header_cell("TX Band"),
                            rx.table.column_header_cell("Model"),
                            rx.table.column_header_cell("F/W Version"),
                        ),
                    ),
                    rx.table.body(rx.foreach(device.readers, reader_row)),
                ),
                rx.flex(
                    rx.dialog.close(rx.button("Cancel", color_scheme="gray", variant="soft")),
                    spacing="3",
                    margin_top="16px",
                    justify="end",
                ),
                spacing="3",
                direction="column",
            ),
            max_width="960px",  # Use max_width on dialog.content
        ),
    )
