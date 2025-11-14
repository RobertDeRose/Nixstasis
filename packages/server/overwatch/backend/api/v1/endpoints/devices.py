import logging
from datetime import datetime
from uuid import UUID

import reflex as rx
from fastapi import APIRouter, HTTPException, status
from sqlalchemy.exc import SQLAlchemyError

from nixstasis.models import Device, DeviceCreate, DeviceUpdate, DeviceUpdateWithReaders
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
            device = Device(**device_create.model_dump())
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
            device.sqlmodel_update(device_update.model_dump(exclude_unset=True))
            device.last_seen = datetime.now()
            session.add(device)
            session.commit()
            session.refresh(device)
            DeviceState.handle_poll(device)
            return device

    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
