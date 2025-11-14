import reflex as rx

from . import styles
from .backend.admin import admin_dashboard
from .backend.api.v1.api import api_router
from .pages import *  # noqa: F403


# Create the app.
app = rx.App(
    style=styles.base_style,
    stylesheets=styles.base_stylesheets,
    api_transformer=api_router,
)

# Admin Dashboard
admin_dashboard.mount_to(app._api)
