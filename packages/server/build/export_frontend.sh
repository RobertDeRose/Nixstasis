#!/bin/bash

uv run reflex db migrate
uv run reflex export --frontend-only --no-zip --env prod

mkdir -p build/root-dir/var/www/
mv .web/build/client build/root-dir/var/www/nixstasis
