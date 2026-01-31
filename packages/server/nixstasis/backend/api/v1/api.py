from fastapi import FastAPI

from nixstasis.backend.api.v1.endpoints import devices, on_demand_tls


api_router = FastAPI(
    title="Nixstasis API",
    description="Allows devices to register and provide information to Nixstasis",
    contact={"name": "Nixstasis Systems Inc.", "url": "https://checkpointsystems.com/"},
    license_info={"name": "Closed Source, Private"},
    generate_unique_id_function=lambda route: route.name,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
)

api_router.include_router(devices.router, prefix="/api/v1/device", tags=["devices"])
api_router.include_router(on_demand_tls.router, include_in_schema=False)
