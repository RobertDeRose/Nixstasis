import asyncio

import reflex as rx

from nixstasis.models import Device


class ModalState(rx.State):
    """Manages the state for all modals in the application."""

    show_modal: bool = False
    selected_device: Device | None = None
    show_connection_modal: bool = False
    connection_string_to_display: str = ""
    copied: bool = False

    @rx.event
    def open_modal(self, device: dict):
        """Open the device detail modal."""
        self.selected_device = Device(**device)
        self.show_modal = True

    @rx.event
    def close_modal(self):
        """Close the device detail modal."""
        self.show_modal = False
        self.selected_device = None

    @rx.event
    def open_connection_modal(self, connection_string: str):
        """Open the connection string modal."""
        self.connection_string_to_display = connection_string
        self.show_connection_modal = True
        self.copied = False

    @rx.event
    def close_connection_modal(self):
        """Close the connection string modal."""
        self.show_connection_modal = False
        self.connection_string_to_display = ""

    @rx.event
    def copy_to_clipboard(self):
        """Copy the connection string to the clipboard and show feedback."""
        yield rx.set_clipboard(self.connection_string_to_display)
        self.copied = True
        yield asyncio.sleep(2)
        self.copied = False
