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
            raise ValidationError(error) from ...


NonBlankStr = Annotated[str | None, PlainValidator(lambda v: None if v == "" else v)]


class DeviceCreate(SQLModel):
    mac_address: Annotated[str, PlainValidator(str.upper)] = Field(unique=True)
    ip_address: Annotated[str | None, PlainValidator(_validate_ipaddress)] = None


class DeviceUpdate(SQLModel):
    account: int | None = None
    store: NonBlankStr = None
    door: NonBlankStr = None
    software_version: str | None = None
    firmware_version: str | None = None
    remote_access_token: str | None = None
    remote_connection_string: str | None = None
    last_seen: datetime | None = None


class DeviceUpdateWithReaders(DeviceUpdate):
    """Extended update model that includes relationship data"""

    readers: list[Reader] | None = None


class Device(DeviceCreate, DeviceUpdate, rx.Model, table=True):
    __tablename__ = "devices"
    __table_args__ = (
        UniqueConstraint("mac_address", name="uq_mac_address"),
        UniqueConstraint("account", "store", "door", name="uq_device_triplet"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    remote_access_requested: bool = False
    status: StatusType = StatusType.OFFLINE

    readers: list[Reader] | None = Relationship(back_populates="device", sa_relationship_kwargs={"lazy": "selectin"})
