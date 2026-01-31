import logging
import re

import reflex as rx
from fastapi import APIRouter, HTTPException, Response, status

from nixstasis.models import Device


domain_pattern = re.compile(r"^(auth|nixstasis|frp-router|atom-.*?)\.ab\.checkpoint-device\.com$")
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
def permit_tls(domain: str) -> Response:
    """
    Check if a domain is allowed to issue a TLS certificate.

    This endpoint is used by Caddy's `on_demand_tls` feature. Caddy sends a GET request
    with a `domain` query parameter. If this endpoint returns a 2xx status code, Caddy
    proceeds with obtaining a certificate. If it returns 4xx/5xx, Caddy denies the request.

    Args:
        domain: The domain name requesting a certificate (e.g., "atom-1234.device.<domain>")

    Returns:
        Response: 204 No Content if allowed

    Raises:
        HTTPException: 401 Unauthorized if denied
    """
    if match := domain_pattern.match(domain):
        subdomain = match.group(1)
        ckp_domain = subdomain.startswith("atom-")
        if not ckp_domain or (ckp_domain and _is_valid_subdomain(subdomain)):
            logger.warning("[ALLOWING] %s for TLS", domain)
            return Response(status_code=status.HTTP_204_NO_CONTENT)

    logger.error("[DENYING] %s for TLS", domain)
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)


def _is_valid_subdomain(subdomain: str) -> bool:
    """
    Verify if a subdomain corresponds to a registered device with an active remote connection.

    Args:
        subdomain: The subdomain to check (e.g., "atom-1234")

    Returns:
        bool: True if the device exists and matches the connection string, False otherwise.
    """
    with rx.session() as session:
        return (
            session.exec(Device.select().where(Device.remote_connection_string == subdomain)).one_or_none() is not None
        )
