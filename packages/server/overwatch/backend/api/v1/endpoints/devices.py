import logging
from datetime import datetime
from uuid import UUID

import reflex as rx
from fastapi import APIRouter, HTTPException, status
from sqlalchemy.exc import SQLAlchemyError

from nixstasis.models import Device, DeviceCreate, DeviceUpdate, DeviceUpdateWithReaders
from nixstasis.models.utils import StatusType
from nixstasis.states.device_state import DeviceState


logger = logging.getLogger(__name__)
router = APIRouter()


@router.post(
    "/register",
    responses={
        status.HTTP_400_BAD_REQUEST: dict(description="The request was not valid"),
        status.HTTP_404_NOT_FOUND: dict(description="The device's MAC Address was not approved for registration"),
    },
)
def register(device_create: DeviceCreate) -> Device:
    """
    Register a device with Nixstasis.

    This endpoint is called by the device during its initial provisioning or
    when it needs to re-establish its identity. It looks up the device by MAC address
    (which must be pre-seeded in the DB) and updates its IP and online status.

    Args:
        device_create: The registration payload containing MAC and IP addresses.

    Returns:
        Device: The updated device record.

    Raises:
        HTTPException(400): If there is a database error.
        HTTPException(404): If the MAC address is not found in the allowed devices list.
    """
    with rx.session() as session:
        try:
            stm = Device.select().where(Device.mac_address == device_create.mac_address)
            device = session.exec(stm).one_or_none()
            if device:
                device.status = StatusType.ONLINE
                device.last_seen = datetime.now()
                device.ip_address = device_create.ip_address
                session.add(device)
                session.commit()
                session.refresh(device)
                DeviceState.handle_register_device(device)
                return device
        except SQLAlchemyError as e:
            logger.exception("Unable to register device with payload %s", device_create)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST) from e

    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)


@router.post(
    "/{device_id}/poll",
    responses={
        status.HTTP_404_NOT_FOUND: dict(description="The device was not found for updating"),
    },
)
def poll(device_id: UUID, device_update: DeviceUpdateWithReaders | DeviceUpdate) -> Device:
    """
    Update Nixstasis with current device status and retrieve pending commands.

    Once a device is registered, it polls this endpoint periodically (e.g., every 30s)
    to report its health (heartbeat) and updated metadata (readers, versions).
    The response may contain commands or configuration updates from the server,
    such as a request to open a remote access tunnel.

    Args:
        device_id: The UUID of the device.
        device_update: The payload containing status updates, including connected readers.

    Returns:
        Device: The updated device record, which the client uses to check for `remote_access_requested`.

    Raises:
        HTTPException(404): If the device ID is not found.
    """
    with rx.session() as session:
        device = session.exec(Device.select().where(Device.id == device_id)).one_or_none()

        if device:
            previous_connection_string = device.remote_connection_string

            device.sqlmodel_update(device_update.model_dump(exclude_unset=True))
            device.last_seen = datetime.now()
            device.status = StatusType.ONLINE

            # If the device just started reporting a connection string, it means the tunnel is up.
            # If the tunnel is up, we can clear the 'request' flag unless we want to keep it persistent.
            # Logic here seems to be: if we had a connection string before, and now we don't (implied check?),
            # or maybe checking if the request was fulfilled?
            # "if previous_connection_string and not device.remote_connection_string:"
            # implies checking if the connection dropped?
            # Actually, the original logic was:
            if previous_connection_string and not device.remote_connection_string:
                device.remote_access_requested = False

            session.add(device)
            session.commit()
            session.refresh(device)
            DeviceState.handle_poll(device)
            return device

    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
