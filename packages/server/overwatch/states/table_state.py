import asyncio
import logging

import reflex as rx

from nixstasis.models import Device


logger = logging.getLogger(__name__)


class TableState(rx.State):
    """The state class."""

    new_mac_address: str | None = None
    devices: list[Device] = []

    search_value: str = ""
    sort_value: str = ""
    sort_reverse: bool = False

    total_devices: int = 0
    offset: int = 0
    limit: int = 12  # Number of rows per page

    @rx.event
    def set_search_value(self, value: str):
        self.search_value = value

    @rx.event
    def set_sort_value(self, value: str):
        self.sort_value = value

    @rx.event
    async def add_new_device(self):
        mac_address = self.new_mac_address
        if not mac_address:
            return

        error = await asyncio.to_thread(self._add_new_device, mac_address)
        if error:
            yield rx.toast.error(error, position="top-right")
        else:
            yield rx.toast.success(f"Create new device for {mac_address}", position="top-right")
            self.set_new_mac_address(None)

    def _add_new_device(self, mac_address: str) -> str | None:
        with rx.session() as session:
            device = Device.model_validate(dict(mac_address=mac_address))
            session.add(device)
            try:
                session.commit()
                session.refresh(device)
                self.devices.append(device)
                self.total_devices = len(self.devices)
                rx.toast.success(
                    f"Added new device for {mac_address}",
                    position="top-right",
                )
            except Exception as e:
                error = str(e).lower()
                if "unique" in error:
                    return f"A device with the MAC Address {mac_address} already exists"

                logger.exception("Unable to create new device with mac %s", mac_address)
                return "Unknown error adding device"

    @rx.var(cache=True)
    def filtered_sorted_items(self) -> list[Device]:
        devices = self.devices

        # Filter items based on selected item
        if self.sort_value:
            if self.sort_value in ["account"]:
                devices = sorted(
                    devices,
                    key=lambda item: float(getattr(item, self.sort_value)),
                    reverse=self.sort_reverse,
                )
            else:
                devices = sorted(
                    devices,
                    key=lambda item: str(getattr(item, self.sort_value)).lower(),
                    reverse=self.sort_reverse,
                )

        # Filter items based on search value
        if self.search_value:
            search_value = self.search_value.lower()
            devices = [
                item
                for item in devices
                if any(
                    search_value in str(getattr(item, attr)).lower()
                    for attr in [
                        "account",
                        "store",
                        "door",
                        "status",
                    ]
                )
            ]

        return devices

    @rx.var(cache=True)
    def page_number(self) -> int:
        return (self.offset // self.limit) + 1

    @rx.var(cache=True)
    def total_pages(self) -> int:
        return (self.total_devices // self.limit) + 1

    @rx.var(cache=True, initial_value=[])
    def get_current_page(self) -> list[Device]:
        start_index = self.offset
        end_index = start_index + self.limit
        return self.filtered_sorted_items[start_index:end_index]

    def set_new_mac_address(self, new_mac_address: str | None):
        self.new_mac_address = new_mac_address

    def prev_page(self):
        if self.page_number > 1:
            self.offset -= self.limit

    def next_page(self):
        if self.page_number < self.total_pages:
            self.offset += self.limit

    def first_page(self):
        self.offset = 0

    def last_page(self):
        self.offset = (self.total_pages - 1) * self.limit

    def on_load(self):
        with rx.session() as session:
            self.devices = session.exec(Device.select().limit(self.limit).offset(self.offset)).all()
            self.total_devices = len(self.devices)

    def toggle_sort(self):
        self.sort_reverse = not self.sort_reverse
        self.on_load()
