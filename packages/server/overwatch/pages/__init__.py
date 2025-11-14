"""
Import order is important. The order of import controls the order in the sidebar
"""

from .index import index  # noqa: I001
from .devices import devices
from .settings import settings


__all__ = ["index", "devices", "settings"]  # noqa: RUF022
