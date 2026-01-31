import asyncio
import logging
from datetime import datetime, timedelta

import reflex as rx

from nixstasis.models import Device
from nixstasis.models.utils import StatusType


logger = logging.getLogger(__name__)


async def mark_offline():
    try:
        while True:
            await asyncio.sleep(120)
            await asyncio.to_thread(_update_status)
    except asyncio.CancelledError:
        logger.info("Shutting down stask 'mark_offline'")


def _update_status():
    two_minutes_ago = datetime.now() - timedelta(minutes=2)

    with rx.session() as session:
        for device in session.exec(Device.select().where(Device.last_seen <= two_minutes_ago)).all():
            device.status = StatusType.OFFLINE
            session.add(device)

        session.commit()
