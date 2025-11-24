import logging
import re

import reflex as rx
from fastapi import APIRouter, HTTPException, Response, status

from nixstasis.models import Device


domain_pattern = re.compile(r"^(auth|nixstasis|atom-.*?)\.ab\.checkpoint-device\.com$")
logger = logging.getLogger(__name__)
router = APIRouter()


@router.get(
    "/permit_tls",
    status_code=204,
    responses={
        # status.HTTP_200_OK: dict(description=None),
        status.HTTP_204_NO_CONTENT: dict(description="The host is permitted"),
        status.HTTP_401_UNAUTHORIZED: dict(description="The host is no permitted"),
    },
)
def permit_tls(domain: str) -> None:
    if match := domain_pattern.match(domain):
        subdomain = match.group(1)
        ckp_domain = subdomain.startswith("atom-")
        if not ckp_domain or (ckp_domain and _is_valid_subdomain(subdomain)):
            logger.warning("[ALLOWING] %s for TLS", domain)
            return Response(status_code=status.HTTP_204_NO_CONTENT)

    logger.error("[DENYING] %s for TLS", domain)
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)


def _is_valid_subdomain(subdomain: str) -> bool:
    with rx.session() as session:
        return (
            session.exec(Device.select().where(Device.remote_connection_string == subdomain)).one_or_none() is not None
        )
