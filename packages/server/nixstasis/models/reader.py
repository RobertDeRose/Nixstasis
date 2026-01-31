from typing import Optional, TYPE_CHECKING

import reflex as rx
from sqlmodel import Field, Relationship

from .utils import StatusType


if TYPE_CHECKING:
    from .device import Device


class Reader(rx.Model, table=True):
    """Database model for an RFID Reader connected to a Device."""

    __tablename__ = "readers"

    id: int | None = Field(
        default=None,
        primary_key=True,
        description="Unique DB ID for the reader.",
    )
    serial_number: str = Field(
        unique=True,
        description="Manufacturer serial number of the reader.",
        schema_extra={"example": "SR12345678"},
    )
    position: str | None = Field(
        default=None,
        description="Physical location/position in the store or aisle.",
        schema_extra={"example": "Overhead-1"},
    )
    profile: str | None = Field(
        default=None,
        description="Configuration profile name.",
        schema_extra={"example": "Standard-Inventory"},
    )
    tx_band: str | None = Field(
        default=None,
        description="Transmission frequency band.",
        schema_extra={"example": "FCC"},
    )
    region: str | None = Field(
        default=None,
        description="Operating region code.",
        schema_extra={"example": "US"},
    )
    model: str | None = Field(
        default=None,
        description="Model name/number.",
        schema_extra={"example": "R2000"},
    )
    version: str | None = Field(
        default=None,
        description="Firmware version.",
        schema_extra={"example": "1.2.3"},
    )
    status: StatusType = Field(
        default=StatusType.OFFLINE,
        description="Current status (online, offline, etc.).",
    )
    finalized: bool = Field(
        default=False,
        description="Whether the reader provisioning is finalized.",
    )
    inventory: bool = Field(
        default=False,
        description="Whether the reader is currently running inventory.",
    )

    device_id: int | None = Field(
        default=None,
        foreign_key="devices.id",
        description="Foreign key to the parent Device.",
    )
    device: Optional["Device"] = Relationship(back_populates="readers")
