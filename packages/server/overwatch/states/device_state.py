import asyncio
import logging
from uuid import UUID

import reflex as rx
from sqlmodel import func, select

from nixstasis.models import Device, StatusType


logger = logging.getLogger(__name__)


class DeviceState(rx.State):
    """
    State management for the Devices page.

    Maintains the list of all devices, filters, and handles live updates
    via polling or events.
    """

    _all_devices: dict[UUID, Device] = {}
    _online_devices: set[UUID] = set()
    _offline_devices: set[UUID] = set()
    search_query: str = ""
    filter_status: str = "all"

    @rx.event
    def set_filter_status(self, status: str):
        """Set the filter status."""
        self.filter_status = status

    @rx.event
    def on_load(self) -> None:
        """Load all devices from the database on page load."""
        with rx.session() as session:
            devices = session.exec(Device.select()).all()

            self._all_devices.clear()
            self._online_devices.clear()
            self._offline_devices.clear()
            for d in devices:
                self._all_devices[d.id] = d
                if d.status == StatusType.ONLINE:
                    self._online_devices.add(d.id)
                else:
                    self._offline_devices.add(d.id)

    @rx.event
    async def check_for_updates(self) -> None:
        """
        Background task to check if the number of devices has changed.

        If the count differs from the local state, reloads the full list.
        """
        with rx.session() as session:
            # Type ignore: SQLModel field vs instance type confusion
            stm = select(func.count(Device.id))  # type: ignore
            result = await asyncio.to_thread(session.exec, stm)
            count = result.one()
            async with self:
                if count != self.total_devices:
                    self.on_load()

    @rx.var
    def filtered_devices(self) -> list[Device]:
        """Return devices filtered by status and search query."""
        devices = list(self._all_devices.values())
        if self.filter_status != "all":
            devices = [d for d in devices if d.status == self.filter_status]
        if self.search_query:
            query = self.search_query.lower()
            devices = [
                v
                for v in devices
                if (v.store and query in v.store.lower())
                or (v.account and query in str(v.account).lower())
                or (v.door and query in v.door.lower())
                or (v.ip_address and query in v.ip_address.lower())
                or (v.mac_address and query in v.mac_address.lower())
            ]
        return devices

    @rx.var
    def total_devices(self) -> int:
        """Total count of devices."""
        return len(self._all_devices)

    @rx.var
    def online_devices(self) -> int:
        """Count of online devices."""
        return len(self._online_devices)

    @rx.var
    def offline_devices(self) -> int:
        """Count of offline devices."""
        return len(self._offline_devices)

    @rx.event(background=True)
    async def request_remote_access(self, device_id: UUID | str):
        """Request remote access for a device and update DB."""
        if not device_id:
            return
        if isinstance(device_id, str):
            try:
                device_id = UUID(device_id)
            except Exception:
                logger.exception("Unable to convert %s to a valid UUID", device_id)
                return

        # device_id is now UUID
        device = await asyncio.to_thread(self._request_remote_access, device_id)
        if device:
            async with self:
                self._all_devices[device.id] = device
        else:
            logger.warning("Unable to located device with ID: %s", device_id)

    def _request_remote_access(self, device_id: UUID) -> Device | None:
        with rx.session() as session:
            device = session.exec(Device.select().where(Device.id == device_id)).one_or_none()
            if device:
                device.remote_access_requested = True
                session.add(device)
                session.commit()
                session.refresh(device)
                return device

        return None

    @rx.event(background=True)
    async def handle_register_device(self, device: Device):
        """Register or update a device in the database."""
        async with self:
            self._all_devices[device.id] = device

    @rx.event(background=True)
    async def handle_poll(self, device: Device):
        """Handle a device poll event to update the local state."""
        async with self:
            self._all_devices[device.id] = device
