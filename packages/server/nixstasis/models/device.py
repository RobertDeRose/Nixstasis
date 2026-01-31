from datetime import datetime
from ipaddress import IPv4Address, IPv6Address
from typing import Annotated
from uuid import UUID, uuid4

import reflex as rx
from pydantic import PlainValidator, ValidationError
from sqlmodel import Field, Relationship, SQLModel, UniqueConstraint

from .reader import Reader
from .utils import StatusType


def _validate_ipaddress(value: str):
    try:
        IPv4Address(value)
        return value
    except Exception:
        try:
            IPv6Address(value)
            return value.upper()
        except Exception:
            error = f"{value} is not a valid IPv4 or IPv6 address"
            raise ValidationError(error) from None


NonBlankStr = Annotated[str | None, PlainValidator(lambda v: None if v == "" else v)]


class DeviceCreate(SQLModel):
    """Schema for creating/registering a new device."""

    mac_address: Annotated[str, PlainValidator(str.upper)] = Field(
        unique=True,
        description="The physical MAC address of the device (eth0). Used as the unique hardware identifier.",
        schema_extra={"example": "00:11:22:33:44:55"},
    )
    ip_address: Annotated[str | None, PlainValidator(_validate_ipaddress)] = Field(
        default=None,
        description="The WAN IPv4 or IPv6 address of the device.",
        schema_extra={"example": "192.168.1.100"},
    )


class DeviceUpdate(SQLModel):
    """Schema for updating device status and metadata."""

    account: int | None = Field(
        default=None,
        description="The account number associated with this device location.",
        schema_extra={"example": 12345},
    )
    store: NonBlankStr = Field(
        default=None,
        description="The store number or identifier.",
        schema_extra={"example": "STORE-001"},
    )
    door: NonBlankStr = Field(
        default=None,
        description="The specific door or entrance identifier where the device is installed.",
        schema_extra={"example": "Front Entrance"},
    )
    software_version: str | None = Field(
        default=None,
        description="The version of the Nixstasis client software running on the device.",
        schema_extra={"example": "1.0.0"},
    )
    firmware_version: str | None = Field(
        default=None,
        description="The firmware version of the attached RFID readers.",
        schema_extra={"example": "2.5.0"},
    )
    remote_access_token: str | None = Field(
        default=None,
        description="The auth token for the device's local web server.",
    )
    remote_connection_string: str | None = Field(
        default=None,
        description="The active FRP tunnel subdomain/URL for remote access.",
        schema_extra={"example": "atom-001122334455"},
    )
    last_seen: datetime | None = Field(
        default=None,
        description="Timestamp of the last successful poll.",
    )


class DeviceUpdateWithReaders(DeviceUpdate):
    """Extended update model that includes relationship data (connected readers)."""

    readers: list[Reader] | None = Field(
        default=None,
        description="List of RFID readers currently connected to the device.",
    )


class Device(DeviceCreate, DeviceUpdate, rx.Model, table=True):
    """Database model for a Device."""

    __tablename__ = "devices"
    __table_args__ = (
        UniqueConstraint("mac_address", name="uq_mac_address"),
        UniqueConstraint("account", "store", "door", name="uq_device_triplet"),
    )

    id: UUID = Field(
        default_factory=uuid4,
        primary_key=True,
        description="Unique UUID for the device record.",
    )
    remote_access_requested: bool = Field(
        default=False,
        description="Flag indicating if the server wants the device to open a remote tunnel.",
    )
    status: StatusType = Field(
        default=StatusType.OFFLINE,
        description="Current online/offline status based on polling.",
    )

    readers: list[Reader] | None = Relationship(
        back_populates="device",
        sa_relationship_kwargs={"lazy": "selectin"},
    )
