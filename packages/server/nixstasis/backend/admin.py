from typing import Any

from fastapi import Request
from reflex.model import Model
from starlette_admin.contrib.sqlmodel import Admin, ModelView

from nixstasis.models import Device, Reader


class NullAsBlankModelView(ModelView):
    async def _arrange_data(
        self,
        request: Request,
        data: dict[str, Any],
        is_edit: bool = False,
    ) -> dict[str, Any]:
        data = await super()._arrange_data(request, data, is_edit)
        for k, v in data.items():
            if isinstance(v, str) and v == "":
                data[k] = None

        return data


admin_dashboard = Admin(Model.get_db_engine(), title="Nixstasis Admin")
admin_dashboard.add_view(NullAsBlankModelView(Device))
admin_dashboard.add_view(NullAsBlankModelView(Reader))
