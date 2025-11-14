import csv
import gzip
from collections.abc import Iterable
from io import BytesIO
from pathlib import Path
from typing import Any

import reflex as rx
from sqlmodel import select

from ..components.reader_modal import reader_modal
from ..models import Device
from ..states.table_state import TableState
from .status_badge import status_badge


def _download_csv() -> Path:
    header = ["mac_address", "account", "store", "door", "software_version", "firmware_version"]
    with rx.session() as session:
        stm = select(
            Device.mac_address,
            Device.account,
            Device.store,
            Device.door,
            Device.software_version,
            Device.firmware_version,
        )

        return rx.download(
            data=_convert_data_to_csv(header, session.exec(stm).all()), filename="devices.csv.gz", mime_type="text/csv"
        )


def _convert_data_to_csv(header: list[str], data: Iterable[Any]) -> bytes:
    """Convert data into a compressed CSV file without using pandas."""
    compressed_data = BytesIO()
    # Write the data as a compressed CSV file
    with gzip.open(compressed_data, "wt", newline="", encoding="utf-8") as gz_file:
        writer = csv.writer(gz_file)
        writer.writerow(header)  # Write the header
        writer.writerows(data)  # Write the rows

    return compressed_data.getvalue()


def add_device_component() -> rx.Component:
    return rx.popover.root(
        rx.popover.trigger(
            rx.button(
                rx.icon("key-round", size=20),
                "Approve New Device",
                size="3",
                variant="surface",
                display=["none", "none", "none", "flex"],
                color_scheme="green",
            ),
        ),
        rx.popover.content(
            rx.card(
                rx.vstack(
                    rx.hstack(rx.icon("fingerprint", size=25), rx.text.strong("MAC Address")),
                    rx.form(
                        rx.hstack(
                            rx.input(
                                placeholder="00:11:22:33:44:55:66:77",
                                type="text",
                                required=True,
                                on_change=TableState.set_new_mac_address,
                            ),
                            rx.popover.close(
                                rx.button("Save", on_click=TableState.add_new_device, type="submit"),
                            ),
                        ),
                        width="100%",
                    ),
                ),
                align_items="left",
                width="100%",
            ),
        ),
    )


def _header_cell(text: str, icon: str) -> rx.Component:
    return rx.table.column_header_cell(
        rx.hstack(
            rx.icon(icon, size=18),
            rx.text(text),
            align="center",
            spacing="2",
        ),
    )


def _show_item(device: Device, index: int) -> rx.Component:
    bg_color = rx.cond(
        index % 2 == 0,
        rx.color("gray", 1),
        rx.color("accent", 2),
    )
    hover_color = rx.cond(
        index % 2 == 0,
        rx.color("gray", 3),
        rx.color("accent", 3),
    )
    return rx.table.row(
        rx.table.row_header_cell(device.mac_address),
        rx.table.cell(device.account),
        rx.table.cell(device.store),
        rx.table.cell(device.door),
        rx.table.cell(status_badge(device.status)),
        rx.table.cell(rx.cond(device.readers, reader_modal(device))),
        style={"_hover": {"bg": hover_color}, "bg": bg_color},
        align="center",
    )


def _pagination_view() -> rx.Component:
    return (
        rx.hstack(
            rx.text(
                "Page ",
                rx.code(TableState.page_number),
                f" of {TableState.total_pages}",
                justify="end",
            ),
            rx.hstack(
                rx.icon_button(
                    rx.icon("chevrons-left", size=18),
                    on_click=TableState.first_page,
                    opacity=rx.cond(TableState.page_number == 1, 0.6, 1),
                    color_scheme=rx.cond(TableState.page_number == 1, "gray", "accent"),
                    variant="soft",
                ),
                rx.icon_button(
                    rx.icon("chevron-left", size=18),
                    on_click=TableState.prev_page,
                    opacity=rx.cond(TableState.page_number == 1, 0.6, 1),
                    color_scheme=rx.cond(TableState.page_number == 1, "gray", "accent"),
                    variant="soft",
                ),
                rx.icon_button(
                    rx.icon("chevron-right", size=18),
                    on_click=TableState.next_page,
                    opacity=rx.cond(TableState.page_number == TableState.total_pages, 0.6, 1),
                    color_scheme=rx.cond(
                        TableState.page_number == TableState.total_pages,
                        "gray",
                        "accent",
                    ),
                    variant="soft",
                ),
                rx.icon_button(
                    rx.icon("chevrons-right", size=18),
                    on_click=TableState.last_page,
                    opacity=rx.cond(TableState.page_number == TableState.total_pages, 0.6, 1),
                    color_scheme=rx.cond(
                        TableState.page_number == TableState.total_pages,
                        "gray",
                        "accent",
                    ),
                    variant="soft",
                ),
                align="center",
                spacing="2",
                justify="end",
            ),
            spacing="5",
            margin_top="1em",
            align="center",
            width="100%",
            justify="end",
        ),
    )


def device_table() -> rx.Component:
    return rx.box(
        rx.flex(
            rx.flex(
                rx.cond(
                    TableState.sort_reverse,
                    rx.icon(
                        "arrow-down-z-a",
                        size=28,
                        stroke_width=1.5,
                        cursor="pointer",
                        flex_shrink="0",
                        on_click=TableState.toggle_sort,
                    ),
                    rx.icon(
                        "arrow-down-a-z",
                        size=28,
                        stroke_width=1.5,
                        cursor="pointer",
                        flex_shrink="0",
                        on_click=TableState.toggle_sort,
                    ),
                ),
                rx.select(
                    [
                        "account",
                        "store",
                        "door",
                        "status",
                    ],
                    placeholder="Sort By: Name",
                    size="3",
                    on_change=TableState.set_sort_value,
                ),
                rx.input(
                    rx.input.slot(rx.icon("search")),
                    rx.input.slot(
                        rx.icon("x"),
                        justify="end",
                        cursor="pointer",
                        on_click=TableState.set_search_value(""),
                        display=rx.cond(TableState.search_value, "flex", "none"),
                    ),
                    value=TableState.search_value,
                    placeholder="Search here...",
                    size="3",
                    max_width=["150px", "150px", "200px", "250px"],
                    width="100%",
                    variant="surface",
                    color_scheme="gray",
                    on_change=TableState.set_search_value,
                ),
                align="center",
                justify="end",
                spacing="3",
            ),
            rx.hstack(
                rx.tooltip(rx.icon("circle-help"), content="A device cannot register itself until approved"),
                add_device_component(),
                rx.tooltip(
                    rx.button(
                        rx.icon("hard-drive-download", size=20),
                        "Export to CSV",
                        size="3",
                        variant="surface",
                        display=["none", "none", "none", "flex"],
                        on_click=_download_csv,
                    ),
                    content="Export all devices as a GZipped CSV file",
                ),
                align="center",
            ),
            spacing="3",
            justify="between",
            wrap="wrap",
            width="100%",
            padding_bottom="1em",
        ),
        rx.table.root(
            rx.table.header(
                rx.table.row(
                    _header_cell("MAC Address", "fingerprint"),
                    _header_cell("Account", "building"),
                    _header_cell("Store", "store"),
                    _header_cell("Door", "door-open"),
                    _header_cell("Status", "activity"),
                    rx.table.column_header_cell(""),
                ),
            ),
            rx.table.body(
                rx.foreach(
                    TableState.get_current_page,
                    lambda device, index: _show_item(device, index),
                )
            ),
            variant="surface",
            size="3",
            width="100%",
        ),
        _pagination_view(),
        width="100%",
    )
