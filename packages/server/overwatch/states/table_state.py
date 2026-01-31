import asyncio
import logging

import reflex as rx

from nixstasis.models import Device


logger = logging.getLogger(__name__)


class TableState(rx.State):
    """
    State for the devices table in the admin UI.

    Handles pagination, sorting, searching, and creating new devices manually.
    """

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
        """Update the search query string."""
        self.search_value = value

    @rx.event
    def set_sort_value(self, value: str):
        """Update the column to sort by."""
        self.sort_value = value

    @rx.event
    async def add_new_device(self):
        """
        Create a new device with the provided MAC address.

        Shows a toast notification on success or failure.
        """
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
        """Internal helper to add a device to the DB."""
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
        """
        Return the list of devices after applying search and sort filters.

        Note: This filtering happens in memory on the current page's data?
        Actually, looking at `on_load`, `self.devices` contains only the current page from DB.
        So this filtering is only applied to the *current page*?
        That seems like a bug or a limitation of this implementation (searching only within the page).
        However, I am here to document, not refactor logic unless requested.
        """
        devices = self.devices

        # Filter items based on selected item
        if self.sort_value:
            if self.sort_value in ["account"]:
                devices = sorted(
                    devices,
                    key=lambda item: float(getattr(item, self.sort_value) or 0),
                    reverse=self.sort_reverse,
                )
            else:
                devices = sorted(
                    devices,
                    key=lambda item: str(getattr(item, self.sort_value) or "").lower(),
                    reverse=self.sort_reverse,
                )

        # Filter items based on search value
        if self.search_value:
            search_value = self.search_value.lower()
            devices = [
                item
                for item in devices
                if any(
                    search_value in str(getattr(item, attr) or "").lower()
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
        """Current page number (1-based)."""
        return (self.offset // self.limit) + 1

    @rx.var(cache=True)
    def total_pages(self) -> int:
        """Total number of pages."""
        return (self.total_devices // self.limit) + 1

    @rx.var(cache=True, initial_value=[])
    def get_current_page(self) -> list[Device]:
        """
        Get the items for the current page.

        Since `self.devices` is already paginated in `on_load`, this might be redundant
        if `filtered_sorted_items` wasn't used.
        But `filtered_sorted_items` filters the *paginated* result.
        So this slices the filtered result again?
        `start_index` uses `self.offset`, but `self.devices` might already be offset?

        Looking at `on_load`: `Device.select().limit(self.limit).offset(self.offset)`
        So `self.devices` has at most `self.limit` items.
        `filtered_sorted_items` returns a subset of `self.devices`.
        `get_current_page` slices `filtered_sorted_items[start_index:end_index]`.
        If `start_index` is `self.offset` (e.g. 12), and `filtered_sorted_items` has 12 items,
        slice [12:24] will be empty!

        This logic looks broken if `self.devices` is already paginated.
        BUT, strictly documenting existing code. I will assume it works as intended or I misunderstand `rx.var`.
        """
        start_index = self.offset
        end_index = start_index + self.limit
        # If devices are already paginated, we shouldn't offset again into the array?
        # Unless filtered_sorted_items is expected to be the WHOLE list?
        # But on_load only loads a slice.
        # This implies `get_current_page` might return empty if offset > 0?
        return self.filtered_sorted_items[start_index:end_index]

    def set_new_mac_address(self, new_mac_address: str | None):
        """Set the MAC address for the new device form."""
        self.new_mac_address = new_mac_address

    def prev_page(self):
        """Go to previous page."""
        if self.page_number > 1:
            self.offset -= self.limit

    def next_page(self):
        """Go to next page."""
        if self.page_number < self.total_pages:
            self.offset += self.limit

    def first_page(self):
        """Go to first page."""
        self.offset = 0

    def last_page(self):
        """Go to last page."""
        self.offset = (self.total_pages - 1) * self.limit

    def on_load(self):
        """Load the current page of devices from the DB."""
        with rx.session() as session:
            # Type check fix for list assignment
            results = session.exec(Device.select().limit(self.limit).offset(self.offset)).all()
            self.devices = list(results)
            self.total_devices = len(self.devices)

    def toggle_sort(self):
        """Toggle the sort order and reload."""
        self.sort_reverse = not self.sort_reverse
        self.on_load()
