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
    """Register a device with Nixstasis

    Returns
    -------
    Device
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
            logger.exception("Unable to register device with payload %s", device)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST) from e

    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)


@router.post(
    "/{device_id}/poll",
    responses={
        status.HTTP_404_NOT_FOUND: dict(description="The device was not found for updating"),
    },
)
def poll(device_id: UUID, device_update: DeviceUpdateWithReaders | DeviceUpdate) -> Device:
    """Update Nixstasis about current device status

    Once a device is registered, it is expected to poll Nixstasis periodically as a healthcheck and as a way to get
    update request from Nixstasis.

    Returns
    -------
    Device
    """
    with rx.session() as session:
        device = session.exec(Device.select().where(Device.id == device_id)).one_or_none()

        if device:
            previous_connection_string = device.remote_connection_string

            device.sqlmodel_update(device_update.model_dump(exclude_unset=True))
            device.last_seen = datetime.now()
            device.status = StatusType.ONLINE

            if previous_connection_string and not device.remote_connection_string:
                device.remote_access_requested = False

            session.add(device)
            session.commit()
            session.refresh(device)
            DeviceState.handle_poll(device)
            return device

    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
