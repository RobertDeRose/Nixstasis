from typing import Optional, TYPE_CHECKING

import reflex as rx
from sqlmodel import Field, Relationship

from .utils import StatusType


if TYPE_CHECKING:
    from .device import Device


class Reader(rx.Model, table=True):
    __tablename__ = "readers"

    id: int | None = Field(default=None, primary_key=True)
    serial_number: str = Field(unique=True)
    position: str | None = None
    profile: str | None = None
    tx_band: str | None = None
    region: str | None = None
    model: str | None = None
    version: str | None = None
    status: StatusType = StatusType.OFFLINE
    finalized: bool = False
    inventory: bool = False

    device_id: int | None = Field(default=None, foreign_key="devices.id")
    device: Optional["Device"] = Relationship(back_populates="readers")
